import SwiftUI

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
        VStack(spacing: 20) {
            Text("Add Device")
                .font(.title2)
                .bold()

            VStack(spacing: 8) {
                Text("This Mac's Pairing Code:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(generatedCode)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(8)
                Text("Share this 6-digit code with the device you wish to pair with.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Enter pairing code shown on remote device:")
                    .font(.callout)

                TextField("6-digit code (e.g. 839274)", text: $inputPairingCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18, design: .monospaced))
                    .disabled(isPairingInProgress)
            }

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error)
                }
                .font(.caption)
                .foregroundColor(.red)
            }

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
        .padding(24)
        .frame(width: 440)
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
                }
            }
        }
    }
}
