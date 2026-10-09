import SwiftUI
import UIKit

public struct IOSPairingModalView: View {
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Banner
                    HStack(spacing: 12) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Secure Device Pairing")
                                .font(.headline)
                            Text("Pair devices to authorize low-latency remote streaming.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.blue.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    )

                    // Card 1: This iPhone's Pairing Code
                    VStack(spacing: 14) {
                        HStack {
                            Label("This iPhone's Code", systemImage: "iphone")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)

                            Spacer()

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                generatedCode = PairingManager.shared.generatePairingCode()
                                ToastManager.shared.showInfo(title: "New Code Generated", message: "Enter this updated code on the remote machine.")
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.blue)
                            }
                        }

                        // Monospaced 6-digit display boxes
                        HStack(spacing: 8) {
                            ForEach(Array(generatedCode.enumerated()), id: \.offset) { index, char in
                                Text(String(char))
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .frame(width: 42, height: 52)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 1.2)
                                    )
                            }
                        }

                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = generatedCode
                                ToastManager.shared.showSuccess(
                                    title: "Code Copied",
                                    message: "Pairing code \(generatedCode) copied to clipboard."
                                )
                            } label: {
                                Label("Copy Code", systemImage: "doc.on.doc.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                            }

                            Text("Enter on Mac to pair")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )

                    // Card 2: Enter Remote Code
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Or Enter Remote Device Code", systemImage: "desktopcomputer")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            TextField("6-digit code (e.g. 839274)", text: $inputPairingCode)
                                .keyboardType(.numberPad)
                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                .disabled(isPairingInProgress)
                                .padding(12)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )

                            if !inputPairingCode.isEmpty {
                                Button {
                                    inputPairingCode = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.title3)
                                }
                            }

                            Button {
                                if let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   pasted.count == 6, pasted.allSatisfy({ $0.isNumber }) {
                                    inputPairingCode = pasted
                                    ToastManager.shared.showSuccess(title: "Code Pasted", message: pasted)
                                } else {
                                    ToastManager.shared.showWarning(title: "Invalid Clipboard", message: "Clipboard does not contain a 6-digit code.")
                                }
                            } label: {
                                Image(systemName: "doc.on.clipboard.fill")
                                    .font(.title3)
                                    .foregroundColor(.blue)
                                    .padding(10)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }

                        if let error = errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(error)
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top, 2)
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )

                    // Security & Encryption Banner
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.subheadline)
                            .foregroundColor(.green)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mutual Cryptographic Verification")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.primary)
                            Text("Pairing exchanges authenticated public keys stored securely in your iOS Keychain.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.green.opacity(0.08))
                    )

                    Spacer(minLength: 20)

                    // Action Button
                    Button {
                        startPairing()
                    } label: {
                        HStack(spacing: 8) {
                            if isPairingInProgress {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "link")
                            }
                            Text(isPairingInProgress ? "Pairing Device..." : "Connect & Pair")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            (isPairingInProgress || inputPairingCode.trimmingCharacters(in: .whitespaces).count != 6) ?
                            LinearGradient(colors: [Color.gray, Color.gray.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                            LinearGradient(colors: [Color.blue, Color(red: 0.15, green: 0.35, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: isPairingInProgress || inputPairingCode.trimmingCharacters(in: .whitespaces).count != 6 ? Color.clear : Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .disabled(isPairingInProgress || inputPairingCode.trimmingCharacters(in: .whitespaces).count != 6)
                }
                .padding(20)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Pair Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        PairingManager.shared.invalidateActiveCode()
                        dismiss()
                    }
                    .disabled(isPairingInProgress)
                }
            }
        }
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
            ToastManager.shared.showError(title: "Invalid Code", message: "Pairing code must be 6 digits.")
            return
        }

        isPairingInProgress = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

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
                    ToastManager.shared.showError(title: "Pairing Failed", message: error.localizedDescription)
                }
            }
        }
    }
}
