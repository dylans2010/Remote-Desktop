import SwiftUI

public struct IOSPairingModalView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var generatedCode: String = ""
    @State private var inputPairingCode: String = ""
    @State private var errorMessage: String? = nil

    var onSubmitCode: (String) -> Void

    public init(onSubmitCode: @escaping (String) -> Void) {
        self.onSubmitCode = onSubmitCode
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
                }
                .padding(.top, 16)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter code from remote Mac/device:")
                        .font(.callout)

                    TextField("6-digit code (e.g. 839274)", text: $inputPairingCode)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .font(.system(size: 20, design: .monospaced))
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()

                Button(action: {
                    if inputPairingCode.trimmingCharacters(in: .whitespaces).count == 6 {
                        onSubmitCode(inputPairingCode)
                        dismiss()
                    } else {
                        errorMessage = "Please enter a valid 6-digit pairing code."
                    }
                }) {
                    Text("Connect & Pair")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
            .navigationTitle("Pair Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            generatedCode = PairingManager.shared.generatePairingCode()
        }
    }
}
