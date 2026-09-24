import AVFoundation
import SwiftUI

struct BarcodeScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if RuntimeEnvironment.isCameraAvailable {
                BarcodeScannerRepresentable(
                    onScan: { code in
                        onScan(code)
                        dismiss()
                    },
                    onCancel: { dismiss() }
                )
                .ignoresSafeArea()
            } else {
                BarcodeUnavailableView(onDismiss: { dismiss() })
            }
        }
    }
}

private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let controller = BarcodeScannerViewController()
        controller.onScan = onScan
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "barcode.session")
    private let metadataQueue = DispatchQueue(label: "barcode.metadata")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureDevice: AVCaptureDevice?
    private var didAccept = false
    private var lastUnstableCode: String?
    private var lastUnstableAt: Date?
    private let hintLabel = UILabel()
    private let torchButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureChrome()
        sessionQueue.async { [weak self] in
            self?.prepareSession()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning, self.session.inputs.isEmpty == false else { return }
            self.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        if let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    private func prepareSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.sessionQueue.async { self.configureSession() }
                } else {
                    DispatchQueue.main.async { self.showBlocked("Camera access is off. Enable it in Settings to scan barcodes.") }
                }
            }
        default:
            DispatchQueue.main.async {
                self.showBlocked("Camera access is off. Enable it in Settings to scan barcodes.")
            }
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            DispatchQueue.main.async { self.showBlocked("This device doesn't have a usable camera.") }
            return
        }
        captureDevice = device

        session.beginConfiguration()
        session.automaticallyConfiguresApplicationAudioSession = false
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: metadataQueue)
        let wanted: [AVMetadataObject.ObjectType] = [
            .ean8, .ean13, .upce, .code128, .code39, .code93,
            .itf14, .interleaved2of5, .qr, .pdf417, .dataMatrix,
        ]
        output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }
        session.commitConfiguration()

        configureDevice(device)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let preview = AVCaptureVideoPreviewLayer(session: self.session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = self.view.bounds
            self.view.layer.insertSublayer(preview, at: 0)
            self.previewLayer = preview
            if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        if !session.isRunning {
            session.startRunning()
        }
    }

    private func configureDevice(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            let zoom = min(1.6, device.activeFormat.videoMaxZoomFactor)
            if zoom > 1.01, device.minAvailableVideoZoomFactor <= zoom {
                device.videoZoomFactor = zoom
            }
            DispatchQueue.main.async { [weak self] in
                self?.torchButton.isHidden = !device.hasTorch
            }
        } catch {
            return
        }
    }

    private func configureChrome() {
        let dim = UIView()
        dim.translatesAutoresizingMaskIntoConstraints = false
        dim.isUserInteractionEnabled = false
        dim.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        dim.layer.borderWidth = 2
        dim.layer.cornerRadius = 12
        view.addSubview(dim)

        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.tintColor = .white
        cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancel)

        torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        torchButton.tintColor = .white
        torchButton.addTarget(self, action: #selector(torchTapped), for: .touchUpInside)
        torchButton.translatesAutoresizingMaskIntoConstraints = false
        torchButton.isHidden = true
        view.addSubview(torchButton)

        hintLabel.text = "Point at a product barcode"
        hintLabel.textColor = .white
        hintLabel.font = .systemFont(ofSize: 15, weight: .medium)
        hintLabel.textAlignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            torchButton.centerYAnchor.constraint(equalTo: cancel.centerYAnchor),
            torchButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            torchButton.widthAnchor.constraint(equalToConstant: 44),
            torchButton.heightAnchor.constraint(equalToConstant: 44),
            dim.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dim.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            dim.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.78),
            dim.heightAnchor.constraint(equalToConstant: 150),
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func showBlocked(_ message: String) {
        hintLabel.text = message
        hintLabel.numberOfLines = 0
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func torchTapped() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.captureDevice, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                let enable = device.torchMode != .on
                device.torchMode = enable ? .on : .off
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    let name = enable ? "flashlight.on.fill" : "flashlight.off.fill"
                    self.torchButton.setImage(UIImage(systemName: name), for: .normal)
                }
            } catch {
                return
            }
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didAccept else { return }
        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject,
                  let value = readable.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            if let code = acceptedCode(from: value) {
                didAccept = true
                let generator = UIImpactFeedbackGenerator(style: .medium)
                DispatchQueue.main.async {
                    generator.impactOccurred()
                    self.hintLabel.text = "Got it"
                    self.onScan?(code)
                }
                sessionQueue.async { [weak self] in
                    guard let self, self.session.isRunning else { return }
                    self.session.stopRunning()
                }
                return
            }
        }
    }

    /// Valid GTINs log on the first read. Anything else must repeat so a glitch can't dismiss the scanner.
    private func acceptedCode(from raw: String) -> String? {
        if let code = OpenFoodFactsService.preferredBarcode(from: raw) {
            return code
        }
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 6, digits.count <= 18 else { return nil }
        let now = Date()
        if lastUnstableCode == digits, let lastUnstableAt, now.timeIntervalSince(lastUnstableAt) < 1.2 {
            return digits
        }
        lastUnstableCode = digits
        lastUnstableAt = now
        return nil
    }
}

private struct BarcodeUnavailableView: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Camera unavailable", systemImage: "barcode.viewfinder")
            } description: {
                Text("Use a real iPhone to scan barcodes, or enter a barcode manually.")
            }
            .navigationTitle("Scan barcode")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss() }
                }
            }
        }
    }
}
