import AVFoundation
import SwiftUI

struct BarcodeScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = BarcodeCaptureController()
    @State private var didFinish = false

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
                    message: "Use a real iPhone to scan barcodes, or enter a barcode manually.",
                    onClose: close
                )
            case .ready:
                liveScanner
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task {
            await controller.start()
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: controller.scannedCode) { _, code in
            guard let code, !code.isEmpty, !didFinish else { return }
            didFinish = true
            // Hand the code to the parent before dismiss so the confirm sheet gets it.
            onScan(code)
            dismiss()
        }
    }

    private var liveScanner: some View {
        ZStack {
            CameraPreviewView(session: controller.session)
                .ignoresSafeArea()

            ScanCameraOverlay(
                style: .barcode,
                isLocked: controller.scannedCode != nil,
                status: controller.scannedCode != nil
                    ? "LOCKED"
                    : (controller.isReadingStill ? "READING" : "SCAN CODE"),
                subtitle: controller.scannedCode != nil
                    ? "Got it — pulling nutrition"
                    : (controller.isReadingStill
                        ? "Looking at the bars"
                        : "Center the barcode in the frame")
            )

            VStack {
                HStack {
                    CameraGlassButton(systemName: "xmark") {
                        close()
                    }
                    .accessibilityLabel("Close scanner")

                    Spacer()

                    Text("BARCODE")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .tracking(2.4)
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()

                    CameraGlassButton(
                        systemName: controller.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                        filled: controller.torchOn
                    ) {
                        controller.toggleTorch()
                    }
                    .opacity(controller.torchAvailable ? 1 : 0)
                    .disabled(!controller.torchAvailable)
                    .accessibilityLabel(controller.torchOn ? "Turn flashlight off" : "Turn flashlight on")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                VStack(spacing: 14) {
                    Text(controller.readHint ?? "Fill the box with the bars and hold still")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)

                    Button {
                        controller.captureStill()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(BrandTheme.teal, lineWidth: 3)
                                .frame(width: 72, height: 72)
                            Circle()
                                .fill(controller.isReadingStill ? BrandTheme.teal : Color.white)
                                .frame(width: controller.isReadingStill ? 48 : 58, height: controller.isReadingStill ? 48 : 58)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!controller.canCaptureStill)
                    .accessibilityLabel("Read barcode from a photo")
                }
                .padding(.bottom, 28)
            }
        }
    }

    private func close() {
        guard !didFinish else { return }
        didFinish = true
        dismiss()
    }
}

final class BarcodeCaptureController: NSObject, ObservableObject {
    enum Phase {
        case requesting
        case ready
        case denied
        case unavailable
    }

    let session = AVCaptureSession()

    @Published var phase: Phase = .requesting
    @Published var torchOn = false
    @Published var torchAvailable = false
    @Published var scannedCode: String?
    @Published var isReadingStill = false
    @Published var readHint: String?

    var canCaptureStill: Bool {
        phase == .ready && scannedCode == nil && !isReadingStill
    }

    private let sessionQueue = DispatchQueue(label: "funfitness.barcode.camera")
    private let metadataOutput = AVCaptureMetadataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private lazy var liveVision = LiveBarcodeVision { [weak self] code in
        self?.lockScannedBarcode(code)
    }
    private var device: AVCaptureDevice?
    private var didConfigure = false
    private var isStopping = false
    private var didScan = false
    private var snapAttempts = 0
    private var lastAttemptedCode: String?
    private var lastAttemptAt = CFAbsoluteTime(0)

    func start() async {
        isStopping = false
        snapAttempts = 0
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

        await MainActor.run {
            phase = .ready
            scannedCode = nil
        }

        sessionQueue.async { [weak self] in
            guard let self, !self.isStopping else { return }
            self.didScan = false
            if !self.session.isRunning {
                self.session.startRunning()
            }
            BarcodeMetadata.apply(to: self.metadataOutput)
            if self.metadataOutput.metadataObjectTypes.isEmpty {
                self.sessionQueue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, !self.isStopping else { return }
                    BarcodeMetadata.apply(to: self.metadataOutput)
                }
            }
        }
        scheduleFocusedSnap(after: 1.6)
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

    func captureStill(feedback: Bool = true) {
        guard canCaptureStill else { return }
        isReadingStill = true
        readHint = nil
        if feedback {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.focusNearCenter()
            let deadline = Date().addingTimeInterval(0.85)
            while !self.isStopping, self.device?.isAdjustingFocus == true, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.04)
            }
            guard !self.isStopping, !self.didScan, self.session.isRunning,
                  self.photoOutput.connection(with: .video) != nil else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isReadingStill = false
                    if !self.didScan, !self.isStopping {
                        self.readHint = "Camera isn't ready yet."
                    }
                }
                return
            }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = self.photoOutput.maxPhotoQualityPrioritization
            if let connection = self.photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func scheduleFocusedSnap(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isStopping, self.scannedCode == nil, !self.isReadingStill else { return }
            guard self.snapAttempts < 6 else { return }
            self.snapAttempts += 1
            self.captureStill(feedback: false)
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
                if self.session.canSetSessionPreset(.hd1920x1080) {
                    self.session.sessionPreset = .hd1920x1080
                } else if self.session.canSetSessionPreset(.high) {
                    self.session.sessionPreset = .high
                } else if self.session.canSetSessionPreset(.hd1280x720) {
                    self.session.sessionPreset = .hd1280x720
                }

                guard
                    let camera = Self.barcodeCamera(),
                    let input = try? AVCaptureDeviceInput(device: camera),
                    self.session.canAddInput(input)
                else {
                    self.session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }

                self.session.addInput(input)
                self.device = camera

                guard self.session.canAddOutput(self.metadataOutput) else {
                    self.session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }
                self.session.addOutput(self.metadataOutput)
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: self.sessionQueue)
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                }
                self.liveVision.attach(to: self.session)

                self.configureOptics(on: camera)

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

    /// Ultra-wide stays in focus a few inches from a can. The triple-camera
    /// virtual device switches lenses at that distance and drops the frame.
    private static func barcodeCamera() -> AVCaptureDevice? {
        if let ultra = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
            return ultra
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
    }

    private func configureOptics(on camera: AVCaptureDevice) {
        focusNearCenter(on: camera)
        guard (try? camera.lockForConfiguration()) != nil else { return }
        defer { camera.unlockForConfiguration() }
        let zoom = min(2.0, camera.maxAvailableVideoZoomFactor)
        if zoom > 1.05 {
            camera.videoZoomFactor = zoom
        }
    }

    private func focusNearCenter() {
        guard let device else { return }
        focusNearCenter(on: device)
    }

    private func focusNearCenter(on camera: AVCaptureDevice) {
        guard (try? camera.lockForConfiguration()) != nil else { return }
        defer { camera.unlockForConfiguration() }
        if camera.isAutoFocusRangeRestrictionSupported {
            camera.autoFocusRangeRestriction = .near
        }
        if camera.isFocusPointOfInterestSupported {
            camera.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
        if camera.isFocusModeSupported(.continuousAutoFocus) {
            camera.focusMode = .continuousAutoFocus
        }
        if camera.isSmoothAutoFocusSupported {
            camera.isSmoothAutoFocusEnabled = true
        }
        camera.isSubjectAreaChangeMonitoringEnabled = true
        if camera.isExposurePointOfInterestSupported {
            camera.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
        if camera.isExposureModeSupported(.continuousAutoExposure) {
            camera.exposureMode = .continuousAutoExposure
        }
        if camera.isLowLightBoostSupported {
            camera.automaticallyEnablesLowLightBoostWhenAvailable = true
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

extension BarcodeCaptureController: AVCaptureMetadataOutputObjectsDelegate {
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

        guard let value, value.filter(\.isNumber).count >= 8 else { return }
        lockScannedBarcode(value)
    }
}

extension BarcodeCaptureController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image: UIImage? = {
            if error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
                return image
            }
            if let cgImage = photo.cgImageRepresentation() {
                return UIImage(cgImage: cgImage)
            }
            return nil
        }()
        guard let image else {
            DispatchQueue.main.async { [weak self] in
                self?.isReadingStill = false
                self?.readHint = "Couldn't take the photo. Try again."
            }
            return
        }
        Task { [weak self] in
            let code = await FoodPhotoLocalAnalysis.detectBarcode(in: image)
            await MainActor.run {
                guard let self else { return }
                self.isReadingStill = false
                if let code {
                    self.lockScannedBarcode(code)
                } else {
                    self.readHint = "Hold the bars in the box and keep still."
                    self.scheduleFocusedSnap(after: 1.2)
                }
            }
        }
    }

    fileprivate func lockScannedBarcode(_ value: String) {
        let normalized = BarcodeNormalization.normalizedBarcode(value)
        guard !normalized.isEmpty else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.didScan else { return }
            let now = CFAbsoluteTimeGetCurrent()
            if self.lastAttemptedCode == normalized, now - self.lastAttemptAt < 1.5 {
                return
            }
            self.lastAttemptedCode = normalized
            self.lastAttemptAt = now
            self.didScan = true
            self.liveVision.stop()
            DispatchQueue.main.async {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.scannedCode = value
            }
        }
    }
}
