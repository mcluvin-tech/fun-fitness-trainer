import SwiftUI
import SwiftData
import PhotosUI

struct FoodLogView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showCamera = false
    @State private var showBarcodeScanner = false
    @State private var showManual = false
    @State private var pendingBarcode = ""
    @State private var pendingBarcodeScan: PendingBarcodeScan?
    @State private var pickedItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var showConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                HomeDarkBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 64))
                            .foregroundStyle(BrandTheme.magenta)
                        Text("Snap your food")
                            .font(.title2.bold())
                            .foregroundStyle(BrandTheme.homePrimaryText)
                        Text("For packaged food, photograph the barcode or nutrition label — macros are read on-device when possible. Plate photos use AI and should be confirmed.")
                            .font(.caption)
                            .foregroundStyle(BrandTheme.homeSecondaryText)
                            .multilineTextAlignment(.center)

                        if !RuntimeEnvironment.isCameraAvailable {
                            Text("No camera on this device — choose a photo from your library or log manually.")
                                .font(.caption)
                                .foregroundStyle(BrandTheme.homeSecondaryText)
                                .multilineTextAlignment(.center)
                        }

                        if !appState.canScanFood {
                            Text("Free scans used today (\(AppConfig.freeScansPerDay)/day). Go Pro or log manually.")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                        } else {
                            Text(appState.scanAllowanceLabel)
                                .font(.caption)
                                .foregroundStyle(BrandTheme.homeSecondaryText)
                        }

                        if RuntimeEnvironment.isCameraAvailable {
                            Button {
                                showCamera = true
                            } label: {
                                Label("Open camera", systemImage: "camera.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(BrandTheme.magenta)
                            .disabled(!appState.canScanFood)
                        }

                        Button {
                            if RuntimeEnvironment.isCameraAvailable {
                                showBarcodeScanner = true
                            } else {
                                pendingBarcodeScan = PendingBarcodeScan()
                            }
                        } label: {
                            Label("Scan barcode", systemImage: "barcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(BrandTheme.teal)

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
                            .foregroundStyle(BrandTheme.homeSecondaryText)
                    }
                    .padding()
                }
            }
            .preferredColorScheme(.dark)
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 88)
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                if !pendingBarcode.isEmpty {
                    pendingBarcodeScan = PendingBarcodeScan(pendingBarcode)
                    pendingBarcode = ""
                } else if pendingImage != nil {
                    showConfirm = true
                }
            }) {
                CameraCaptureView(
                    onBarcode: { pendingBarcode = $0 }
                ) { image in
                    pendingImage = image
                }
            }
            .fullScreenCover(isPresented: $showBarcodeScanner, onDismiss: {
                if !pendingBarcode.isEmpty {
                    pendingBarcodeScan = PendingBarcodeScan(pendingBarcode)
                    pendingBarcode = ""
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
            .sheet(item: $pendingBarcodeScan) { scan in
                BarcodeMealConfirmView(barcode: scan.code) {
                    pendingBarcodeScan = nil
                    appState.recordScan()
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
