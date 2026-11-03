import AVFoundation
import SwiftUI
import UIKit

enum CameraCapturePurpose {
    case meal
    case progress

    var reticle: ScanReticleStyle {
        switch self {
        case .meal: return .meal
        case .progress: return .portrait
        }
    }

    var status: String {
        switch self {
        case .meal: return "SCAN MEAL"
        case .progress: return "CAPTURE"
        }
    }

    var subtitle: String {
        switch self {
        case .meal: return "Food, nutrition label, or barcode"
        case .progress: return "Match your usual lighting and pose"
        }
    }

    var capturingStatus: String { "ANALYZING" }

    var capturingSubtitle: String {
        switch self {
        case .meal: return "Reading the frame"
        case .progress: return "Saving on this device"
        }
    }
}

struct CameraCaptureView: View {
    var purpose: CameraCapturePurpose = .meal
    var onBarcode: ((String) -> Void)?
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller: PhotoCaptureController
    @State private var didFinish = false
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?

    init(
        purpose: CameraCapturePurpose = .meal,
        onBarcode: ((String) -> Void)? = nil,
        onCapture: @escaping (UIImage) -> Void
    ) {
        self.purpose = purpose
        self.onBarcode = onBarcode
        self.onCapture = onCapture
        _controller = StateObject(
            wrappedValue: PhotoCaptureController(scansBarcodes: purpose == .meal && onBarcode != nil)
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch controller.phase {
            case .requesting:
                ProgressView()
                    .tint(.white)
            case .denied:
                CameraPermissionState(onClose: close)
            case .unavailable:
                CameraUnavailableState(
                    title: "Camera unavailable",
                    message: "Use a real iPhone, or pick a photo from your library instead.",
                    onClose: close
                )
            case .ready:
                liveCamera
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task {
            await controller.start()
        }
        .onDisappear {
            countdownTask?.cancel()
            controller.stop()
        }
        .onChange(of: controller.capturedImage) { _, image in
            guard let image, !didFinish else { return }
            didFinish = true
            countdownTask?.cancel()
            if purpose == .meal {
                Task { @MainActor in
                    let code = await FoodPhotoLocalAnalysis.detectBarcode(in: image)
                    if let code, !code.isEmpty {
                        onBarcode?(code)
                    } else {
                        onCapture(image)
                    }
                    dismiss()
                }
            } else {
                onCapture(image)
                dismiss()
            }
        }
        .onChange(of: controller.scannedCode) { _, code in
            guard let code, !code.isEmpty, !didFinish else { return }
            didFinish = true
            countdownTask?.cancel()
            onBarcode?(code)
            dismiss()
        }
    }

    private var liveCamera: some View {
        ZStack {
            CameraPreviewView(session: controller.session, mirrored: controller.isFrontCamera) { point in
                controller.focus(atDevicePoint: point)
            }
            .ignoresSafeArea()

            if let freeze = controller.freezeFrame {
                Image(uiImage: freeze)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.12))
            }

            ScanCameraOverlay(
                style: purpose.reticle,
                isLocked: controller.isCapturing || controller.scannedCode != nil || countdown != nil,
                status: overlayStatus,
                subtitle: overlaySubtitle
            )

            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 92, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 8)
                    .transition(.scale.combined(with: .opacity))
            }

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
    }

    private var topBar: some View {
        HStack {
            CameraGlassButton(systemName: "xmark") {
                close()
            }
            .accessibilityLabel("Close camera")

            Spacer()

            Text(purpose == .meal ? "MACRO SCAN" : "PROGRESS")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            HStack(spacing: 10) {
                if purpose == .progress {
                    CameraGlassButton(systemName: "arrow.triangle.2.circlepath.camera") {
                        countdownTask?.cancel()
                        countdownTask = nil
                        countdown = nil
                        controller.flipCamera()
                    }
                    .disabled(controller.isCapturing)
                    .accessibilityLabel(controller.isFrontCamera ? "Use back camera" : "Use selfie camera")
                }

                CameraGlassButton(
                    systemName: controller.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                    filled: controller.torchOn
                ) {
                    controller.toggleTorch()
                }
                .opacity(controller.torchAvailable ? 1 : 0)
                .disabled(!controller.torchAvailable || controller.isCapturing)
                .accessibilityLabel(controller.torchOn ? "Turn flashlight off" : "Turn flashlight on")
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            Text(bottomHint)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))

            HStack(spacing: 28) {
                if purpose == .progress {
                    Button {
                        toggleCountdown()
                    } label: {
                        Text(countdown == nil ? "5s" : "Stop")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!controller.canCapture && countdown == nil)
                    .accessibilityLabel(countdown == nil ? "Five second timer" : "Cancel timer")
                }

            Button {
                countdownTask?.cancel()
                countdownTask = nil
                countdown = nil
                controller.capturePhoto()
            } label: {
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [BrandTheme.teal, BrandTheme.magenta],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 78, height: 78)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: controller.isCapturing
                                    ? [BrandTheme.teal, BrandTheme.neonBlue]
                                    : [Color.white, Color.white.opacity(0.92)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: controller.isCapturing ? 52 : 64, height: controller.isCapturing ? 52 : 64)
                        .shadow(color: BrandTheme.magenta.opacity(0.45), radius: 12)
                }
            }
            .buttonStyle(.plain)
            .disabled(!controller.canCapture || countdown != nil)
            .accessibilityLabel("Take photo")

                if purpose == .progress {
                    Color.clear.frame(width: 52, height: 52)
                }
            }
        }
        .padding(.bottom, 12)
    }

    private func toggleCountdown() {
        if countdownTask != nil {
            countdownTask?.cancel()
            countdownTask = nil
            countdown = nil
            return
        }
        countdownTask = Task { @MainActor in
            for second in stride(from: 5, through: 1, by: -1) {
                countdown = second
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            countdown = nil
            countdownTask = nil
            controller.capturePhoto()
        }
    }

    private var overlayStatus: String {
        if let countdown { return "\(countdown)" }
        if controller.scannedCode != nil { return "LOCKED" }
        if controller.isCapturing { return purpose.capturingStatus }
        if controller.previewBarcode != nil { return "HOLD STEADY" }
        if !controller.canCapture { return "STARTING" }
        return purpose.status
    }

    private var overlaySubtitle: String {
        if let code = controller.scannedCode { return code }
        if controller.isCapturing { return purpose.capturingSubtitle }
        if controller.previewBarcode != nil { return "Barcode in view" }
        return purpose.subtitle
    }

    private var bottomHint: String {
        if controller.scannedCode != nil { return "Got the barcode" }
        if controller.isCapturing { return "Hold still" }
        if countdown != nil { return "Timer running" }
        if purpose == .meal { return "Point at a barcode, or tap the shutter" }
        return controller.isFrontCamera ? "Selfie · tap 5s to step back" : "Tap 5s, set the phone down"
    }

    private func close() {
        guard !didFinish else { return }
        didFinish = true
        dismiss()
    }
}

final class PhotoCaptureController: NSObject, ObservableObject {
    enum Phase {
        case requesting
        case ready
        case denied
        case unavailable
    }

    let session = AVCaptureSession()

    @Published var phase: Phase = .requesting
    @Published var isCapturing = false
    @Published var sessionRunning = false
    @Published var torchOn = false
    @Published var torchAvailable = false
    @Published var isFrontCamera = false
    @Published var freezeFrame: UIImage?
    @Published var capturedImage: UIImage?
    @Published var scannedCode: String?
    @Published var previewBarcode: String?

    var canCapture: Bool {
        phase == .ready && sessionRunning && !isCapturing && scannedCode == nil
    }

    let scansBarcodes: Bool
    private let sessionQueue = DispatchQueue(label: "funfitness.photo.camera")
    private let metadataQueue = DispatchQueue(label: "funfitness.photo.metadata")
    private let photoOutput = AVCapturePhotoOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private lazy var liveVision = LiveBarcodeVision { [weak self] code in
        self?.lockScannedBarcode(code)
    }
    private var device: AVCaptureDevice?
    private var didConfigure = false
    private var isStopping = false
    private var lastBarcode: String?
    private var didLockBarcode = false

    init(scansBarcodes: Bool = false) {
        self.scansBarcodes = scansBarcodes
        super.init()
    }

    func start() async {
        isStopping = false
        liveVision.restart()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                await MainActor.run { phase = .denied }
                return
            }
        default:
            await MainActor.run { phase = .denied }
            return
        }

        guard RuntimeEnvironment.isCameraAvailable else {
            await MainActor.run { phase = .unavailable }
            return
        }

        let configured = await configureSession()
        guard configured else {
            await MainActor.run { phase = .unavailable }
            return
        }

        // Show the preview before startRunning so the first frames aren't dropped
        // behind a spinner, and the lens can start focusing immediately.
        await MainActor.run { phase = .ready }

        sessionQueue.async { [weak self] in
            guard let self, !self.isStopping else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            if self.scansBarcodes {
                BarcodeMetadata.apply(to: self.metadataOutput)
            }
            DispatchQueue.main.async {
                self.sessionRunning = self.session.isRunning
            }
            if self.scansBarcodes, self.metadataOutput.metadataObjectTypes.isEmpty {
                self.sessionQueue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, !self.isStopping else { return }
                    BarcodeMetadata.apply(to: self.metadataOutput)
                }
            }
        }
    }

    func stop() {
        isStopping = true
        liveVision.stop()
        let torchDevice = device
        sessionQueue.async { [weak self] in
            guard let self, self.isStopping else { return }
            if let torchDevice, torchDevice.torchMode != .off {
                try? torchDevice.lockForConfiguration()
                torchDevice.torchMode = .off
                torchDevice.unlockForConfiguration()
            }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.torchOn = false
        }
    }

    func toggleTorch() {
        guard let device, device.hasTorch else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try device.lockForConfiguration()
                let on = device.torchMode != .on
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.torchOn = on
                }
            } catch {
                DispatchQueue.main.async {
                    self.torchOn = false
                }
            }
        }
    }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isCapturing else { return }
            let next: AVCaptureDevice.Position = self.isFrontCamera ? .back : .front
            guard
                let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: next),
                let input = try? AVCaptureDeviceInput(device: camera)
            else { return }

            self.session.beginConfiguration()
            for existing in self.session.inputs {
                self.session.removeInput(existing)
            }
            guard self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.device = camera
            Self.configureFocus(on: camera)
            self.session.commitConfiguration()

            let front = camera.position == .front
            let torchOK = !front && camera.hasTorch && camera.isTorchAvailable
            DispatchQueue.main.async {
                self.isFrontCamera = front
                self.torchAvailable = torchOK
                if front { self.torchOn = false }
            }
        }
    }

    func focus(atDevicePoint point: CGPoint) {
        let clamped = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        sessionQueue.async { [weak self] in
            guard let device = self?.device else { return }
            guard (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = clamped
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = clamped
                device.exposureMode = .autoExpose
            }
        }
        sessionQueue.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let device = self?.device else { return }
            Self.configureFocus(on: device)
        }
    }

    func capturePhoto() {
        guard canCapture else { return }
        isCapturing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else {
                DispatchQueue.main.async { self?.isCapturing = false }
                return
            }
            let settings = AVCapturePhotoSettings()
            // Settings cannot ask for higher quality than the output's max, or the shutter is ignored.
            settings.photoQualityPrioritization = self.photoOutput.maxPhotoQualityPrioritization
            if self.photoOutput.supportedFlashModes.contains(.off) {
                settings.flashMode = .off
            }
            if let connection = self.photoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = self.device?.position == .front
                }
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureSession() async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }
                if self.didConfigure {
                    continuation.resume(returning: true)
                    return
                }

                self.session.beginConfiguration()
                self.session.automaticallyConfiguresApplicationAudioSession = false
                // 720p opens faster than the photo preset and still reads barcodes.
                if self.session.canSetSessionPreset(.hd1280x720) {
                    self.session.sessionPreset = .hd1280x720
                } else if self.session.canSetSessionPreset(.high) {
                    self.session.sessionPreset = .high
                }

                guard
                    let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                        ?? AVCaptureDevice.default(for: .video),
                    let input = try? AVCaptureDeviceInput(device: camera),
                    self.session.canAddInput(input)
                else {
                    self.session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }

                self.session.addInput(input)
                self.device = camera

                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                    self.photoOutput.maxPhotoQualityPrioritization = .speed
                } else {
                    self.session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }

                if self.scansBarcodes, self.session.canAddOutput(self.metadataOutput) {
                    self.session.addOutput(self.metadataOutput)
                    self.metadataOutput.setMetadataObjectsDelegate(self, queue: self.metadataQueue)
                    self.liveVision.attach(to: self.session)
                }

                Self.configureFocus(on: camera)
                self.session.commitConfiguration()
                self.didConfigure = true

                let torchOK = camera.hasTorch && camera.isTorchAvailable
                DispatchQueue.main.async {
                    self.torchAvailable = torchOK
                }

                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(self.handleRuntimeError),
                    name: .AVCaptureSessionRuntimeError,
                    object: self.session
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(self.handleInterruptionEnded),
                    name: .AVCaptureSessionInterruptionEnded,
                    object: self.session
                )

                continuation.resume(returning: true)
            }
        }
    }

    private static func configureFocus(on device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = true
        }
        device.isSubjectAreaChangeMonitoringEnabled = true
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
        }
    }

    @objc private func handleRuntimeError(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            guard let self, !self.isStopping, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    @objc private func handleInterruptionEnded(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            guard let self, !self.isStopping, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension PhotoCaptureController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let image = Self.image(from: photo, error: error)?.downsampled(maxPixelSize: 2000)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let image else {
                    self.isCapturing = false
                    return
                }
                self.freezeFrame = image
                self.capturedImage = image
            }
        }
    }
}

private extension PhotoCaptureController {
    static func image(from photo: AVCapturePhoto, error: Error?) -> UIImage? {
        if error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            return image
        }
        if let cgImage = photo.cgImageRepresentation() {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}

private extension UIImage {
    func downsampled(maxPixelSize: Int) -> UIImage {
        let longest = max(size.width * scale, size.height * scale)
        guard longest > CGFloat(maxPixelSize) else { return self }
        let ratio = CGFloat(maxPixelSize) / longest
        let newSize = CGSize(width: max(size.width * ratio, 1), height: max(size.height * ratio, 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

extension PhotoCaptureController: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let value = FoodPhotoLocalAnalysis.preferredScan(
            metadataObjects.compactMap { object in
                guard let code = object as? AVMetadataMachineReadableCodeObject,
                      let raw = code.stringValue else { return nil }
                return FoodPhotoLocalAnalysis.ScannedCodeCandidate(
                    raw: raw,
                    isUPCE: code.type == .upce
                )
            }
        )

        guard let value else { return }
        lockScannedBarcode(value)
    }

    private func lockScannedBarcode(_ value: String) {
        metadataQueue.async { [weak self] in
            guard let self, self.scansBarcodes, !self.didLockBarcode else { return }
            self.didLockBarcode = true
            self.liveVision.stop()
            self.lastBarcode = value
            DispatchQueue.main.async {
                guard self.scannedCode == nil else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.scannedCode = value
                self.previewBarcode = value
            }
        }
    }
}
