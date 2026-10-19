//
//  DownloadsListView.swift
//  Feather
//
//  Live list of all in-flight & finished downloads with speed.
//

import SwiftUI
import NimbleViews

struct DownloadsListView: View {
	@ObservedObject private var _downloadManager = DownloadManager.shared

	var body: some View {
		Group {
			if _downloadManager.downloads.isEmpty {
				VStack(spacing: 8) {
					Image(systemName: "arrow.down.circle")
						.font(.largeTitle)
						.foregroundColor(.secondary)
					Text(.localized("No files chosen."))
						.foregroundColor(.secondary)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				List {
					ForEach(_downloadManager.downloads) { download in
						DownloadsListRow(download: download)
					}
				}
				.listStyle(.plain)
			}
		}
		.navigationTitle(.localized("Downloads"))
		.navigationBarTitleDisplayMode(.inline)
	}
}

struct DownloadsListRow: View {
	let download: Download
	@State private var progress: Double = 0
	@State private var bytesDownloaded: Int64 = 0
	@State private var totalBytes: Int64 = 0
	@State private var speed: Int64 = 0

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text(download.fileName)
					.font(.subheadline)
					.lineLimit(1)
				Spacer()
				Button {
					DownloadManager.shared.cancelDownload(download)
				} label: {
					Image(systemName: "xmark.circle.fill")
						.foregroundColor(.secondary)
				}
				.buttonStyle(.plain)
			}

			ProgressView(value: max(progress, 0.01))
				.progressViewStyle(.linear)

			HStack {
				Text(verbatim: "\(Int(progress * 100))%")
					.contentTransition(.numericText())
				if speed > 0 {
					Text(verbatim: String.localized("Speed: %@", speed.formattedByteCount))
						.foregroundColor(.accentColor)
				}
				Spacer()
				if totalBytes > 0 {
					Text(verbatim: "\(bytesDownloaded.formattedByteCount) / \(totalBytes.formattedByteCount)")
				}
			}
			.font(.caption)
			.foregroundColor(.secondary)
		}
		.padding(.vertical, 2)
		.onReceive(download.$progress) { self.progress = $0 }
		.onReceive(download.$bytesDownloaded) { self.bytesDownloaded = $0 }
		.onReceive(download.$totalBytes) { self.totalBytes = $0 }
		.onReceive(download.$speed) { self.speed = $0 }
	}
}
