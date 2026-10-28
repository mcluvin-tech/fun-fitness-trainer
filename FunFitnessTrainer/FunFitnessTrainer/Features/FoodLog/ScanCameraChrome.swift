import AVFoundation
import SwiftUI

enum ScanReticleStyle {
    case meal
    case barcode
    case portrait

    var cornerRadius: CGFloat {
        switch self {
        case .barcode: return 16
        case .meal, .portrait: return 22
        }
    }
}

enum BarcodeMetadata {
    static let types: [AVMetadataObject.ObjectType] = [
        .ean13, .ean8, .upce, .code128, .pdf417, .dataMatrix, .qr,
    ]

    /// Call after the session is running. Available types are empty before that.
    static func apply(to output: AVCaptureMetadataOutput) {
        let supported = output.availableMetadataObjectTypes
        let selected = types.filter { supported.contains($0) }
        guard !selected.isEmpty else { return }
        output.metadataObjectTypes = selected
    }
}

/// Samples the preview and runs the still-image barcode detector.
/// AVFoundation's live scanner skips codes that run into the edge of the package.
final class LiveBarcodeVision: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "funfitness.barcode.vision", qos: .userInitiated)
    private let textQueue = DispatchQueue(label: "funfitness.barcode.text", qos: .userInitiated)
    private let onCode: (String) -> Void
    private var busy = false
    private var textBusy = false
    private var lastScan = CFAbsoluteTimeGetCurrent() - 10
    private var lastText = CFAbsoluteTimeGetCurrent() - 10
    private var enabled = true

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
    }

    func attach(to session: AVCaptureSession) {
        guard session.canAddOutput(output) else { return }
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        session.addOutput(output)
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    func restart() {
        enabled = true
    }

    func stop() {
        enabled = false
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard enabled else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let orientation = Self.orientation(for: connection.videoRotationAngle)
        let now = CFAbsoluteTimeGetCurrent()

        if !busy, now - lastScan > 0.18 {
            busy = true
            lastScan = now
            let code = FoodPhotoLocalAnalysis.readLiveBarcode(in: buffer, orientation: orientation)
            busy = false
            if let code {
                onCode(code)
                return
            }
        }

        // Printed digits under the bars. The chip bag's first digit sits on the green,
        // so the bar detector misses frames that the numbers still explain.
        guard !textBusy, now - lastText > 0.9 else { return }
        textBusy = true
        lastText = now
        guard let upright = FoodPhotoLocalAnalysis.copyUpright(buffer, orientation: orientation) else {
            textBusy = false
            return
        }
        textQueue.async { [weak self] in
            let code = FoodPhotoLocalAnalysis.readPrintedBarcode(in: upright)
            self?.queue.async {
                if let code {
                    self?.onCode(code)
                }
                self?.textBusy = false
            }
        }
    }

    /// `videoRotationAngle` is how far the buffer is already rotated. 0 means sensor landscape.
    private static func orientation(for videoRotationAngle: CGFloat) -> CGImagePropertyOrientation {
        switch videoRotationAngle {
        case 90: return .up
        case 180: return .down
        case 270: return .left
        default: return .right
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool = false
    var onFocus: ((CGPoint) -> Void)?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.mirrored = mirrored
        view.onFocus = onFocus
        view.startObserving()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.mirrored = mirrored
        uiView.onFocus = onFocus
        uiView.updateConnection()
    }

    final class PreviewView: UIView {
        var mirrored = false
        var onFocus: ((CGPoint) -> Void)?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        func startObserving() {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            addGestureRecognizer(tap)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(updateConnection),
                name: .AVCaptureSessionDidStartRunning,
                object: previewLayer.session
            )
        }

        @objc private func handleTap(_ tap: UITapGestureRecognizer) {
            let point = tap.location(in: self)
            onFocus?(previewLayer.captureDevicePointConverted(fromLayerPoint: point))
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateConnection()
        }

        @objc func updateConnection() {
            guard let connection = previewLayer.connection else { return }
            let angle: CGFloat = 90
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        }

        func devicePoint(from viewPoint: CGPoint) -> CGPoint {
            previewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

struct ScanCameraOverlay: View {
    let style: ScanReticleStyle
    var isLocked: Bool = false
    var status: String
    var subtitle: String

    var body: some View {
        GeometryReader { geo in
            let cutout = cutoutRect(in: geo.size)

            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(isLocked ? 0.72 : 0.58))
                    .mask {
                        cutoutMask(in: geo.size, cutout: cutout)
                            .fill(style: FillStyle(eoFill: true))
                    }
                    .allowsHitTesting(false)

                if style != .barcode {
                    ruleOfThirds(in: cutout)
                        .opacity(0.22)
                }

                ScanCornerBrackets(cornerLength: style == .barcode ? 26 : 32)
                    .stroke(
                        AngularGradient(
                            colors: isLocked
                                ? [BrandTheme.teal, BrandTheme.neonBlue, BrandTheme.teal]
                                : [BrandTheme.magenta, BrandTheme.teal, BrandTheme.neonBlue, BrandTheme.magenta],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: cutout.width, height: cutout.height)
                    .position(x: cutout.midX, y: cutout.midY)
                    .shadow(color: (isLocked ? BrandTheme.teal : BrandTheme.magenta).opacity(0.7), radius: isLocked ? 14 : 8)
                    .scaleEffect(isLocked ? 1.015 : 1)
                    .animation(.easeInOut(duration: 0.22), value: isLocked)

                ScanLaserLine(isLocked: isLocked)
                    .frame(width: cutout.width - 10, height: cutout.height - 10)
                    .position(x: cutout.midX, y: cutout.midY)
                    .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius - 4, style: .continuous))

                PulsingBarcodeBars(isLocked: isLocked)
                    .frame(width: min(cutout.width - 36, 220))
                    .position(x: cutout.midX, y: cutout.maxY - 22)

                VStack(spacing: 6) {
                    Text(status)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .tracking(3.2)
                        .foregroundStyle(isLocked ? BrandTheme.teal : Color.white.opacity(0.95))
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .position(x: cutout.midX, y: cutout.minY - 36)
            }
        }
        .allowsHitTesting(false)
    }

    private func cutoutRect(in size: CGSize) -> CGRect {
        let topReserve: CGFloat = 108
        let bottomReserve: CGFloat = style == .barcode ? 168 : 196
        let available = CGRect(
            x: 0,
            y: topReserve,
            width: size.width,
            height: max(size.height - topReserve - bottomReserve, 120)
        )

        let width: CGFloat
        let height: CGFloat
        switch style {
        case .meal:
            width = available.width * 0.84
            height = min(width * 1.12, available.height * 0.94)
        case .barcode:
            width = available.width * 0.88
            height = min(138, available.height * 0.42)
        case .portrait:
            width = available.width * 0.72
            height = min(width * 1.32, available.height * 0.96)
        }

        return CGRect(
            x: available.midX - width / 2,
            y: available.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func cutoutMask(in size: CGSize, cutout: CGRect) -> Path {
        var path = Path(CGRect(origin: .zero, size: size))
        path.addRoundedRect(
            in: cutout,
            cornerSize: CGSize(width: style.cornerRadius, height: style.cornerRadius),
            style: .continuous
        )
        return path
    }

    private func ruleOfThirds(in cutout: CGRect) -> some View {
        Path { path in
            for i in 1...2 {
                let x = cutout.minX + cutout.width * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: cutout.minY + 10))
                path.addLine(to: CGPoint(x: x, y: cutout.maxY - 10))
                let y = cutout.minY + cutout.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: cutout.minX + 10, y: y))
                path.addLine(to: CGPoint(x: cutout.maxX - 10, y: y))
            }
        }
        .stroke(Color.white.opacity(0.45), lineWidth: 0.6)
    }
}

struct ScanCornerBrackets: Shape {
    var cornerLength: CGFloat = 32

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let l = min(cornerLength, min(rect.width, rect.height) / 2.6)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return path
    }
}

struct ScanLaserLine: View {
    var isLocked: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 45, paused: false)) { timeline in
            let period = isLocked ? 0.55 : 1.65
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let y = t < 0.5 ? t * 2 : (1 - (t - 0.5) * 2)

            GeometryReader { geo in
                ZStack {
                    LinearGradient(
                        colors: [
                            BrandTheme.teal.opacity(0),
                            BrandTheme.teal.opacity(0.35),
                            BrandTheme.magenta.opacity(0.55),
                            BrandTheme.teal.opacity(0.35),
                            BrandTheme.teal.opacity(0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 42)
                    .blur(radius: 8)
                    .offset(y: (y - 0.5) * geo.size.height)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [BrandTheme.teal, Color.white, BrandTheme.magenta],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 2.4)
                        .shadow(color: BrandTheme.teal.opacity(0.95), radius: 8)
                        .shadow(color: BrandTheme.magenta.opacity(0.7), radius: 10)
                        .offset(y: (y - 0.5) * geo.size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .opacity(isLocked ? 1 : 0.92)
    }
}

struct PulsingBarcodeBars: View {
    var isLocked: Bool
    private let pattern: [CGFloat] = [
        1, 0.45, 1, 1, 0.4, 0.85, 0.4, 1, 0.5, 1,
        0.4, 0.9, 1, 0.45, 1, 0.4, 0.8, 1, 0.5, 1,
        0.4, 1, 0.85, 0.45, 1, 0.5, 1, 0.4, 0.9, 1,
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.2) {
                ForEach(pattern.indices, id: \.self) { index in
                    let width = pattern[index] > 0.7 ? 2.4 : 1.3
                    let phase = t * (isLocked ? 8 : 4.2) + Double(index) * 0.38
                    let pulse = 0.55 + 0.45 * sin(phase)

                    Capsule()
                        .fill(isLocked ? BrandTheme.teal : Color.white.opacity(0.55 + 0.4 * pulse))
                        .frame(width: width, height: 7 + CGFloat(pulse) * (isLocked ? 11 : 8))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct CameraGlassButton: View {
    let systemName: String
    var filled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                }
                .overlay {
                    if filled {
                        Circle().fill(BrandTheme.teal.opacity(0.35))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

struct CameraUnavailableState: View {
    let title: String
    let message: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            HomeDarkBackground()
            VStack(spacing: 18) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(BrandTheme.teal)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BrandTheme.homePrimaryText)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Button("Close", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .tint(BrandTheme.magenta)
            }
        }
    }
}

struct CameraPermissionState: View {
    let onClose: () -> Void

    var body: some View {
        CameraUnavailableState(
            title: "Camera access needed",
            message: "Turn on Camera in Settings to scan meals and barcodes.",
            onClose: onClose
        )
        .overlay(alignment: .bottom) {
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.bordered)
            .tint(BrandTheme.teal)
            .padding(.bottom, 40)
        }
    }
}
