import SwiftUI

public struct PairingModalView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var generatedCode: String = ""
    @State private var inputPairingCode: String = ""
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String? = nil

    var onSubmitCode: (String) -> Void

    public init(onSubmitCode: @escaping (String) -> Void) {
        self.onSubmitCode = onSubmitCode
    }

    public var body: some View {
        VStack(spacing: 20) {
            Text("Add Computer")
                .font(.title2)
                .bold()

            VStack(spacing: 8) {
                Text("This Computer's Pairing Code:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(generatedCode)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(8)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Enter the pairing code shown on the other computer:")
                    .font(.callout)

                TextField("6-digit code (e.g. 839274)", text: $inputPairingCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18, design: .monospaced))
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Connect & Pair") {
                    if inputPairingCode.trimmingCharacters(in: .whitespaces).count == 6 {
                        onSubmitCode(inputPairingCode)
                        dismiss()
                    } else {
                        errorMessage = "Please enter a valid 6-digit pairing code."
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            generatedCode = PairingManager.shared.generatePairingCode()
        }
    }
}
