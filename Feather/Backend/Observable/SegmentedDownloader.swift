//
//  SegmentedDownloader.swift
//  Feather
//
//  Multi-threaded segmented download engine.
//  Splits a file into N segments fetched in parallel via HTTP Range
//  requests, writes each byte range directly into a pre-allocated file,
//  and reports aggregated progress + speed.
//

import Foundation

// MARK: - Engine

final class SegmentedDownloadSession: NSObject {

	typealias ProgressHandler = _ProgressHandler
	typealias CompletionHandler = _CompletionHandler

	enum SegmentError: LocalizedError {
		case cancelled
		case serverError(Int)
		case rangeNotSupported
		case sizeMismatch

		var errorDescription: String? {
			switch self {
			case .cancelled: return "Cancelled"
			case .serverError(let code): return "HTTP \(code)"
			case .rangeNotSupported: return "Range not supported"
			case .sizeMismatch: return "Size mismatch"
			}
		}
	}

	struct Segment {
		var start: Int64
		var end: Int64 // inclusive
		var written: Int64
		var task: URLSessionDataTask?
		var retries: Int = 0
	}

	let url: URL
	let destinationURL: URL
	let threadCount: Int

	private(set) var isCancelled = false
	private(set) var isFinished = false

	private var _session: URLSession!
	private var _segments: [Segment] = []
	private var _taskToSegment: [Int: Int] = [:]
	private var _fileHandle: FileHandle?
	private var _totalBytes: Int64 = 0
	private var _acceptsRanges = false
	private var _downloadedBytes: Int64 = 0
	private var _activeSegments = 0

	// speed calculation
	private var _lastTick = Date()
	private var _lastTickBytes: Int64 = 0
	private var _speed: Int64 = 0

	private let _writeQueue = DispatchQueue(label: "feather.segmented.write")
	private let _lock = NSLock()

	private let _onProgress: ProgressHandler
	private let _onCompletion: CompletionHandler

	// MARK: Init

	init(
		url: URL,
		threadCount: Int = 16,
		onProgress: @escaping ProgressHandler,
		onCompletion: @escaping CompletionHandler
	) {
		self.url = url
		self.threadCount = max(1, min(threadCount, 32))
		self._onProgress = onProgress
		self._onCompletion = onCompletion

		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("FeatherSegmented", isDirectory: true)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		let name = url.lastPathComponent.isEmpty
			? UUID().uuidString
			: url.lastPathComponent
		self.destinationURL = dir.appendingPathComponent(name)

		super.init()
	}

	// MARK: Public

	func start() {
		let config = URLSessionConfiguration.ephemeral
		config.timeoutIntervalForRequest = 30
		config.requestCachePolicy = .reloadIgnoringLocalCacheData
		let queue = OperationQueue()
		queue.maxConcurrentOperationCount = threadCount * 2
		_session = URLSession(configuration: config, delegate: self, delegateQueue: queue)

		_probe()
	}

	func cancel() {
		_lock.lock()
		isCancelled = true
		let tasks = _segments.compactMap { $0.task }
		_lock.unlock()
		tasks.forEach { $0.cancel() }
		_cleanupPartialFile()
	}

	// MARK: Probe

	private func _probe() {
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
		request.timeoutInterval = 20

		let task = _session.dataTask(with: request) { [weak self] _, response, error in
			guard let self else { return }
			if self.isCancelled { return }

			guard error == nil, let http = response as? HTTPURLResponse else {
				DispatchQueue.main.async { self._fail(with: error ?? URLError(.badServerResponse)) }
				return
			}

			let total = Self._extractTotal(response: http)
			let ranged = (http.statusCode == 206)

			DispatchQueue.main.async {
				self._beginDownload(totalBytes: total, acceptsRanges: ranged)
			}
		}
		task.resume()
	}

	private static func _extractTotal(response: HTTPURLResponse) -> Int64 {
		if let contentRange = response.value(forHTTPHeaderField: "Content-Range") {
			// "bytes 0-0/123456"
			let parts = contentRange.split(separator: "/")
			if parts.count == 2, let total = Int64(parts[1]) {
				return total
			}
		}
		let len = response.expectedContentLength
		if len > 0 {
			return len
		}
		return 0
	}

	// MARK: Begin

	private func _beginDownload(totalBytes: Int64, acceptsRanges: Bool) {
		guard !isCancelled else { return }

		let fm = FileManager.default
		try? fm.removeItem(at: destinationURL)

		if totalBytes > 0 && acceptsRanges {
			_acceptsRanges = true
			_totalBytes = totalBytes

			guard fm.createFile(atPath: destinationURL.path, contents: Data()) else {
				_fail(with: URLError(.cannotCreateFile))
				return
			}
			if let handle = try? FileHandle(forWritingTo: destinationURL) {
				_fileHandle = handle
				try? handle.truncate(atOffset: UInt64(totalBytes))
			} else {
				_fail(with: URLError(.cannotCreateFile))
				return
			}

			_buildSegments()
			_launchAllSegments()
		} else {
			// single stream fallback (no range support or unknown size)
			_totalBytes = totalBytes
			_acceptsRanges = false
			guard fm.createFile(atPath: destinationURL.path, contents: nil) else {
				_fail(with: URLError(.cannotCreateFile))
				return
			}
			_fileHandle = try? FileHandle(forWritingTo: destinationURL)
			_startSingleStream()
		}
	}

	// MARK: Segments

	private func _buildSegments() {
		var result: [Segment] = []
		let count = threadCount
		let chunk = _totalBytes / Int64(count)
		var index: Int64 = 0
		for i in 0..<count {
			let start = index
			var end: Int64
			if i == count - 1 {
				end = _totalBytes - 1
			} else {
				end = index + chunk - 1
			}
			if start > end { break }
			result.append(Segment(start: start, end: end, written: 0))
			index = end + 1
		}
		_segments = result
		_activeSegments = result.count
	}

	private func _launchAllSegments() {
		_lock.lock()
		let snapshot = _segments
		_lock.unlock()
		for (idx, _) in snapshot.enumerated() {
			_launchSegment(at: idx)
		}
	}

	private func _launchSegment(at index: Int) {
		_lock.lock()
		guard index < _segments.count, _segments[index].task == nil else {
			_lock.unlock()
			return
		}
		let seg = _segments[index]
		let from = seg.start + seg.written
		let to = seg.end
		var request = URLRequest(url: url)
		request.setValue("bytes=\(from)-\(to)", forHTTPHeaderField: "Range")
		request.timeoutInterval = 30
		let task = _session.dataTask(with: request)
		_segments[index].task = task
		_taskToSegment[task.taskIdentifier] = index
		_lock.unlock()
		task.resume()
	}

	// MARK: Single stream fallback

	private func _startSingleStream() {
		_lock.lock()
		_segments = [Segment(start: 0, end: max(_totalBytes - 1, 0), written: 0)]
		_activeSegments = 1
		_lock.unlock()

		var request = URLRequest(url: url)
		request.timeoutInterval = 30
		let task = _session.dataTask(with: request)
		_lock.lock()
		_segments[0].task = task
		_taskToSegment[task.taskIdentifier] = 0
		_lock.unlock()
		task.resume()
	}

	// MARK: Data write

	fileprivate func _write(_ data: Data, forSegment index: Int) {
		_writeQueue.async { [weak self] in
			guard let self else { return }
			if self.isCancelled || self.isFinished { return }

			self._lock.lock()
			guard index < self._segments.count else {
				self._lock.unlock()
				return
			}
			let offset = self._segments[index].start + self._segments[index].written
			let segStart = self._segments[index].start
			let segEnd = self._segments[index].end
			let segTotal = segEnd - segStart + 1
			self._lock.unlock()

			// cap writes so a misbehaving server cannot spill into the next segment
			var payload = data
			let remaining = segTotal - (offset - segStart)
			if Int64(payload.count) > remaining {
				payload = payload.prefix(Int(max(remaining, 0)))
			}

			if let handle = self._fileHandle {
				handle.seek(toFileOffset: UInt64(offset))
				handle.write(payload)
			}

			var done = false
			self._lock.lock()
			if index < self._segments.count {
				self._segments[index].written += Int64(payload.count)
				let segWritten = self._segments[index].written
				done = segWritten >= segTotal
			}
			self._downloadedBytes += Int64(payload.count)
			self._lock.unlock()

			if done {
				self._segmentDidFinish(index: index)
			}
			self._reportProgress()
		}
	}

	private func _segmentDidFinish(index: Int) {
		_lock.lock()
		if index < _segments.count {
			_segments[index].task = nil
		}
		_activeSegments -= 1
		let remaining = _activeSegments
		_lock.unlock()

		if remaining <= 0 {
			_complete()
		}
	}

	// MARK: Progress / completion

	private func _reportProgress() {
		let now = Date()
		let elapsed = now.timeIntervalSince(_lastTick)
		guard elapsed >= 0.25 else { return }

		_lock.lock()
		let bytes = _downloadedBytes
		_lock.unlock()

		let delta = bytes - _lastTickBytes
		if elapsed > 0 {
			let instant = Int64(Double(delta) / elapsed)
			_speed = _speed == 0 ? instant : Int64(Double(_speed) * 0.6 + Double(instant) * 0.4)
		}
		_lastTick = now
		_lastTickBytes = bytes

		let progress: Double
		if _totalBytes > 0 {
			progress = Double(bytes) / Double(_totalBytes)
		} else {
			progress = 0
		}
		let speed = _speed
		let total = _totalBytes
		DispatchQueue.main.async { [weak self] in
			guard let self, !self.isCancelled, !self.isFinished else { return }
			self._onProgress(progress, bytes, total, speed)
		}
	}

	private func _complete() {
		guard !isCancelled, !isFinished else { return }
		isFinished = true

		_lock.lock()
		let bytes = _downloadedBytes
		let total = _totalBytes
		_lock.unlock()

		if _acceptsRanges && total > 0 && bytes != total {
			_fail(with: SegmentError.sizeMismatch)
			return
		}

		try? _fileHandle?.close()
		_fileHandle = nil
		_session.invalidateAndCancel()
		_session = nil

		let url = self.destinationURL
		DispatchQueue.main.async { [weak self] in
			guard let self, !self.isCancelled else { return }
			self._onCompletion(.success(url))
		}
	}

	fileprivate func _segmentFailed(index: Int, error: Error?) {
		_lock.lock()
		guard !isCancelled, !isFinished, index < _segments.count else {
			_lock.unlock()
			return
		}
		let seg = _segments[index]
		let segStart = seg.start
		let segEnd = seg.end
		let segWritten = seg.written
		let retries = seg.retries
		_segments[index].task = nil
		_segments[index].retries += 1
		_lock.unlock()

		// whole-segment complete already? treat as finish
		if segWritten >= (segEnd - segStart + 1) {
			_segmentDidFinish(index: index)
			return
		}

		if retries < 3 && !isCancelled {
			// retry from where we stopped
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
				guard let self, !self.isCancelled, !self.isFinished else { return }
				self._launchSegment(at: index)
			}
		} else {
			_fail(with: error ?? URLError(.networkConnectionLost))
		}
	}

	private func _fail(with error: Error) {
		guard !isCancelled, !isFinished else { return }
		isFinished = true
		_cleanupPartialFile()
		_session?.invalidateAndCancel()
		_session = nil

		DispatchQueue.main.async { [weak self] in
			guard let self, !self.isCancelled else { return }
			self._onCompletion(.failure(error))
		}
	}

	private func _cleanupPartialFile() {
		try? _fileHandle?.close()
		_fileHandle = nil
		try? FileManager.default.removeItem(at: destinationURL)
	}

	// MARK: Reset downloaded bytes counter used by single stream path

	fileprivate func _trackTaskMapping(taskIdentifier: Int) -> Int? {
		_lock.lock()
		defer { _lock.unlock() }
		return _taskToSegment[taskIdentifier]
	}
}

// MARK: - Callback aliases (kept out of generic context)

typealias _ProgressHandler = (Double, Int64, Int64, Int64) -> Void
typealias _CompletionHandler = (Result<URL, Error>) -> Void

// MARK: - URLSessionDataDelegate

extension SegmentedDownloadSession: URLSessionDataDelegate {

	func urlSession(
		_ session: URLSession,
		dataTask: URLSessionDataTask,
		didReceive response: URLResponse,
		completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
	) {
		if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
			completionHandler(.cancel)
			if let index = _trackTaskMapping(taskIdentifier: dataTask.taskIdentifier) {
				_segmentFailed(index: index, error: SegmentError.serverError(http.statusCode))
			}
			return
		}
		completionHandler(.allow)
	}

	func urlSession(
		_ session: URLSession,
		dataTask: URLSessionDataTask,
		didReceive data: Data
	) {
		guard let index = _trackTaskMapping(taskIdentifier: dataTask.taskIdentifier) else { return }
		_write(data, forSegment: index)
	}

	func urlSession(
		_ session: URLSession,
		task: URLSessionTask,
		didCompleteWithError error: Error?
	) {
		guard let index = _trackTaskMapping(taskIdentifier: task.taskIdentifier) else { return }
		if let error {
			_segmentFailed(index: index, error: error)
		} else {
			// normal completion — verify segment fully written
			_lock.lock()
			var fullyDone = false
			if index < _segments.count {
				let seg = _segments[index]
				fullyDone = seg.written >= (seg.end - seg.start + 1)
			}
			_lock.unlock()

			if fullyDone {
				_segmentDidFinish(index: index)
			} else {
				_segmentFailed(index: index, error: URLError(.networkConnectionLost))
			}
		}
	}
}
