import SwiftUI

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
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("This iPhone's Pairing Code:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(generatedCode)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                    Text("Enter this code on the remote device to authorize pairing.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 16)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter code shown on remote device:")
                        .font(.callout)

                    TextField("6-digit code (e.g. 839274)", text: $inputPairingCode)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .font(.system(size: 20, design: .monospaced))
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

                Spacer()

                Button(action: {
                    startPairing()
                }) {
                    HStack {
                        if isPairingInProgress {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.trailing, 8)
                        }
                        Text("Connect & Pair")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isPairingInProgress || inputPairingCode.trimmingCharacters(in: .whitespaces).count != 6)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
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
