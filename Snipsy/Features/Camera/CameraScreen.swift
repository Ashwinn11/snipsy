import SwiftUI
import AVFoundation
import PhotosUI

/// Root camera experience: full-bleed feed, stamp-shaped viewfinder, glass
/// chrome. The camera tab's persistent content — mounted/torn down (and the
/// capture session started/stopped) by tab selection, not a modal.
struct CameraScreen: View {
    let model: AppModel
    let screenSize: CGSize
    let safeArea: EdgeInsets

    @State private var focusPoint: CGPoint? = nil
    @State private var focusPulse = false
    @State private var pickedItem: PhotosPickerItem? = nil
    /// Shutter-tap punch: a quick press-down-and-spring-back on the whole
    /// viewfinder, so the tap itself reads as stamping down onto paper.
    @State private var capturePunch = false

    /// The stamp-to-be. 4:5, full-bleed width, slightly above middle —
    /// the frame is the whole stage, not a window. Shared by the capture
    /// path and the reveal handoff — single source of truth.
    static func viewfinderRect(in size: CGSize) -> CGRect {
        let w = size.width
        let h = w * 1.25
        return CGRect(x: 0, y: size.height * 0.44 - h / 2,
                      width: w, height: h)
    }

    var body: some View {
        let vf = Self.viewfinderRect(in: screenSize)

        ZStack {
            feed

            HoleDim(hole: vf)
                .fill(Color.black.opacity(0.32), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

            ViewfinderOverlay(rect: vf)

            chrome(viewfinder: vf)

            if let p = focusPoint {
                FocusIndicator()
                    .position(p)
                    .id("\(p.x)-\(p.y)")
            }
        }
        .scaleEffect(capturePunch ? 0.97 : 1)
        .frame(width: screenSize.width, height: screenSize.height)
        .background(Color.black)
    }

    /// The shutter tap's press-then-lift: down quickly, spring back past
    /// rest, settle — timed inside the pre-blackout beat so it reads as one
    /// continuous stamp-and-flash with the existing shutter haptic.
    private func firePunch() {
        withAnimation(Theme.springTight) { capturePunch = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.12))
            withAnimation(Theme.springBouncy) { capturePunch = false }
        }
    }

    // MARK: Feed

    @ViewBuilder
    private var feed: some View {
        if model.camera.authorization == .denied {
            PermissionDeniedView()
        } else {
            CameraPreviewView(session: model.camera.session) { viewPoint, devicePoint in
                model.camera.focus(atDevicePoint: devicePoint)
                model.haptics.tick()
                focusPoint = viewPoint
                Task {
                    try? await Task.sleep(for: .seconds(0.9))
                    if focusPoint == viewPoint { focusPoint = nil }
                }
            }
            .frame(width: screenSize.width, height: screenSize.height)
        }
    }

    // MARK: Chrome

    @ViewBuilder
    private func chrome(viewfinder vf: CGRect) -> some View {
        let topLeftY = safeArea.top + 24
        let barY = screenSize.height - max(safeArea.bottom, 16) - 54

        // Library import — an old photo takes the same ride as a live shot.
        PhotosPicker(selection: $pickedItem, matching: .images) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                .frame(width: 44, height: 44)
        }
        // Fixed scrim, not glass: liquid glass refracts the live feed, so
        // the chrome would flicker with every exposure change.
        .background(.black.opacity(0.32), in: Circle())
        .position(x: 46, y: topLeftY)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                defer { pickedItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                let size = screenSize
                await model.importPhoto(
                    image,
                    viewfinderRect: Self.viewfinderRect(in: size),
                    viewSize: size
                )
            }
        }

        // Wordmark
        Text("SNIPSY")
            .font(Theme.display(15))
            .tracking(2)
            .rotationEffect(.degrees(-2))
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.45), radius: 7, y: 1)
            .position(x: screenSize.width / 2, y: safeArea.top + 24)

        // Flash (back camera only)
        if !model.camera.frontCamera {
            Button {
                model.camera.flashOn.toggle()
                model.haptics.tick()
            } label: {
                Image(systemName: model.camera.flashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(model.camera.flashOn ? 1 : 0.85))
                    .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                    .frame(width: 44, height: 44)
            }
            // Fixed scrim, not glass: liquid glass refracts the live feed, so
        // the chrome would flicker with every exposure change.
        .background(.black.opacity(0.32), in: Circle())
            .position(x: screenSize.width - 46, y: safeArea.top + 24)
        }

        // Bottom bar — `barY` is already bound at the top of this function.
        // The collection is its own tab now — nothing redundant sits here.

        ShutterButton {
            firePunch()
            let size = screenSize
            let rect = Self.viewfinderRect(in: size)
            Task { await model.capture(viewfinderRect: rect, viewSize: size) }
        }
        .position(x: screenSize.width / 2, y: barY)

        Button {
            model.camera.flip()
            model.haptics.tick()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                .frame(width: 48, height: 48)
        }
        // Fixed scrim, not glass: liquid glass refracts the live feed, so
        // the chrome would flicker with every exposure change.
        .background(.black.opacity(0.32), in: Circle())
        .position(x: screenSize.width - 66, y: barY)
    }
}

/// Full-screen dim with a perforated stamp-shaped hole (even-odd fill) —
/// the live feed shows through the same silhouette the finished stamp wears.
struct HoleDim: Shape {
    let hole: CGRect

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        p.addPath(PerforatedRect().path(in: hole))
        return p
    }
}

/// Yellow-less, postal-red focus square that pulses once.
struct FocusIndicator: View {
    @State private var appeared = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Theme.postalRed.opacity(0.9), lineWidth: 1.8)
            .frame(width: 74, height: 74)
            .scaleEffect(appeared ? 1 : 1.35)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(Theme.springTight) { appeared = true }
            }
    }
}

/// Friendly camera-permission state on paper — never a dead end.
struct PermissionDeniedView: View {
    var body: some View {
        ZStack {
            PaperBackdrop(showsGrid: true)
            VStack(spacing: 18) {
                PerforatedRect()
                    .stroke(Theme.inkSoft.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.4, dash: [4, 5]))
                    .frame(width: 120, height: 157)
                    .overlay {
                        Image(systemName: "camera")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.inkSoft)
                    }
                Text("Snipsy needs the camera")
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.ink)
                Text("Every stamp starts with a photo.\nAllow camera access in Settings.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 13)
                        .background(Theme.postalRed, in: Capsule())
                }
                .padding(.top, 6)
            }
        }
    }
}
