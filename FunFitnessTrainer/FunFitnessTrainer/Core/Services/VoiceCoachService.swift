import AVFoundation
import Speech

/// Speech-to-text for Larry chat (replies are text-only, no TTS).
@MainActor
final class VoiceCoachService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var liveTranscript = ""
    @Published private(set) var isReady = false
    @Published var permissionDenied = false
    @Published var lastError: String?

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

    func startRecording() throws {
        guard isReady, !isRecording else { return }

        lastError = nil
        liveTranscript = ""
        transcriptBox.reset()
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
                if let error, self.isRecording {
                    self.lastError = error.localizedDescription
                }
            }
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    /// Stops recording and returns the recognizer's best transcript.
    /// `formattedString` often looks like "Catalina crunch." — trailing punctuation is removed
    /// before the text is handed to Larry. Cancelling immediately used to drop that final result.
    func stopRecording() async -> String {
        guard isRecording else {
            return FoodItemNaming.normalizedSpeechTranscript(liveTranscript)
        }

        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline {
            let snapshot = transcriptBox.snapshot()
            if snapshot.isFinal, !snapshot.text.isEmpty { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

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
