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
    /// A picked photo waiting to be framed against the aperture.
    @State private var framingImage: PickedPhoto? = nil
    /// Shutter-tap punch: a quick press-down-and-spring-back on the whole
    /// viewfinder, so the tap itself reads as stamping down onto paper.
    @State private var capturePunch = false

    // MARK: Frame geometry
    //
    // The viewfinder is a physical object now — a slide mount you look
    // through — rather than a full-bleed crop. Both numbers below are
    // measured off `viewfinder_frame`, so nothing here is eyeballed: change
    // the art and re-measure, don't nudge these by hand.

    /// The mount's own proportions (639 × 953 as cut).
    private static let frameAspect: CGFloat = 953.0 / 639.0

    /// Where the punched window sits inside it, as fractions of the art.
    /// This is what makes the aperture and the capture crop agree.
    ///
    /// The moulded opening is taller than 4:5, so the hole is cut
    /// width-matched and centred inside it; the bands left above and below
    /// keep the recess gradient and read as part of the moulding.
    private static let apertureInFrame = CGRect(x: 0.1549, y: 0.2046,
                                                width: 0.6635, height: 0.5561)

    /// The mount on screen — inset from the edges, so the live feed reads as
    /// the world you're holding it up against.
    static func frameRect(in size: CGSize) -> CGRect {
        let w = min(size.width * 0.86, 430)
        let h = w * frameAspect
        return CGRect(x: (size.width - w) / 2,
                      y: size.height * 0.44 - h / 2,
                      width: w, height: h)
    }

    /// The stamp-to-be: the frame's window, 4:5. Shared by the capture path
    /// and the reveal handoff — single source of truth, so what you see
    /// through the mount is exactly what gets cut.
    static func viewfinderRect(in size: CGSize) -> CGRect {
        let f = frameRect(in: size)
        return CGRect(x: f.minX + apertureInFrame.minX * f.width,
                      y: f.minY + apertureInFrame.minY * f.height,
                      width: apertureInFrame.width * f.width,
                      height: apertureInFrame.height * f.height)
    }

    var body: some View {
        let frame = Self.frameRect(in: screenSize)
        let vf = Self.viewfinderRect(in: screenSize)

        ZStack {
            // Without permission there is no feed to frame, so the stamp
            // cut-out and its surrounding dim would just be masking a
            // permission screen into a stamp silhouette. Show that screen
            // whole instead.
            if isLive {
                feed

                // Darken the world the mount isn't framing, so the eye goes
                // to the window. The mount's own body does the occluding
                // inside its bounds.
                HoleDim(hole: vf, corner: vf.width * 0.026)
                    .fill(Color.black.opacity(0.38), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                Image("viewfinder_frame")
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)
            } else {
                permissionGate
            }

            chrome(viewfinder: vf)

            if let p = focusPoint, isLive {
                FocusIndicator()
                    .position(p)
                    .id("\(p.x)-\(p.y)")
            }
        }
        .scaleEffect(capturePunch ? 0.97 : 1)
        .frame(width: screenSize.width, height: screenSize.height)
        .background(Color.black)
        .fullScreenCover(item: $framingImage) { picked in
            PhotoFramingScreen(
                image: picked.image,
                screenSize: screenSize,
                safeArea: safeArea,
                onCancel: { framingImage = nil },
                onUse: { crop, screen in
                    framingImage = nil
                    Task {
                        await model.importFramed(
                            crop, screen: screen,
                            aperture: Self.viewfinderRect(in: screenSize))
                    }
                }
            )
        }
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

    /// A real feed to frame — everything camera-shaped hangs off this.
    private var isLive: Bool { model.camera.authorization == .authorized }

    @ViewBuilder
    private var permissionGate: some View {
        if model.camera.authorization == .denied {
            // Hard denial: the system prompt is spent, so Settings is the
            // only way back.
            PermissionDeniedView()
        } else {
            // Never asked, or deferred during onboarding — the prompt is
            // still unspent, so it's worth offering again.
            CameraPermissionPrimerView(model: model)
        }
    }

    private var feed: some View {
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
                      let raw = ImageOptimizer.downsampled(data: data, maxPixel: 3072)
                else { return }
                // Frame it first. The old path cropped on the spot using the
                // live viewfinder rect, which had nothing to do with where
                // the subject actually was.
                framingImage = PickedPhoto(image: ImageOptimizer.normalizedOrientation(raw))
            }
        }

        // Wordmark — white-on-feed, so it only belongs over a live feed.
        // The permission screens carry their own headline.
        if isLive {
            Text("SNIPSY")
                .font(Theme.display(15))
                .tracking(2)
                .rotationEffect(.degrees(-2))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.45), radius: 7, y: 1)
                .position(x: screenSize.width / 2, y: safeArea.top + 24)
        }

        // Flash (back camera only)
        if isLive && !model.camera.frontCamera {
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

        // Shutter and flip need a feed to act on. The library button above
        // stays put in every state — importing an old photo is a complete
        // path through the app that never needs the camera at all.
        if isLive {
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
}

/// Full-screen dim with a rectangular hole (even-odd fill).
///
/// The hole used to be a `PerforatedRect`, back when the dim itself drew the
/// stamp silhouette. The mount art now owns that job — its window is a plain
/// rounded opening — so a perforated hole would show notches that don't line
/// up with the object sitting on top of it.
struct HoleDim: Shape {
    let hole: CGRect
    var corner: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        p.addRoundedRect(in: hole,
                         cornerSize: CGSize(width: corner, height: corner))
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

/// A picked library photo on its way to the framing step. `UIImage` is not
/// `Identifiable`, and identity here is per-pick, not per-pixel.
struct PickedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}
