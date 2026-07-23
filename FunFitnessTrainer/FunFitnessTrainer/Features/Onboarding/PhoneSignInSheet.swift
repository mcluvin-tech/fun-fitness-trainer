import SwiftUI

struct PhoneSignInSheet: View {
    @ObservedObject var helper: PhoneSignInHelper

    var body: some View {
        NavigationStack {
            Form {
                switch helper.step {
                case .enterPhone:
                    Section {
                        TextField("Phone number", text: $helper.phoneInput)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                    } footer: {
                        Text("Include country code, e.g. +1 for US numbers. We'll text you a one-time code.")
                    }
                case .enterOTP:
                    Section {
                        TextField("Verification code", text: $helper.otpInput)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    } footer: {
                        Text("Enter the 6-digit code we sent to your phone.")
                    }
                }

                if let err = helper.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Phone sign-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        helper.showSheet = false
                        helper.reset()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if helper.isLoading {
                        ProgressView()
                    } else if helper.step == .enterPhone {
                        Button("Send code") {
                            Task { await helper.sendOTP() }
                        }
                        .disabled(helper.phoneInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button("Verify") {
                            Task { await helper.verifyOTP() }
                        }
                        .disabled(helper.otpInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if helper.step == .enterOTP {
                    Button("Use a different number") {
                        helper.backToPhoneEntry()
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
