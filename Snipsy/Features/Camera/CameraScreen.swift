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
    /// Shutter-tap punch: the mount dips under the die. Only the down-stroke
    /// belongs to this screen — `DevelopOverlay` springs the frozen frame
    /// back out of it.
    @State private var capturePunch = false

    // MARK: Frame geometry
    //
    // The viewfinder is a physical object now — a slide mount you look
    // through — rather than a full-bleed crop. Both numbers below are
    // measured off `viewfinder_frame`, so nothing here is eyeballed: change
    // the art and re-measure, don't nudge these by hand.

    /// The mount's own proportions (1024 × 1536 as cut).
    private static let frameAspect: CGFloat = 1536.0 / 1024.0

    /// The moulded opening, as fractions of the art. Measured, not eyeballed:
    /// the punch runs x 132…891, y 225…1261 of 1024 × 1536.
    private static let openingInFrame = CGRect(x: 0.1289, y: 0.1465,
                                               width: 0.7422, height: 0.6751)

    /// What actually gets cut, 4:5, width-matched and centred in the opening.
    ///
    /// The opening is 0.733 wide — taller than 4:5 — but the crop stays 4:5
    /// because that is the stamp's picture window (`StampView`: 0.85W ×
    /// 1.0625W). Matching it is what makes the handoff pixel-continuous.
    /// Derived rather than written down, so re-measuring the opening can
    /// never leave the two out of step.
    private static var apertureInFrame: CGRect {
        let h = openingInFrame.width * 1.25 / frameAspect
        return CGRect(x: openingInFrame.minX, y: openingInFrame.midY - h / 2,
                      width: openingInFrame.width, height: h)
    }

    /// The mount on screen — inset from the edges, so the live feed reads as
    /// the world you're holding it up against.
    static func frameRect(in size: CGSize) -> CGRect {
        let w = min(size.width * 0.86, 430)
        let h = w * frameAspect
        return CGRect(x: (size.width - w) / 2,
                      y: size.height * 0.44 - h / 2,
                      width: w, height: h)
    }

    /// The glass you look through: the whole moulded opening. The live feed
    /// fills it edge to edge, so the mount reads as a clean window instead of
    /// a lens with dimmed bands top and bottom.
    static func windowRect(in size: CGSize) -> CGRect {
        rect(openingInFrame, in: size)
    }

    /// The stamp-to-be: 4:5, centred in the window. Shared by the capture
    /// path and the reveal handoff — single source of truth for what is kept.
    /// Slightly shorter than `windowRect`, so the top and bottom slivers of
    /// the live feed are preview only.
    static func viewfinderRect(in size: CGSize) -> CGRect {
        rect(apertureInFrame, in: size)
    }

    // MARK: Punch

    /// How far the mount dips under the die.
    static let punchScale: CGFloat = 0.94

    /// The press pivots on the opening's centre — expressed in the mount
    /// art's OWN bounds, because the mount is the only thing that moves.
    /// The aperture closes symmetrically on a picture that stays put.
    static let punchAnchor = UnitPoint(x: openingInFrame.midX,
                                       y: openingInFrame.midY)

    /// Drive a mount's press-then-lift: down under the die, spring back
    /// past rest.
    ///
    /// Deliberately quick. Both paths hold a curtain for ~0.2s before
    /// handing over to a develop that draws the mount at rest, so a press
    /// still travelling at the swap would ghost against its own still copy
    /// through the crossfade. The whole motion lands inside that beat.
    @MainActor
    static func firePunch(_ pressed: Binding<Bool>) {
        withAnimation(.spring(response: 0.15, dampingFraction: 0.9)) {
            pressed.wrappedValue = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.10))
            withAnimation(.spring(response: 0.20, dampingFraction: 0.68)) {
                pressed.wrappedValue = false
            }
        }
    }

    private static func rect(_ r: CGRect, in size: CGSize) -> CGRect {
        let f = frameRect(in: size)
        return CGRect(x: f.minX + r.minX * f.width,
                      y: f.minY + r.minY * f.height,
                      width: r.width * f.width,
                      height: r.height * f.height)
    }

    var body: some View {
        let frame = Self.frameRect(in: screenSize)
        let window = Self.windowRect(in: screenSize)

        ZStack {
            // Without permission there is no feed to frame, so the stamp
            // cut-out and its surrounding dim would just be masking a
            // permission screen into a stamp silhouette. Show that screen
            // whole instead.
            if isLive {
                feed

                // Darken the world the mount isn't framing, so the eye goes
                // to the window. The mount's own body does the occluding
                // inside its bounds. Cut to the full opening, not the 4:5
                // crop — punching the crop left the opening's top and bottom
                // slivers dimmed, which read as a vignette on the glass.
                HoleDim(hole: window, corner: window.width * 0.026)
                    .fill(Color.black.opacity(0.38), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                // The mount is the only thing that punches. The feed, the
                // dim and the chrome all hold still, so the tap reads as the
                // frame pressing DOWN onto the picture — its aperture
                // closing over a subject that never moves. Scaling anything
                // wider than the art (the feed, or the whole screen) turned
                // the press into the app flinching.
                Image("viewfinder_frame")
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .scaleEffect(capturePunch ? Self.punchScale : 1,
                                 anchor: Self.punchAnchor)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)
            } else {
                permissionGate
            }

            chrome()

            if let p = focusPoint, isLive {
                FocusIndicator()
                    .position(p)
                    .id("\(p.x)-\(p.y)")
            }
        }
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
    private func chrome() -> some View {
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
                Self.firePunch($capturePunch)
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
