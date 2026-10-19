//
//  LANImportServer.swift
//  Feather
//
//  LAN import: hosts a small HTTP server (Vapor) so a computer
//  browser can upload IPA/archive files straight into Feather.
//  Uploads are streamed to disk (never buffered fully in memory).
//

import Foundation
import Vapor
import NIOFoundationCompat
import SwiftUI

final class LANImportServer: ObservableObject {
	static let shared = LANImportServer()

	enum ServerState: Equatable {
		case idle
		case running(port: Int)
		case failed(String)
	}

	@Published var state: ServerState = .idle
	@Published var uploadedFileNames: [String] = []
	@Published var autoImport: Bool = true
	@Published var totalUploadedBytes: Int64 = 0

	let preferredPort = 8765

	private var _app: Application?
	private var _uploadDir: URL {
		FileManager.default.temporaryDirectory
			.appendingPathComponent("FeatherLANUploads", isDirectory: true)
	}

	private init() {
		try? FileManager.default.createDirectory(at: _uploadDir, withIntermediateDirectories: true)
		refreshUploadedFiles()
	}

	// MARK: Control

	func start() {
		guard case .idle = state else { return }

		// ensure Vapor logging system is bootstrapped (shared with ServerInstaller)
		let _ = ServerInstaller.env

		var env = Environment.production
		env.arguments = ["vapor"]
		let app = Application(env)
		app.threadPool = .init(numberOfThreads: 2)
		app.http.server.configuration.hostname = "0.0.0.0"
		app.http.server.configuration.port = preferredPort
		app.routes.defaultMaxBodySize = "2gb"

		_routes(app)

		do {
			try app.server.start()
			_app = app
			DispatchQueue.main.async { self.state = .running(port: self.preferredPort) }
		} catch {
			_app = nil
			let message = error.localizedDescription
			DispatchQueue.main.async { self.state = .failed(message) }
		}
	}

	func stop() {
		_app?.server.shutdown()
		_app?.shutdown()
		_app = nil
		DispatchQueue.main.async { self.state = .idle }
	}

	// MARK: Routes

	private func _routes(_ app: Application) {
		app.get { _ in
			Response(
				status: .ok,
				headers: ["Content-Type": "text/html; charset=utf-8"],
				body: .init(string: Self.uploadPageHTML)
			)
		}

		// streaming upload: POST /upload?name=xxx.ipa
		app.on(.POST, "upload", body: .stream) { [weak self] req -> EventLoopFuture<Response> in
			guard let self else {
				return req.eventLoop.makeSucceededFuture(Response(status: .internalServerError))
			}

			let rawName = req.query[String.self, at: "name"] ?? "upload.bin"
			let safeName = rawName.replacingOccurrences(of: "/", with: "_")
				.replacingOccurrences(of: "..", with: "_")
			let destination = self._uploadDir.appendingPathComponent(safeName)

			FileManager.default.createFile(atPath: destination.path, contents: Data())
			guard let handle = try? FileHandle(forWritingTo: destination) else {
				return req.eventLoop.makeSucceededFuture(Response(status: .internalServerError))
			}

			var total: Int64 = 0
			let promise = req.eventLoop.makePromise(of: Response.self)

			req.body.drain { result -> EventLoopFuture<Void> in
				switch result {
				case .buffer(let buffer):
					let data = Data(buffer: buffer)
					handle.seek(toFileOffset: UInt64(total))
					handle.write(data)
					total += Int64(data.count)
					return req.eventLoop.makeSucceededVoidFuture()
				case .end:
					try? handle.close()

					let finalTotal = total
					let finalName = safeName
					DispatchQueue.main.async {
						self.totalUploadedBytes += finalTotal
						if !self.uploadedFileNames.contains(finalName) {
							self.uploadedFileNames.insert(finalName, at: 0)
						}
					}

					// auto import ipa archives straight into the library
					if self.autoImport && safeName.lowercased().hasSuffix(".ipa") {
						let url = destination
						DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
							FR.handlePackageFile(url) { _ in }
						}
						NSLog("[Feather][LAN] auto importing %@", safeName)
					}

					promise.succeed(Response(status: .ok, body: .init(string: "OK \(finalTotal)")))
					return req.eventLoop.makeSucceededVoidFuture()
				case .error(let error):
					try? handle.close()
					promise.fail(error)
					return req.eventLoop.makeSucceededVoidFuture()
				}
			}

			return promise.futureResult
		}

		app.get("files") { [weak self] req async throws -> Response in
			guard let self else { return Response(status: .internalServerError) }
			let contents = (try? FileManager.default.contentsOfDirectory(
				at: self._uploadDir,
				includingPropertiesForKeys: nil
			)) ?? []
			let names = contents.map { $0.lastPathComponent }.sorted()

			struct FilesPayload: Content {
				var files: [String]
			}
			let payload = FilesPayload(files: names)
			let data = try JSONEncoder().encode(payload)
			return Response(
				status: .ok,
				headers: ["Content-Type": "application/json"],
				body: .init(data: data)
			)
		}

		app.get("download") { req async throws -> Response in
			let rawName = req.query[String.self, at: "name"] ?? ""
			let safeName = rawName.replacingOccurrences(of: "/", with: "_")
				.replacingOccurrences(of: "..", with: "_")
			let fileURL = self._uploadDir.appendingPathComponent(safeName)
			guard FileManager.default.fileExists(atPath: fileURL.path) else {
				return Response(status: .notFound)
			}
			return req.fileio.streamFile(at: fileURL.path)
		}
	}

	// MARK: Files

	func refreshUploadedFiles() {
		let contents = (try? FileManager.default.contentsOfDirectory(
			at: _uploadDir,
			includingPropertiesForKeys: nil
		)) ?? []
		uploadedFileNames = contents
			.map { $0.lastPathComponent }
			.sorted()
	}

	func deleteFile(named name: String) {
		try? FileManager.default.removeItem(at: _uploadDir.appendingPathComponent(name))
		refreshUploadedFiles()
	}

	// MARK: LAN address

	func lanIPAddress() -> String? {
		var address: String?
		var ifaddr: UnsafeMutablePointer<ifaddrs>?
		guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }

		var ptr: UnsafeMutablePointer<ifaddrs>? = first
		while let current = ptr {
			let interface = current.pointee
			if let sa = interface.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
				let name = String(cString: interface.ifa_name)
				if name.hasPrefix("en") {
					var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
					if getnameinfo(
						sa,
						socklen_t(sa.pointee.sa_len),
						&host,
						socklen_t(host.count),
						nil,
						0,
						NI_NUMERICHOST
					) == 0 {
						address = String(cString: host)
						break
					}
				}
			}
			ptr = current.pointee.ifa_next
		}
		freeifaddrs(ifaddr)
		return address
	}

	func serverURL() -> URL? {
		if case .running = state {
			if let ip = lanIPAddress() {
				return URL(string: "http://\(ip):\(preferredPort)")
			}
			return URL(string: "http://127.0.0.1:\(preferredPort)")
		}
		return nil
	}

	// MARK: Upload page HTML

	static let uploadPageHTML: String = """
	<!DOCTYPE html>
	<html lang="zh">
	<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>Feather 局域网导入</title>
	<style>
		body { font-family: -apple-system, sans-serif; background:#0d0d12; color:#eee;
			display:flex; justify-content:center; padding:40px 16px; }
		.card { max-width:520px; width:100%; }
		h1 { font-size:22px; } h1 span { color:#848ef9; }
		.drop { border:2px dashed #555; border-radius:14px; padding:36px 16px;
			text-align:center; margin:18px 0; cursor:pointer; }
		.drop:hover { border-color:#848ef9; }
		.row { display:flex; justify-content:space-between; padding:10px 0;
			border-bottom:1px solid #222; font-size:14px; }
		.bar { height:6px; background:#222; border-radius:3px; margin-top:8px; }
		.bar i { display:block; height:100%; width:0; background:#848ef9; border-radius:3px; }
		button { background:#848ef9; color:#fff; border:none; border-radius:8px;
			padding:10px 18px; font-size:15px; }
		input[type=file] { display:none; }
	</style>
	</head>
	<body>
	<div class="card">
		<h1><span>Feather</span> 局域网导入</h1>
		<div class="drop" onclick="document.getElementById('f').click()">
			<b>点击选择文件上传</b><br>
			<small>支持 IPA / ZIP / DEB · 可多选 · 直传到手机 Feather</small>
		</div>
		<div class="bar" id="barWrap" style="display:none"><i id="bar"></i></div>
		<p id="status"></p>
		<div id="list"></div>
	</div>
	<input type="file" id="f" multiple accept=".ipa,.zip,.deb,.tipa,.dylib">
	<script>
	const f = document.getElementById('f');
	const statusEl = document.getElementById('status');
	const bar = document.getElementById('bar');
	const barWrap = document.getElementById('barWrap');
	f.onchange = async () => {
		for (const file of f.files) {
			await new Promise((resolve) => {
				const xhr = new XMLHttpRequest();
				xhr.open('POST', '/upload?name=' + encodeURIComponent(file.name));
				barWrap.style.display = 'block';
				xhr.upload.onprogress = (e) => {
					if (e.lengthComputable) {
						bar.style.width = Math.round(e.loaded / e.total * 100) + '%';
						statusEl.textContent = file.name + '  ' +
							(e.loaded / 1048576).toFixed(1) + ' / ' +
							(e.total / 1048576).toFixed(1) + ' MB';
					}
				};
				xhr.onload = () => {
					statusEl.textContent = '✅ ' + file.name + ' 上传完成';
					bar.style.width = '0';
					resolve();
				};
				xhr.onerror = () => { statusEl.textContent = '❌ ' + file.name + ' 上传失败'; resolve(); };
				xhr.send(file);
			});
		}
		f.value = '';
	};
	</script>
	</body>
	</html>
	"""
}
