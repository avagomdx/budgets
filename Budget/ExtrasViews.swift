import SwiftUI
import UIKit
import LocalAuthentication
import PhotosUI

// MARK: - App lock (Face ID / passcode)

enum AppLock {
    static let enabledKey = "appLockEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Asks for Face ID (or Touch ID / the device passcode). Returns true when it succeeded.
    static func authenticate(reason: String = "Unlock Budget") async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

struct LockView: View {
    let onUnlock: () -> Void
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                Text("Budget is locked")
                    .font(.title2.bold())
                Button {
                    unlock()
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
            }
        }
        .onAppear {
            unlock()
        }
    }

    private func unlock() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            if await AppLock.authenticate() {
                onUnlock()
            }
            isAuthenticating = false
        }
    }
}

// MARK: - Receipts

enum ReceiptImage {
    /// Shrinks a photo to at most 1600 px and stores it as JPEG.
    static func compressed(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
}

/// Section for the expense form: add a receipt from the camera or photo library.
struct ReceiptSection: View {
    @Binding var data: Data?

    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingFullScreen = false

    var body: some View {
        Section {
            if let data, let image = UIImage(data: data) {
                HStack(spacing: 12) {
                    Button {
                        showingFullScreen = true
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Text("Tap to view")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove", role: .destructive) {
                        self.data = nil
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                HStack {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera")
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose photo", systemImage: "photo")
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Receipt (optional)")
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: raw) {
                    data = ReceiptImage.compressed(image)
                }
                photoItem = nil
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker(onImage: { image in
                data = ReceiptImage.compressed(image)
            }, onFinish: {
                showingCamera = false
            })
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingFullScreen) {
            ReceiptViewer(data: data)
        }
    }
}

struct ReceiptViewer: View {
    let data: Data?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onFinish: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onFinish: @escaping () -> Void) {
            self.onImage = onImage
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}
