//
//  SigningQueue.swift
//  Feather
//
//  Serial batch signing queue: enqueues multiple apps,
//  signs them one-by-one with the global signing options.
//

import Foundation
import SwiftUI

@MainActor
final class SigningQueue: ObservableObject {
	static let shared = SigningQueue()

	enum ItemState: String {
		case waiting
		case signing
		case done
		case failed
	}

	struct Item: Identifiable {
		let id: UUID
		let name: String
		var state: ItemState = .waiting
		var errorMessage: String?
	}

	@Published var items: [Item] = []
	@Published var isRunning: Bool = false
	@Published var currentIndex: Int = 0

	private var _pending: [(UUID, AppInfoPresentable)] = []

	var progressText: String {
		guard !items.isEmpty else { return "" }
		return String.localized("Signing %lld of %lld", currentIndex, items.count)
	}

	private init() {}

	// MARK: Enqueue

	func add(apps: [AppInfoPresentable]) {
		for app in apps {
			let id = UUID()
			items.append(Item(id: id, name: app.name ?? "App"))
			_pending.append((id, app))
		}
	}

	func clear() {
		guard !isRunning else { return }
		items.removeAll()
		_pending.removeAll()
		currentIndex = 0
	}

	// MARK: Run

	func start() {
		guard !isRunning, !_pending.isEmpty else { return }
		isRunning = true
		currentIndex = 0
		_processNext()
	}

	private func _processNext() {
		guard !_pending.isEmpty else {
			isRunning = false
			_notifyFinished()
			return
		}

		let (id, app) = _pending.removeFirst()
		currentIndex += 1

		if let index = items.firstIndex(where: { $0.id == id }) {
			items[index].state = .signing
		}

		var certificate: CertificatePair?
		let certIndex = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		if certIndex >= 0 {
			certificate = Storage.shared.getCertificate(for: certIndex)
		}

		let options = OptionsManager.shared.options

		FR.signPackageFile(
			app,
			using: options,
			icon: nil,
			certificate: certificate
		) { [weak self] error in
			DispatchQueue.main.async {
				guard let self else { return }
				if let index = self.items.firstIndex(where: { $0.id == id }) {
					if let error {
						self.items[index].state = .failed
						self.items[index].errorMessage = error.localizedDescription
					} else {
						self.items[index].state = .done
					}
				}
				self._processNext()
			}
		}
	}

	private func _notifyFinished() {
		let failed = items.filter { $0.state == .failed }.count
		let generator = UINotificationFeedbackGenerator()
		generator.notificationOccurred(failed > 0 ? .warning : .success)

		let message = failed > 0
			? String.localized("Batch signing finished with %lld failure(s)", failed)
			: String.localized("Batch signing completed")

		UIAlertController.showAlertWithOk(
			title: .localized("Batch Sign"),
			message: message,
			isCancel: true
		)
	}
}
