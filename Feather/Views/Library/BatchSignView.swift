//
//  BatchSignView.swift
//  Feather
//
//  Multi-select app list feeding the signing queue.
//

import SwiftUI
import NimbleViews

struct BatchSignView: View {
	@Environment(\.dismiss) private var _dismiss

	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
		animation: .snappy
	) private var _signedApps: FetchedResults<Signed>

	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _importedApps: FetchedResults<Imported>

	@ObservedObject private var _queue = SigningQueue.shared

	@State private var _selectedUUIDs: Set<String> = []
	@State private var _isRunning = false

	var body: some View {
		NavigationStack {
			List {
				if !_importedApps.isEmpty {
					NBSection(.localized("Imported")) {
						ForEach(_importedApps, id: \.uuid) { app in
							_row(app: app)
						}
					}
				}

				if !_signedApps.isEmpty {
					NBSection(.localized("Signed")) {
						ForEach(_signedApps, id: \.uuid) { app in
							_row(app: app)
						}
					}
				}
			}
			.navigationTitle(.localized("Batch Sign"))
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
					Button(.localized("Sign Selected")) {
						_startBatch()
					}
					.disabled(_selectedUUIDs.isEmpty || _isRunning)
				}
			}
			.overlay {
				if _isRunning {
					_progressOverlay()
				}
			}
			.onDisappear {
				// keep queue running in background of the app
			}
		}
	}

	// MARK: Row

	@ViewBuilder
	private func _row(app: AppInfoPresentable) -> some View {
		let uuid = app.uuid ?? ""
		Button {
			if _selectedUUIDs.contains(uuid) {
				_selectedUUIDs.remove(uuid)
			} else {
				_selectedUUIDs.insert(uuid)
			}
		} label: {
			HStack(spacing: 12) {
				Image(systemName: _selectedUUIDs.contains(uuid) ? "checkmark.circle.fill" : "circle")
					.foregroundColor(_selectedUUIDs.contains(uuid) ? .accentColor : .secondary)

				FRAppIconView(app: app, size: 36)

				VStack(alignment: .leading, spacing: 2) {
					Text(app.name ?? "App")
						.foregroundColor(.primary)
						.lineLimit(1)
					Text(verbatim: app.version ?? "")
						.font(.caption)
						.foregroundColor(.secondary)
				}
			}
		}
		.buttonStyle(.plain)
	}

	// MARK: Progress overlay

	@ViewBuilder
	private func _progressOverlay() -> some View {
		VStack(spacing: 14) {
			ForEach(_queue.items) { item in
				HStack(spacing: 10) {
					switch item.state {
					case .waiting:
						Image(systemName: "clock")
							.foregroundColor(.secondary)
					case .signing:
						ProgressView()
					case .done:
						Image(systemName: "checkmark.circle.fill")
							.foregroundColor(.green)
					case .failed:
						Image(systemName: "xmark.circle.fill")
							.foregroundColor(.red)
					}

					Text(item.name)
						.lineLimit(1)

					Spacer()

					if let error = item.errorMessage {
						Text(error)
							.font(.caption2)
							.foregroundColor(.red)
							.lineLimit(1)
					}
				}
				.padding(.horizontal)
			}

			Text(verbatim: _queue.progressText)
				.font(.footnote)
				.foregroundColor(.secondary)

			Button(.localized("Close")) {
				_isRunning = false
				_queue.clear()
				_dismiss()
			}
			.disabled(_queue.isRunning)
		}
		.padding(.vertical, 20)
		.frame(maxWidth: .infinity)
		.background(
			RoundedRectangle(cornerRadius: 16)
				.fill(.regularMaterial)
				.shadow(color: .black.opacity(0.15), radius: 10, y: 4)
		)
		.padding()
	}

	// MARK: Actions

	private func _startBatch() {
		var apps: [AppInfoPresentable] = []
		for app in _importedApps {
			if let uuid = app.uuid, _selectedUUIDs.contains(uuid) {
				apps.append(app)
			}
		}
		for app in _signedApps {
			if let uuid = app.uuid, _selectedUUIDs.contains(uuid) {
				apps.append(app)
			}
		}

		guard !apps.isEmpty else { return }

		_queue.add(apps: apps)
		_queue.start()
		_isRunning = true
	}
}
