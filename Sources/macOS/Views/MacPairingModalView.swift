import SwiftUI
import AppKit

public struct MacPairingModalView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var generatedCode: String = ""
    @State private var inputPairingCode: String = ""
    @State private var isPairingInProgress: Bool = false
    @State private var errorMessage: String? = nil

    var onDevicePaired: (Device) -> Void

    public init(onDevicePaired: @escaping (Device) -> Void) {
        self.onDevicePaired = onDevicePaired
    }

    public var body: some View {
        VStack(spacing: 18) {
            // Header Banner
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Secure Device Pairing")
                        .font(.headline)
                    Text("Pair devices to authorize low-latency remote desktop streaming.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
            )

            // Card 1: This Mac's Pairing Code
            VStack(spacing: 12) {
                HStack {
                    Label("This Mac's Pairing Code", systemImage: "macbook")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        generatedCode = PairingManager.shared.generatePairingCode()
                        MacToastManager.shared.showInfo(
                            title: "New Code Generated",
                            message: "Enter this updated code on the remote machine."
                        )
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Generate fresh pairing code")
                }

                // Monospaced 6-digit boxes
                HStack(spacing: 8) {
                    ForEach(Array(generatedCode.enumerated()), id: \.offset) { index, char in
                        Text(String(char))
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                            .frame(width: 38, height: 48)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1.2)
                            )
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(generatedCode, forType: .string)
                        MacToastManager.shared.showSuccess(
                            title: "Code Copied",
                            message: "Pairing code \(generatedCode) copied to clipboard."
                        )
                    } label: {
                        Label("Copy Code", systemImage: "doc.on.doc.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Text("Enter on remote device to establish trust")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            // Card 2: Enter Remote Code
            VStack(alignment: .leading, spacing: 10) {
                Label("Or Enter Remote Device Code", systemImage: "iphone.and.arrow.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("6-digit code (e.g. 839274)", text: $inputPairingCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .disabled(isPairingInProgress)

                    if !inputPairingCode.isEmpty {
                        Button {
                            inputPairingCode = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        if let pasted = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           pasted.count == 6, pasted.allSatisfy({ $0.isNumber }) {
                            inputPairingCode = pasted
                            MacToastManager.shared.showSuccess(title: "Code Pasted", message: pasted)
                        } else {
                            MacToastManager.shared.showWarning(title: "Invalid Clipboard", message: "Clipboard does not contain a 6-digit code.")
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.bordered)
                    .help("Paste code from clipboard")
                }

                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            // Security Banner
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Mutual Cryptographic Verification")
                        .font(.caption.weight(.semibold))
                    Text("Pairing exchanges authenticated public keys stored securely in your macOS Keychain.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.08))
            )

            Divider()

            // Actions
            HStack {
                Button("Cancel") {
                    PairingManager.shared.invalidateActiveCode()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isPairingInProgress)

                Spacer()

                if isPairingInProgress {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                }

                Button("Connect & Pair") {
                    startPairing()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isPairingInProgress || inputPairingCode.trimmingCharacters(in: .whitespaces).count != 6)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            generatedCode = PairingManager.shared.generatePairingCode()
        }
        .onDisappear {
            PairingManager.shared.invalidateActiveCode()
        }
    }

    private func startPairing() {
        let code = inputPairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6 && code.allSatisfy({ $0.isNumber }) else {
            errorMessage = "Please enter a valid 6-digit numeric pairing code."
            MacToastManager.shared.showError(title: "Invalid Code", message: "Pairing code must be 6 digits.")
            return
        }

        isPairingInProgress = true
        errorMessage = nil

        Task {
            do {
                let device = try await PairingManager.shared.pairWithDevice(using: code)
                DispatchQueue.main.async {
                    self.isPairingInProgress = false
                    self.onDevicePaired(device)
                    self.dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isPairingInProgress = false
                    self.errorMessage = error.localizedDescription
                    MacToastManager.shared.showError(title: "Pairing Failed", message: error.localizedDescription)
                }
            }
        }
    }
}
