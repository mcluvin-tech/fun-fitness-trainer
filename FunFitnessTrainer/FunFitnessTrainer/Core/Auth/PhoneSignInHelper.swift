import Foundation

enum PhoneSignInStep {
    case enterPhone
    case enterOTP
}

@MainActor
final class PhoneSignInHelper: ObservableObject {
    @Published var showSheet = false
    @Published var phoneInput = ""
    @Published var otpInput = ""
    @Published var step: PhoneSignInStep = .enterPhone
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var normalizedPhone: String?

    func present() {
        guard AppConfig.hasBackend else {
            errorMessage = "Connect Supabase in Secrets.plist to sign in with your phone."
            return
        }
        reset()
        showSheet = true
    }

    func reset() {
        phoneInput = ""
        otpInput = ""
        step = .enterPhone
        isLoading = false
        errorMessage = nil
        normalizedPhone = nil
    }

    func sendOTP() async {
        errorMessage = nil
        let rawDigits = phoneInput.filter(\.isNumber).count
        let hasPlus = phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+")
        guard let phone = Self.normalizePhone(phoneInput) else {
            // #region agent log
            AgentDebugLog.emit(
                hypothesisId: "A",
                location: "PhoneSignInHelper.sendOTP",
                message: "normalizePhone failed",
                data: ["rawDigitCount": rawDigits, "hasPlus": hasPlus, "hasBackend": AppConfig.hasBackend]
            )
            // #endregion
            errorMessage = "Enter a valid phone number with country code (e.g. +1 555 123 4567)."
            return
        }
        // #region agent log
        AgentDebugLog.emit(
            hypothesisId: "A",
            location: "PhoneSignInHelper.sendOTP",
            message: "normalizePhone ok, calling sendPhoneOTP",
            data: [
                "rawDigitCount": rawDigits,
                "hasPlus": hasPlus,
                "normalizedLength": phone.count,
                "normalizedPrefix": String(phone.prefix(2)),
                "hasBackend": AppConfig.hasBackend,
            ]
        )
        // #endregion
        normalizedPhone = phone
        isLoading = true
        defer { isLoading = false }

        do {
            try await SupabaseService.shared.sendPhoneOTP(phone: phone)
            // #region agent log
            AgentDebugLog.emit(
                hypothesisId: "D",
                location: "PhoneSignInHelper.sendOTP",
                message: "sendPhoneOTP succeeded",
                data: ["step": "enterOTP"]
            )
            // #endregion
            step = .enterOTP
            otpInput = ""
        } catch {
            let ns = error as NSError
            // #region agent log
            AgentDebugLog.emit(
                hypothesisId: "D",
                location: "PhoneSignInHelper.sendOTP",
                message: "sendPhoneOTP threw",
                data: [
                    "errorDomain": ns.domain,
                    "errorCode": ns.code,
                    "errorDescription": error.localizedDescription,
                ]
            )
            // #endregion
            // Temporary debug suffix so a screenshot still gives us the URLError code.
            errorMessage = "\(error.localizedDescription) [\(ns.domain):\(ns.code)]"
        }
    }

    func verifyOTP() async {
        errorMessage = nil
        guard let phone = normalizedPhone else {
            errorMessage = "Send a verification code first."
            return
        }
        let code = otpInput.trimmingCharacters(in: .whitespaces)
        guard code.count >= 4 else {
            errorMessage = "Enter the code from your text message."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await SupabaseService.shared.verifyPhoneOTP(phone: phone, token: code)
            showSheet = false
            reset()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func backToPhoneEntry() {
        step = .enterPhone
        otpInput = ""
        errorMessage = nil
    }

    /// Formats user input to E.164 when possible (defaults US numbers to +1).
    static func normalizePhone(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("+") {
            let digits = trimmed.dropFirst().filter(\.isNumber)
            guard digits.count >= 10, digits.count <= 15 else { return nil }
            return "+\(digits)"
        }

        let digits = trimmed.filter(\.isNumber)
        if digits.count == 10 {
            return "+1\(digits)"
        }
        if digits.count == 11, digits.first == "1" {
            return "+\(digits)"
        }
        return nil
    }
}
