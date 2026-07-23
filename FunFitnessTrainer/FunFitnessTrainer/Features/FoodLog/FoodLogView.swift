import SwiftUI
import SwiftData
import PhotosUI

struct FoodLogView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showCamera = false
    @State private var showBarcodeScanner = false
    @State private var showManual = false
    @State private var pendingBarcode = ""
    @State private var showBarcodeConfirm = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var showConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.brandAccent)
                Text("Snap your food")
                    .font(.title2.bold())
                Text("For packaged food, scan the barcode for exact nutrition. Photos use AI and should always be confirmed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if !RuntimeEnvironment.isCameraAvailable {
                    Text("No camera on this device — choose a photo from your library or log manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !appState.canScanFood {
                    Text("Free scans used today (\(AppConfig.freeScansPerDay)/day). Go Pro or log manually.")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Scans today: \(appState.scansToday)/\(appState.isPro ? "∞" : "\(AppConfig.freeScansPerDay)")")
                        .font(.caption)
                }

                if RuntimeEnvironment.isCameraAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Open camera", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandAccent)
                    .disabled(!appState.canScanFood)
                }

                Button {
                    if RuntimeEnvironment.isCameraAvailable {
                        showBarcodeScanner = true
                    } else {
                        pendingBarcode = ""
                        showBarcodeConfirm = true
                    }
                } label: {
                    Label("Scan barcode", systemImage: "barcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.brandAccent)

                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Label(
                        RuntimeEnvironment.isCameraAvailable ? "Choose from library" : "Pick a food photo",
                        systemImage: "photo.on.rectangle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .modifier(FoodLogPhotoPickerStyle(isPrimary: !RuntimeEnvironment.isCameraAvailable))
                .disabled(!appState.canScanFood)

                Button("Log manually") { showManual = true }
                    .font(.subheadline)
            }
            .padding()
            .navigationTitle("Log food")
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                if pendingImage != nil {
                    showConfirm = true
                }
            }) {
                CameraCaptureView { image in
                    pendingImage = image
                }
            }
            .fullScreenCover(isPresented: $showBarcodeScanner, onDismiss: {
                if !pendingBarcode.isEmpty {
                    showBarcodeConfirm = true
                }
            }) {
                BarcodeScannerView { code in
                    pendingBarcode = code
                }
            }
            .onChange(of: pickedItem) { _, item in
                Task {
                    guard item != nil else { return }
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            pendingImage = image
                            pickedItem = nil
                            showConfirm = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showConfirm) {
                if let img = pendingImage {
                    MealConfirmView(image: img) {
                        pendingImage = nil
                        appState.recordScan()
                    }
                }
            }
            .sheet(isPresented: $showBarcodeConfirm) {
                BarcodeMealConfirmView(barcode: pendingBarcode) {
                    pendingBarcode = ""
                }
            }
            .sheet(isPresented: $showManual) {
                ManualMealEntryView()
            }
        }
    }
}

private struct FoodLogPhotoPickerStyle: ViewModifier {
    let isPrimary: Bool

    func body(content: Content) -> some View {
        if isPrimary {
            content.buttonStyle(.borderedProminent).tint(Color.brandAccent)
        } else {
            content.buttonStyle(.bordered).tint(Color.brandAccent)
        }
    }
}
