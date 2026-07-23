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
        try configureSessionForRecording()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
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

    /// Stops recording and returns the final transcript (empty if nothing heard).
    func stopRecording() -> String {
        guard isRecording else { return liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines) }

        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
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
