//
//  CertExpiryMonitor.swift
//  Feather
//
//  Watches certificate expiration dates, shows in-app banners
//  and fires local notifications before certs expire.
//

import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class CertExpiryMonitor: ObservableObject {
	static let shared = CertExpiryMonitor()

	struct ExpiringCert: Identifiable, Hashable {
		let id: String          // cert uuid
		let nickname: String
		let expiration: Date
		let daysLeft: Int
		let expired: Bool
	}

	@Published var expiring: [ExpiringCert] = []

	@AppStorage("feather.certExpiry.notificationsDisabled")
	private var _notificationsDisabled: Bool = false

	private let _dismissedKey = "feather.certExpiry.dismissed"
	private let _lastNotifiedKey = "feather.certExpiry.lastNotified"

	private init() {}

	// MARK: Refresh

	func refresh() {
		let certs = Storage.shared.getAllCertificates()
		let now = Date()
		let calendar = Calendar.current

		var dismissed = Set(UserDefaults.standard.stringArray(forKey: _dismissedKey) ?? [])

		var result: [ExpiringCert] = []
		for cert in certs {
			guard !cert.revoked, let expiration = cert.expiration else { continue }
			let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expiration)).day ?? 0
			guard days <= 7 else { continue }

			let uuid = cert.uuid ?? UUID().uuidString
			if days < 0 {
				// expired certs always show, never dismissible silently
				dismissed.remove(uuid)
			}
			guard !dismissed.contains(uuid) else { continue }

			result.append(
				ExpiringCert(
					id: uuid,
					nickname: cert.nickname ?? .localized("Certificate"),
					expiration: expiration,
					daysLeft: days,
					expired: days < 0
				)
			)
		}

		self.expiring = result
		UserDefaults.standard.set(Array(dismissed), forKey: _dismissedKey)

		if !_notificationsDisabled {
			_scheduleNotifications(for: result)
		}
	}

	// MARK: Dismissal

	func dismiss(certID: String) {
		var dismissed = Set(UserDefaults.standard.stringArray(forKey: _dismissedKey) ?? [])
		dismissed.insert(certID)
		UserDefaults.standard.set(Array(dismissed), forKey: _dismissedKey)
		withAnimation {
			expiring.removeAll(where: { $0.id == certID })
		}
	}

	// MARK: Notifications

	private func _scheduleNotifications(for certs: [ExpiringCert]) {
		guard !certs.isEmpty else { return }

		let center = UNUserNotificationCenter.current()
		center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
			guard granted else { return }

			let formatter = DateFormatter()
			formatter.dateFormat = "yyyy-MM-dd"

			let dayStamp = formatter.string(from: Date())

			for cert in certs {
				let notifyKey = "\(self._lastNotifiedKey).\(cert.id)"
				let lastNotified = UserDefaults.standard.string(forKey: notifyKey)
				guard lastNotified != dayStamp else { continue }

				let content = UNMutableNotificationContent()
				if cert.expired {
					content.title = String.localized("Certificate Expired")
				} else if cert.daysLeft == 0 {
					content.title = String.localized("Expires today")
				} else {
					content.title = String.localized("Certificate Expiring Soon")
				}
				content.body = String.localized("Expires in %lld days", max(cert.daysLeft, 0))
					+ " · " + cert.nickname
				content.sound = .default

				let request = UNNotificationRequest(
					identifier: "certExpiry.\(cert.id).\(dayStamp)",
					content: content,
					trigger: nil
				)
				center.add(request)
				UserDefaults.standard.set(dayStamp, forKey: notifyKey)
			}
		}
	}
}
