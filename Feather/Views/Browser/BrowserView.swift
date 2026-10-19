//
//  BrowserView.swift
//  Feather
//
//  In-app browser tab: tab strip, address bar, start page,
//  bookmarks / history / downloads sheets.
//

import SwiftUI
import WebKit
import NimbleViews

// MARK: - WebView representable

struct BrowserWebViewRepresentable: UIViewRepresentable {
	let tab: BrowserTab

	func makeUIView(context: Context) -> WKWebView {
		tab.webView
	}

	func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Main view

struct BrowserView: View {
	@StateObject private var _manager = BrowserManager.shared
	@State private var _addressText: String = ""
	@State private var _isLibraryPresenting = false
	@State private var _isDownloadsPresenting = false
	@FocusState private var _addressFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			_tabStrip()
			_addressBar()

			if let tab = _manager.selectedTab {
				if tab.hasLoaded {
					BrowserWebViewRepresentable(tab: tab)
				} else {
					_startPage()
				}
			} else {
				_emptyState()
			}
		}
		.safeAreaInset(edge: .bottom) {
			_bottomToolbar()
		}
		.sheet(isPresented: $_isLibraryPresenting) {
			BrowserLibraryView()
		}
		.sheet(isPresented: $_isDownloadsPresenting) {
			NavigationView {
				DownloadsListView()
			}
		}
		.onAppear {
			if _manager.tabs.isEmpty {
				_ = _manager.newTab()
			}
			_syncAddressText()
		}
		.onChange(of: _manager.selectedTabID) { _ in
			_syncAddressText()
		}
	}

	// MARK: Tab strip

	@ViewBuilder
	private func _tabStrip() -> some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 6) {
				ForEach(_manager.tabs) { tab in
					HStack(spacing: 6) {
						Button {
							_manager.selectedTabID = tab.id
						} label: {
							Text(tab.title.isEmpty ? .localized("New Tab") : tab.title)
								.font(.caption)
								.lineLimit(1)
								.frame(maxWidth: 120)
						}
						.buttonStyle(.plain)
						.foregroundColor(_manager.selectedTabID == tab.id ? .primary : .secondary)

						Button {
							_manager.closeTab(tab.id)
						} label: {
							Image(systemName: "xmark")
								.font(.caption2)
								.foregroundColor(.secondary)
						}
						.buttonStyle(.plain)
					}
					.padding(.horizontal, 10)
					.padding(.vertical, 6)
					.background(
						Capsule().fill(
							_manager.selectedTabID == tab.id
								? Color.accentColor.opacity(0.18)
								: Color.secondary.opacity(0.10)
						)
					)
				}

				Button {
					_ = _manager.newTab()
				} label: {
					Image(systemName: "plus")
						.font(.caption)
						.padding(.horizontal, 8)
						.padding(.vertical, 6)
						.background(Capsule().fill(Color.secondary.opacity(0.10)))
				}
				.buttonStyle(.plain)
			}
			.padding(.horizontal)
			.padding(.vertical, 4)
		}
	}

	// MARK: Address bar

	@ViewBuilder
	private func _addressBar() -> some View {
		VStack(spacing: 0) {
			HStack(spacing: 8) {
				Button {
					_manager.selectedTab?.goBack()
				} label: {
					Image(systemName: "chevron.left")
						.frame(width: 24)
				}
				.disabled(_manager.selectedTab?.canGoBack != true)

				Button {
					_manager.selectedTab?.goForward()
				} label: {
					Image(systemName: "chevron.right")
						.frame(width: 24)
				}
				.disabled(_manager.selectedTab?.canGoForward != true)

				TextField(
					.localized("Search or enter address"),
					text: $_addressText
				)
				.textFieldStyle(.roundedBorder)
				.font(.subheadline)
				.autocorrectionDisabled()
				.keyboardType(.URL)
				.focused($_addressFocused)
				.submitLabel(.go)
				.onSubmit {
					_loadAddress()
				}

				Button {
					_manager.selectedTab?.reload()
				} label: {
					Image(systemName: "arrow.clockwise")
						.frame(width: 24)
				}
			}
			.padding(.horizontal)
			.padding(.vertical, 6)

			if let tab = _manager.selectedTab, tab.progress > 0.01, tab.progress < 1.0 {
				ProgressView(value: tab.progress)
					.progressViewStyle(.linear)
					.frame(height: 2)
			}
		}
	}

	// MARK: Bottom toolbar

	@ViewBuilder
	private func _bottomToolbar() -> some View {
		HStack(spacing: 28) {
			Button {
				_isLibraryPresenting = true
			} label: {
				Image(systemName: "star")
			}

			Spacer()

			Button {
				_shareCurrentPage()
			} label: {
				Image(systemName: "square.and.arrow.up")
			}
			.disabled(_manager.selectedTab?.hasLoaded != true)

			Spacer()

			Button {
				_toggleBookmark()
			} label: {
				Image(
					systemName: (_bookmarkActive() ? "star.fill" : "star")
				)
			}

			Spacer()

			Button {
				_isDownloadsPresenting = true
			} label: {
				Image(systemName: "arrow.down.circle")
			}
		}
		.font(.system(size: 17))
		.padding(.horizontal, 24)
		.padding(.vertical, 8)
		.background(.bar)
	}

	// MARK: Start page

	@ViewBuilder
	private func _startPage() -> some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				Label(.localized("Bookmarks"), systemImage: "star.fill")
					.font(.headline)
					.padding(.horizontal)

				if _manager.bookmarks.isEmpty {
					Text(.localized("No Bookmarks"))
						.font(.subheadline)
						.foregroundColor(.secondary)
						.padding(.horizontal)
				} else {
					LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
						ForEach(_manager.bookmarks) { bookmark in
							Button {
								_openBookmark(bookmark)
							} label: {
								VStack(alignment: .leading, spacing: 4) {
									Text(bookmark.title)
										.font(.subheadline)
										.lineLimit(1)
									Text(verbatim: URL(string: bookmark.urlString)?.host ?? bookmark.urlString)
										.font(.caption2)
										.foregroundColor(.secondary)
										.lineLimit(1)
								}
								.frame(maxWidth: .infinity, alignment: .leading)
								.padding(10)
								.background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.10)))
							}
							.buttonStyle(.plain)
							.foregroundColor(.primary)
						}
					}
					.padding(.horizontal)
				}
			}
			.padding(.vertical)
		}
	}

	// MARK: Empty state

	@ViewBuilder
	private func _emptyState() -> some View {
		VStack(spacing: 10) {
			Image(systemName: "safari")
				.font(.system(size: 44))
				.foregroundColor(.secondary)
			Text(.localized("Browser"))
				.font(.headline)
				.foregroundColor(.secondary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	// MARK: Actions

	private func _loadAddress() {
		_addressFocused = false
		guard let tab = _manager.selectedTab else { return }
		guard let url = BrowserURLHelper.normalize(_addressText) else { return }
		tab.load(url: url)
		_syncAddressText()
	}

	private func _openBookmark(_ bookmark: BrowserBookmark) {
		guard let url = URL(string: bookmark.urlString) else { return }
		if let tab = _manager.selectedTab {
			tab.load(url: url)
		} else {
			_ = _manager.newTab(url: url)
		}
	}

	private func _toggleBookmark() {
		guard let tab = _manager.selectedTab, let urlString = tab.webView.url?.absoluteString, !urlString.isEmpty else { return }
		_manager.toggleBookmark(title: tab.title, urlString: urlString)
	}

	private func _bookmarkActive() -> Bool {
		guard let urlString = _manager.selectedTab?.webView.url?.absoluteString else { return false }
		return _manager.isBookmarked(urlString)
	}

	private func _shareCurrentPage() {
		guard let url = _manager.selectedTab?.webView.url else { return }
		UIActivityViewController.show(activityItems: [url])
	}

	private func _syncAddressText() {
		if let tab = _manager.selectedTab, !tab.urlString.isEmpty {
			_addressText = tab.urlString
		}
	}
}

// MARK: - Bookmarks + History library

struct BrowserLibraryView: View {
	@StateObject private var _manager = BrowserManager.shared
	@Environment(\.dismiss) private var _dismiss
	@State private var _section = 0

	var body: some View {
		NavigationView {
			VStack(spacing: 0) {
				Picker("", selection: $_section) {
					Text(.localized("Bookmarks")).tag(0)
					Text(.localized("History")).tag(1)
				}
				.pickerStyle(.segmented)
				.padding()

				if _section == 0 {
					_bookmarksList()
				} else {
					_historyList()
				}
			}
			.navigationTitle(.localized("Browser"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					Button {
						_dismiss()
					} label: {
						Image(systemName: "xmark")
					}
				}
				ToolbarItem(placement: .navigationBarTrailing) {
					if _section == 1 {
						Button(.localized("Clear History")) {
							_manager.clearHistory()
						}
					}
				}
			}
		}
	}

	@ViewBuilder
	private func _bookmarksList() -> some View {
		if _manager.bookmarks.isEmpty {
			_placeholder(.localized("No Bookmarks"))
		} else {
			List {
				ForEach(_manager.bookmarks) { bookmark in
					_row(title: bookmark.title, urlString: bookmark.urlString)
						.swipeActions {
							Button(role: .destructive) {
								_manager.removeBookmark(bookmark)
							} label: {
								Label(.localized("Delete"), systemImage: "trash")
							}
						}
				}
			}
			.listStyle(.plain)
		}
	}

	@ViewBuilder
	private func _historyList() -> some View {
		if _manager.history.isEmpty {
			_placeholder(.localized("History"))
		} else {
			List {
				ForEach(_manager.history) { item in
					_row(title: item.title, urlString: item.urlString)
				}
			}
			.listStyle(.plain)
		}
	}

	@ViewBuilder
	private func _row(title: String, urlString: String) -> some View {
		Button {
			if let url = URL(string: urlString) {
				_manager.selectedTab?.load(url: url)
			}
			_dismiss()
		} label: {
			VStack(alignment: .leading, spacing: 2) {
				Text(title.isEmpty ? urlString : title)
					.foregroundColor(.primary)
					.lineLimit(1)
				Text(verbatim: urlString)
					.font(.caption)
					.foregroundColor(.secondary)
					.lineLimit(1)
			}
		}
		.buttonStyle(.plain)
	}

	@ViewBuilder
	private func _placeholder(_ text: String) -> some View {
		VStack(spacing: 8) {
			Image(systemName: "tray")
				.font(.largeTitle)
				.foregroundColor(.secondary)
			Text(verbatim: text)
				.foregroundColor(.secondary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
