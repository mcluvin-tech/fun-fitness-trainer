import AVFoundation
import Speech

/// Where a voice log is. Listening can start from any other phase, including while the last reply is up.
enum VoiceTurnPhase: String, Equatable, Sendable {
    case idle
    case listening
    case processing
    case speaking
}

/// Pure transitions for back-to-back voice logs. Hardware is not involved, so tests can drive it.
struct VoiceTurnMachine: Equatable, Sendable {
    private(set) var phase: VoiceTurnPhase = .idle
    private(set) var turn: Int = 0

    /// Starts a new utterance. A late reply for an older turn must not move the phase.
    mutating func beginListening() -> Int {
        turn += 1
        phase = .listening
        return turn
    }

    mutating func beginProcessing() {
        guard phase == .listening else { return }
        phase = .processing
    }

    /// Shows Larry's reply only if this turn is still the one the user is waiting on.
    mutating func beginSpeaking(for turn: Int) -> Bool {
        guard self.turn == turn else { return false }
        guard phase == .processing || phase == .listening else { return false }
        phase = .speaking
        return true
    }

    /// Mic tap while Larry is answering. The previous lookup may keep running.
    mutating func interruptSpeaking() -> Int {
        beginListening()
    }

    mutating func finishToIdle() {
        guard phase != .listening else { return }
        phase = .idle
    }

    mutating func recoverFromRecognizerError() {
        phase = .idle
        turn += 1
    }

    mutating func timedOut() {
        phase = .idle
        turn += 1
    }
}

enum VoiceCoachError: LocalizedError {
    case notReady

    var errorDescription: String? {
        "Speech recognition isn't ready yet."
    }
}

/// Speech-to-text for Larry chat. Replies are on screen. A new listen always rebuilds the engine.
@MainActor
final class VoiceCoachService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var phase: VoiceTurnPhase = .idle
    @Published private(set) var liveTranscript = ""
    @Published private(set) var isReady = false
    @Published var permissionDenied = false
    @Published var lastError: String?

    private var machine = VoiceTurnMachine()
    private var acceptingStop = false
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    /// Updated on the recognition queue, read when the mic stops. Not the MainActor transcript,
    /// which can still be empty if stop wins the race against the UI update.
    private let transcriptBox = SpeechTranscriptBox()

    func prepare() async {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            lastError = "Speech recognition isn't available on this device."
            return
        }

        let speechOK = await requestSpeechAuthorization()
        let micOK = await requestMicrophoneAuthorization()
        permissionDenied = !speechOK || !micOK
        isReady = speechOK && micOK && !permissionDenied
    }

    /// Tears the previous request down and starts a new one. Safe while a reply or lookup is still in flight.
    @discardableResult
    func startRecording() throws -> Int {
        guard isReady else {
            publish { $0.recoverFromRecognizerError() }
            throw VoiceCoachError.notReady
        }

        let turn = publish { $0.beginListening() }
        lastError = nil
        liveTranscript = ""
        transcriptBox.reset()
        acceptingStop = false
        resetCapture()

        do {
            try configureSessionForRecording()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = false
            recognitionRequest = request

            let box = transcriptBox
            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                if let result {
                    box.update(result.bestTranscription.formattedString, isFinal: result.isFinal)
                }
                if error != nil {
                    box.markFinished()
                }
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.liveTranscript = result.bestTranscription.formattedString
                    }
                    if let error, !self.acceptingStop, self.machine.phase == .listening, self.machine.turn == turn {
                        self.lastError = error.localizedDescription
                        self.resetCapture()
                        self.deactivateSession()
                        self.publish { $0.recoverFromRecognizerError() }
                        self.isRecording = false
                    }
                }
            }

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            return turn
        } catch {
            resetCapture()
            deactivateSession()
            isRecording = false
            publish { $0.recoverFromRecognizerError() }
            throw error
        }
    }

    /// Ignores a reply that belongs to an older tap.
    func claimSpeaking(for turn: Int) -> Bool {
        let accepted = publish { $0.beginSpeaking(for: turn) }
        return accepted
    }

    func finishSpeaking() {
        publish { $0.finishToIdle() }
    }

    /// Listening hung. Only the turn that is still listening is reset.
    func timeoutIfStill(_ turn: Int) {
        guard machine.turn == turn, machine.phase == .listening else { return }
        resetCapture()
        deactivateSession()
        isRecording = false
        publish { $0.timedOut() }
        lastError = "Listening timed out. Tap the mic to try again."
    }

    private var tapInstalled = false

    /// Stops recording and returns the recognizer's best transcript.
    /// `formattedString` often looks like "Catalina crunch." — trailing punctuation is removed
    /// before the text is handed to Larry. Cancelling immediately used to drop that final result.
    func stopRecording() async -> String {
        let turn = machine.turn
        let wasRecording = isRecording || machine.phase == .listening
        guard wasRecording else {
            return FoodItemNaming.normalizedSpeechTranscript(liveTranscript)
        }

        acceptingStop = true
        isRecording = false
        publish { $0.beginProcessing() }
        recognitionRequest?.endAudio()

        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline {
            let snapshot = transcriptBox.snapshot()
            if snapshot.isFinal, !snapshot.text.isEmpty { break }
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                break
            }
        }

        guard machine.turn == turn else {
            return FoodItemNaming.normalizedSpeechTranscript(transcriptBox.snapshot().text)
        }
        resetCapture()
        deactivateSession()
        acceptingStop = false

        let captured = transcriptBox.snapshot().text
        let visible = liveTranscript
        let raw = captured.isEmpty ? visible : captured
        return FoodItemNaming.normalizedSpeechTranscript(raw)
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func configureSessionForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Drops the tap, request, and task so the next utterance can install a new tap.
    private func resetCapture() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    @discardableResult
    private func publish<T>(_ change: (inout VoiceTurnMachine) -> T) -> T {
        let value = change(&machine)
        phase = machine.phase
        return value
    }

}

/// Recognition callbacks are not on the main actor. The mic stop reads this box
/// instead of waiting for a queued UI update that may not have run yet.
private final class SpeechTranscriptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var isFinal = false

    func reset() {
        lock.lock()
        text = ""
        isFinal = false
        lock.unlock()
    }

    func update(_ text: String, isFinal: Bool) {
        lock.lock()
        self.text = text
        if isFinal { self.isFinal = true }
        lock.unlock()
    }

    func markFinished() {
        lock.lock()
        isFinal = true
        lock.unlock()
    }

    func snapshot() -> (text: String, isFinal: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (text, isFinal)
    }
}
