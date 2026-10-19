//
//  LANImportView.swift
//  Feather
//
//  Wi-Fi LAN import UI: start/stop server, QR code, uploaded files.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import NimbleViews

struct LANImportView: View {
	@StateObject private var _server = LANImportServer.shared
	@State private var _serverURL: URL?

	var body: some View {
		Form {
			_sectionServer()
			_sectionQR()
			_sectionFiles()
		}
		.navigationTitle(.localized("LAN Import"))
		.onDisappear {
			if case .running = _server.state {
				// keep serving so the user can continue uploading from the sheet
			}
		}
	}

	// MARK: Server control

	@ViewBuilder
	private func _sectionServer() -> some View {
		NBSection(.localized("Server")) {
			switch _server.state {
			case .idle:
				Button {
					_server.start()
					_serverURL = _server.serverURL()
				} label: {
					Label(.localized("Start Server"), systemImage: "play.fill")
				}
			case .running:
				Button(role: .destructive) {
					_server.stop()
					_serverURL = nil
				} label: {
					Label(.localized("Stop Server"), systemImage: "stop.fill")
				}
				if let url = _serverURL {
					LabeledContent(.localized("Server"), value: url.absoluteString)
						.font(.footnote)
						.textSelection(.enabled)
				}
			case .failed(let message):
				Label(message, systemImage: "exclamationmark.triangle.fill")
					.foregroundColor(.red)
					.font(.footnote)
				Button {
					_server.stop()
					_serverURL = nil
				} label: {
					Label(.localized("Close"), systemImage: "xmark")
				}
			}

			Toggle(isOn: $_server.autoImport) {
				Label(.localized("Auto Import"), systemImage: "square.and.arrow.down.on.square")
			}
		} footer: {
			Text(.localized("Scan to upload from your computer"))
		}
	}

	// MARK: QR

	@ViewBuilder
	private func _sectionQR() -> some View {
		if case .running = _server.state, let url = _serverURL {
			NBSection(.localized("Upload")) {
				VStack(spacing: 10) {
					if let image = Self._qrImage(for: url.absoluteString) {
						Image(uiImage: image)
							.interpolation(.none)
							.resizable()
							.scaledToFit()
							.frame(width: 190, height: 190)
							.cornerRadius(12)
					}
					Text(.localized("Scan to upload from your computer"))
						.font(.footnote)
						.foregroundColor(.secondary)
						.multilineTextAlignment(.center)
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 8)
			}
		}
	}

	// MARK: Files

	@ViewBuilder
	private func _sectionFiles() -> some View {
		NBSection(.localized("Downloaded Files")) {
			if _server.uploadedFileNames.isEmpty {
				Text(.localized("No files uploaded yet"))
					.foregroundColor(.secondary)
					.font(.footnote)
			} else {
				ForEach(_server.uploadedFileNames, id: \.self) { name in
					HStack {
						Image(systemName: _icon(for: name))
							.foregroundColor(.accentColor)
						Text(name)
							.lineLimit(1)
						Spacer()
						Button {
							_server.deleteFile(named: name)
						} label: {
							Image(systemName: "trash")
								.foregroundColor(.red)
						}
						.buttonStyle(.borderless)
					}
				}
			}
		}
	}

	private func _icon(for name: String) -> String {
		if name.lowercased().hasSuffix(".ipa") { return "app.badge.fill" }
		return "doc.fill"
	}

	// MARK: QR generation

	private static func _qrImage(for string: String) -> UIImage? {
		let filter = CIFilter.qrCodeGenerator()
		filter.message = Data(string.utf8)
		filter.correctionLevel = "M"

		guard let output = filter.outputImage else { return nil }
		let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))

		let context = CIContext()
		if let cgImage = context.createCGImage(scaled, from: scaled.extent) {
			return UIImage(cgImage: cgImage)
		}
		return nil
	}
}
