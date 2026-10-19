//
//  StorageCleanerView.swift
//  Feather
//
//  Shows reclaimable cache/temp sizes with one-tap cleaning.
//

import SwiftUI
import NimbleViews

struct StorageCleanerView: View {
	struct Item: Identifiable {
		let id: String
		let titleKey: String
		let icon: String
		let url: URL
		let size: Int64
		let isSystemTemp: Bool
	}

	@State private var _items: [Item] = []
	@State private var _isCleaning = false
	@State private var _freedText: String?

	var body: some View {
		Form {
			NBSection(.localized("Storage Cleaner")) {
				if _items.isEmpty {
					HStack {
						ProgressView()
						Text(.localized("Waiting"))
							.foregroundColor(.secondary)
					}
				} else {
					ForEach(_items) { item in
						HStack(spacing: 12) {
							Image(systemName: item.icon)
								.foregroundColor(.accentColor)
								.frame(width: 24)
							Text(.localized(item.titleKey))
							Spacer()
							Text(verbatim: item.size.formattedByteCount)
								.foregroundColor(.secondary)
								.monospacedDigit()
						}
					}
				}
			} footer: {
				Text(verbatim: _footerText())
			}

			NBSection {
				Button {
					_cleanAll()
				} label: {
					HStack {
						Spacer()
						if _isCleaning {
							ProgressView()
						} else {
							Label(.localized("Clean All"), systemImage: "trash")
								.foregroundColor(.red)
						}
						Spacer()
					}
				}
				.disabled(_isCleaning || _items.isEmpty)

				if let freed = _freedText {
					Text(verbatim: freed)
						.font(.footnote)
						.foregroundColor(.green)
						.frame(maxWidth: .infinity)
				}
			}
		}
		.navigationTitle(.localized("Storage Cleaner"))
		.task {
			_recompute()
		}
	}

	// MARK: Footer

	private func _footerText() -> String {
		let total = _items.reduce(Int64(0)) { $0 + $1.size }
		return total.formattedByteCount
	}

	// MARK: Scan

	private func _recompute() {
		var result: [Item] = []

		let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
		let tmp = FileManager.default.temporaryDirectory

		if let caches {
			result.append(
				Item(
					id: "caches",
					titleKey: "Cache",
					icon: "memorychip",
					url: caches,
					size: Self._directorySize(caches),
					isSystemTemp: true
				)
			)
		}
		result.append(
			Item(
				id: "tmp",
				titleKey: "Temporary Files",
				icon: "clock.arrow.circlepath",
				url: tmp,
				size: Self._directorySize(tmp),
				isSystemTemp: true
			)
		)

		_items = result.filter { $0.size > 0 }
	}

	// MARK: Clean

	private func _cleanAll() {
		_isCleaning = true

		var before: Int64 = 0
		for item in _items {
			before += item.size
		}

		DispatchQueue.global().async {
			for item in self._items {
				guard item.isSystemTemp else { continue }
				let contents = (try? FileManager.default.contentsOfDirectory(
					at: item.url,
					includingPropertiesForKeys: nil
				)) ?? []
				// do not nuke the folder itself (system may rely on it existing)
				for entry in contents {
					try? FileManager.default.removeItem(at: entry)
				}
			}

			DispatchQueue.main.async {
				self._isCleaning = false
				let freed = before
				self._freedText = String.localized("Freed %@", freed.formattedByteCount)
				self._recompute()
			}
		}
	}

	// MARK: Helpers

	private static func _directorySize(_ url: URL) -> Int64 {
		let contents = (try? FileManager.default.contentsOfDirectory(
			at: url,
			includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
			options: []
		)) ?? []

		var total: Int64 = 0
		for entry in contents {
			let values = try? entry.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
			if values?.isDirectory == true {
				total += _directorySize(entry)
			} else {
				total += Int64(values?.fileSize ?? 0)
			}
		}
		return total
	}
}
