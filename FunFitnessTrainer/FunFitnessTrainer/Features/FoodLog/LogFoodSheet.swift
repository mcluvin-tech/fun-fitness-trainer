import SwiftUI
import PhotosUI

/// Pop-up for choosing how to log a meal (photo, library, or manual).
struct LogFoodSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @Binding var pickedItem: PhotosPickerItem?
    var onCamera: () -> Void
    var onBarcode: () -> Void
    var onManual: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.brandAccent)
                    .padding(.top, 8)

                Text("Log a meal")
                    .font(.title2.bold())

                Text("Snap a photo of food, a barcode, or a nutrition label — or enter details yourself.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if !appState.canScanFood {
                    Text("Free photo scans used today. You can still log manually.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    if RuntimeEnvironment.isCameraAvailable {
                        Button {
                            onCamera()
                            dismiss()
                        } label: {
                            Label("Take a photo", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.brandAccent)
                        .disabled(!appState.canScanFood)
                    }

                    PhotosPicker(selection: $pickedItem, matching: .images) {
                        Label(
                            RuntimeEnvironment.isCameraAvailable ? "Pick from photos" : "Choose from library",
                            systemImage: "photo.on.rectangle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .modifier(PhotoPickerButtonStyle(isPrimary: !RuntimeEnvironment.isCameraAvailable))
                    .disabled(!appState.canScanFood)
                    .onChange(of: pickedItem) { _, item in
                        if item != nil { dismiss() }
                    }

                    Button {
                        onBarcode()
                        dismiss()
                    } label: {
                        Label("Scan barcode", systemImage: "barcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.brandAccent)

                    Button {
                        dismiss()
                        onManual()
                    } label: {
                        Label("Enter manually", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                Text("Estimates only — not medical advice.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)
            }
            .padding(.bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct PhotoPickerButtonStyle: ViewModifier {
    let isPrimary: Bool

    func body(content: Content) -> some View {
        if isPrimary {
            content.buttonStyle(.borderedProminent).tint(Color.brandAccent)
        } else {
            content.buttonStyle(.bordered).tint(Color.brandAccent)
        }
    }
}
