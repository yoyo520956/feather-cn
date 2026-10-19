//
//  BrowserManager.swift
//  Feather
//
//  In-app browser: multi-tab WKWebView management,
//  bookmarks & history persistence, download interception.
//

import SwiftUI
import WebKit

// MARK: - Models

struct BrowserBookmark: Codable, Identifiable, Hashable {
	var id = UUID()
	var title: String
	var urlString: String
}

struct BrowserHistoryItem: Codable, Identifiable, Hashable {
	var id = UUID()
	var title: String
	var urlString: String
	var date: Date
}

// MARK: - Tab

@MainActor
final class BrowserTab: ObservableObject, Identifiable {
	let id = UUID()
	let webView: WKWebView
	private var _coordinator: BrowserTabCoordinator?

	@Published var title: String = ""
	@Published var urlString: String = ""
	@Published var progress: Double = 0
	@Published var canGoBack: Bool = false
	@Published var canGoForward: Bool = false
	@Published var hasLoaded: Bool = false

	init(url: URL? = nil) {
		let configuration = WKWebViewConfiguration()
		configuration.allowsInlineMediaPlayback = true
		webView = WKWebView(frame: .zero, configuration: configuration)
		webView.allowsBackForwardNavigationGestures = true

		let coordinator = BrowserTabCoordinator(webView: webView)
		coordinator.tab = self
		_coordinator = coordinator
		webView.navigationDelegate = coordinator
		webView.uiDelegate = coordinator
		_coordinator?.startObserving()

		if let url {
			load(url: url)
		}
	}

	func load(url: URL) {
		hasLoaded = true
		let request = URLRequest(url: url)
		webView.load(request)
	}

	func reload() {
		if webView.url != nil {
			webView.reload()
		}
	}

	func stopLoading() {
		webView.stopLoading()
	}

	func goBack() {
		webView.goBack()
	}

	func goForward() {
		webView.goForward()
	}
}

// MARK: - Coordinator (delegates + KVO)

final class BrowserTabCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

	weak var tab: BrowserTab?
	private let _webView: WKWebView
	private var _observations: [NSKeyValueObservation] = []

	init(webView: WKWebView) {
		_webView = webView
		super.init()
	}

	func startObserving() {
		_observations.append(
			_webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
				DispatchQueue.main.async {
					self?.tab?.progress = webView.estimatedProgress
				}
			}
		)
		_observations.append(
			_webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
				DispatchQueue.main.async {
					self?.tab?.title = webView.title ?? ""
				}
			}
		)
		_observations.append(
			_webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
				DispatchQueue.main.async {
					self?.tab?.urlString = webView.url?.absoluteString ?? ""
					self?.tab?.canGoBack = webView.canGoBack
					self?.tab?.canGoForward = webView.canGoForward
				}
			}
		)
	}

	// MARK: Navigation delegate

	func webView(
		_ webView: WKWebView,
		decidePolicyFor navigationAction: WKNavigationAction,
		decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
	) {
		guard let url = navigationAction.request.url else {
			decisionHandler(.allow)
			return
		}

		if BrowserURLHelper.isArchiveURL(url) {
			decisionHandler(.cancel)
			DispatchQueue.main.async {
				DownloadManager.shared.startDownload(from: url)
				UINotificationFeedbackGenerator().notificationOccurred(.success)
			}
			return
		}

		decisionHandler(.allow)
	}

	func webView(
		_ webView: WKWebView,
		decidePolicyFor navigationResponse: WKNavigationResponse,
		decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
	) {
		if !navigationResponse.canShowMIMEType {
			if let url = navigationResponse.response.url {
				decisionHandler(.cancel)
				DispatchQueue.main.async {
					DownloadManager.shared.startDownload(from: url)
					UINotificationFeedbackGenerator().notificationOccurred(.success)
				}
				return
			}
		}
		decisionHandler(.allow)
	}

	func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
		DispatchQueue.main.async {
			guard let tab = self.tab else { return }
			tab.hasLoaded = true
			if let url = webView.url {
				let title = webView.title ?? url.host ?? url.absoluteString
				BrowserManager.shared.addHistory(title: title, urlString: url.absoluteString)
			}
		}
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		DispatchQueue.main.async {
			guard let tab = self.tab else { return }
			tab.canGoBack = webView.canGoBack
			tab.canGoForward = webView.canGoForward
		}
	}

	// MARK: UI delegate

	func webView(
		_ webView: WKWebView,
		createWebViewWith configuration: WKWebViewConfiguration,
		for navigationAction: WKNavigationAction,
		windowFeatures: WKWindowFeatures
	) -> WKWebView? {
		// open target=_blank links in the same webview
		if let url = navigationAction.request.url {
			webView.load(URLRequest(url: url))
		}
		return nil
	}
}

// MARK: - URL helper

enum BrowserURLHelper {
	static let archiveExtensions: Set<String> = [
		"ipa", "zip", "deb", "tipa", "dmg", "pkg",
		"rar", "7z", "tar", "gz", "xz", "bz2", "dylib",
	]

	static func isArchiveURL(_ url: URL) -> Bool {
		let ext = url.pathExtension.lowercased()
		guard !ext.isEmpty else { return false }
		return archiveExtensions.contains(ext)
	}

	static func normalize(_ text: String) -> URL? {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.isEmpty { return nil }

		if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
			if scheme == "http" || scheme == "https" {
				return url
			}
		}

		let looksLikeHost = trimmed.contains(".") && !trimmed.contains(" ")
		if looksLikeHost {
			return URL(string: "https://" + trimmed)
		}

		return searchURL(for: trimmed)
	}

	static func searchURL(for query: String) -> URL? {
		let engine = UserDefaults.standard.string(forKey: "feather.searchEngine") ?? "bing"
		let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
		switch engine {
		case "baidu":
			return URL(string: "https://www.baidu.com/s?wd=" + encoded)
		case "google":
			return URL(string: "https://www.google.com/search?q=" + encoded)
		case "duckduckgo":
			return URL(string: "https://duckduckgo.com/?q=" + encoded)
		default:
			return URL(string: "https://www.bing.com/search?q=" + encoded)
		}
	}
}

// MARK: - Manager

@MainActor
final class BrowserManager: ObservableObject {
	static let shared = BrowserManager()

	@Published var tabs: [BrowserTab] = []
	@Published var selectedTabID: UUID?

	@Published var bookmarks: [BrowserBookmark] = [] {
		didSet { _saveBookmarks() }
	}
	@Published var history: [BrowserHistoryItem] = [] {
		didSet { _saveHistory() }
	}

	private let _bookmarksKey = "feather.browser.bookmarks"
	private let _historyKey = "feather.browser.history"

	var selectedTab: BrowserTab? {
		tabs.first(where: { $0.id == selectedTabID })
	}

	private init() {
		if let data = UserDefaults.standard.data(forKey: _bookmarksKey),
		   let decoded = try? JSONDecoder().decode([BrowserBookmark].self, from: data) {
			bookmarks = decoded
		}
		if let data = UserDefaults.standard.data(forKey: _historyKey),
		   let decoded = try? JSONDecoder().decode([BrowserHistoryItem].self, from: data) {
			history = decoded
		}
	}

	// MARK: Tabs

	func newTab(url: URL? = nil) -> BrowserTab {
		let tab = BrowserTab(url: url)
		tabs.append(tab)
		selectedTabID = tab.id
		return tab
	}

	func closeTab(_ id: UUID) {
		guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
		let tab = tabs[index]
		tab.stopLoading()
		tabs.remove(at: index)

		if selectedTabID == id {
			if tabs.isEmpty {
				selectedTabID = nil
				_ = newTab()
			} else {
				selectedTabID = tabs[max(0, index - 1)].id
			}
		}
	}

	// MARK: Bookmarks

	func isBookmarked(_ urlString: String) -> Bool {
		bookmarks.contains(where: { $0.urlString == urlString })
	}

	func toggleBookmark(title: String, urlString: String) {
		guard !urlString.isEmpty else { return }
		if let index = bookmarks.firstIndex(where: { $0.urlString == urlString }) {
			bookmarks.remove(at: index)
		} else {
			bookmarks.insert(
				BrowserBookmark(title: title.isEmpty ? urlString : title, urlString: urlString),
				at: 0
			)
		}
	}

	func removeBookmark(_ bookmark: BrowserBookmark) {
		bookmarks.removeAll(where: { $0.id == bookmark.id })
	}

	private func _saveBookmarks() {
		if let data = try? JSONEncoder().encode(bookmarks) {
			UserDefaults.standard.set(data, forKey: _bookmarksKey)
		}
	}

	// MARK: History

	func addHistory(title: String, urlString: String) {
		guard let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" else { return }
		// collapse consecutive duplicates of the same page
		if !history.isEmpty, history[0].urlString == urlString {
			history[0].date = Date()
			return
		}
		history.insert(
			BrowserHistoryItem(title: title, urlString: urlString, date: Date()),
			at: 0
		)
		if history.count > 200 {
			history.removeLast(history.count - 200)
		}
	}

	func clearHistory() {
		history.removeAll()
	}

	private func _saveHistory() {
		if let data = try? JSONEncoder().encode(history) {
			UserDefaults.standard.set(data, forKey: _historyKey)
		}
	}
}
