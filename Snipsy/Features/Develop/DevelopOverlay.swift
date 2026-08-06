import SwiftUI

/// The signature moment. The frozen frame sits pixel-perfect over the live
/// preview; everything outside the stamp plate disintegrates into drifting
/// grains, revealing the paper world beneath. Vision runs concurrently so the
/// reveal is usually instant when the last grain dies.
///
/// What the dust leaves is a stamp, not a photo: the kept region is the
/// perforated silhouette, and the wave carves its teeth as the front crosses
/// them. Nothing downstream has to turn a rectangle into an artifact later,
/// so there is no beat where the user is looking at a bare 4:5 crop.
struct DevelopOverlay: View {
    let capture: Capture
    let model: AppModel
    let screenSize: CGSize

    @State private var start: Date? = nil
    @State private var dissolveDone = false
    @State private var analysis: VisionService.Analysis? = nil
    @State private var advanced = false
    /// Cancels the parent's transient ±4 pt proposal overshoot at capture
    /// time (children land 4 pt high without it). Measured live; converges
    /// to the true drift and commits behind the blackout.
    @State private var drift: CGFloat = 0

    private let duration: TimeInterval = 0.72

    var body: some View {
        let vf = capture.viewfinderRect
        // The plate the reveal is about to draw, in the frozen frame's own
        // coordinates. Shared derivation, so the silhouette the grains cut
        // and the one the stamp wears are the same rect to the pixel.
        let plate = StampView.plateRect(inscribedIn: vf)

        ZStack {
            GeometryReader { g in
                let minY = g.frame(in: .global).minY
                Color.clear
                    .onAppear { if abs(minY) > 0.5 { drift -= minY } }
                    .onChange(of: minY) { _, new in
                        if abs(new) > 0.5 { drift -= new }
                    }
            }

            PaperBackdrop()

            TimelineView(.animation(paused: start == nil || dissolveDone)) { timeline in
                let elapsed = start.map { timeline.date.timeIntervalSince($0) } ?? 0
                let raw = min(1.0, max(0.0, elapsed / duration))
                // LINEAR on purpose: the dust front must cross the screen at
                // constant speed and EXIT the right edge — an ease-out tail
                // decelerates it to a crawl short of the edge, which reads
                // as the sweep stalling. Grains stagger their own deaths.
                let progress = raw

                // The camera's last frame, rebuilt whole — feed, dim and
                // moulding — so the phase swap has nothing to fade. The
                // dissolve then takes the mount apart along with the world
                // it was framing: the object in your hands crumbles and
                // leaves the stamp. Composited INTO the effect's layer, so
                // one wave eats all three.
                let mount = CameraScreen.frameRect(in: screenSize)
                let window = CameraScreen.windowRect(in: screenSize)

                ZStack {
                    Image(uiImage: capture.screenImage)
                        .resizable()
                        .frame(width: screenSize.width, height: screenSize.height)

                    HoleDim(hole: window, corner: window.width * 0.026)
                        .fill(Color.black.opacity(0.38), style: FillStyle(eoFill: true))

                    Image("viewfinder_frame")
                        .resizable()
                        .frame(width: mount.width, height: mount.height)
                        .position(x: mount.midX, y: mount.midY)
                }
                .frame(width: screenSize.width, height: screenSize.height)
                .allowsHitTesting(false)
                .layerEffect(
                    ShaderLibrary.grainDissolveRect(
                        .float2(screenSize.width, screenSize.height),
                        .float4(plate.minX, plate.minY,
                                plate.width, plate.height),
                        .float(PerforatedRect.defaultHoleRadiusFraction),
                        .float(PerforatedRect.defaultSpacingFactor),
                        .float(progress),
                        .float(4.5)
                    ),
                    // Width bound: symmetric breeze (≤48) + the sweep
                    // gust (≤54) + a cell.
                    maxSampleOffset: CGSize(width: 116, height: 210)
                )
                .onChange(of: raw >= 1) { _, done in
                    if done {
                        dissolveDone = true
                        tryAdvance()
                    }
                }
            }

            // If Vision is still thinking after the dust settles.
            if dissolveDone && analysis == nil {
                Text("Lifting your subject…")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .position(x: screenSize.width / 2, y: vf.maxY + 44)
                    .transition(.opacity)
            }
        }
        // Pin to the window size like CameraScreen does, and cancel the
        // measured drift so every layer lands exactly on the window — the
        // develop → reveal handoff must be pixel-continuous.
        .offset(y: drift)
        .frame(width: screenSize.width, height: screenSize.height)
        .onAppear {
            Task { @MainActor in
                // Let the frozen frame's first commit land behind the
                // blackout, then lift the curtain and start the wave — the
                // dissolve clock must never race an expensive first frame.
                await afterNextCommit()
                model.blackout = false
                try? await Task.sleep(for: .seconds(0.06))
                start = Date()
                model.haptics.grains(duration: duration * 0.85)
            }
        }
        .task {
            // AppModel started the analysis right after the bake — behind
            // the shutter beat — so by now it usually only needs awaiting.
            var result: VisionService.Analysis
            if let early = model.pendingAnalysis {
                result = await early.value
                model.pendingAnalysis = nil
            } else {
                result = await VisionService.analyze(capture.cropImage)
            }
            // Decode the reveal's textures now, while the grains are still
            // falling — its first frame must not stall on bitmap decode.
            result = await Task.detached(priority: .userInitiated) { [result] in
                var r = result
                r.cutout = r.cutout.map { $0.preparingForDisplay() ?? $0 }
                r.sticker = r.sticker.map { $0.preparingForDisplay() ?? $0 }
                return r
            }.value
            analysis = result
            tryAdvance()
        }
    }

    private func tryAdvance() {
        guard !advanced, dissolveDone, let analysis else { return }
        advanced = true

        let hasSubject = analysis.cutout != nil && analysis.sticker != nil
        let pending = PendingStamp(
            capture: capture,
            style: hasSubject ? .cutout : .classic,
            cutout: analysis.cutout,
            sticker: analysis.sticker,
            stickerBox: analysis.stickerBox,
            stickerLabelAnchor: analysis.labelAnchor,
            suggestedTitle: analysis.label,
            tint: analysis.tint
        )
        model.developFinished(pending)
    }
}
