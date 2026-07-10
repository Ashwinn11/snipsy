import SwiftUI

/// The signature moment. The frozen frame sits pixel-perfect over the live
/// preview; everything outside the viewfinder disintegrates into drifting
/// grains, revealing the paper world beneath. Vision runs concurrently so the
/// reveal is usually instant when the last grain dies.
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

    private let duration: TimeInterval = 1.5

    var body: some View {
        let vf = capture.viewfinderRect

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
                // Ease the wave itself; grains add their own stagger.
                let progress = 0.5 - 0.5 * cos(raw * .pi)

                Image(uiImage: capture.screenImage)
                    .resizable()
                    .frame(width: screenSize.width, height: screenSize.height)
                    .layerEffect(
                        ShaderLibrary.grainDissolveRect(
                            .boundingRect,
                            .float4(vf.minX, vf.minY, vf.width, vf.height),
                            .float(12),
                            .float(progress),
                            .float(9)
                        ),
                        maxSampleOffset: CGSize(width: 52, height: 210)
                    )
                    .onChange(of: raw >= 1) { _, done in
                        if done {
                            dissolveDone = true
                            tryAdvance()
                        }
                    }

                // Carry the camera's outside-viewfinder dim into the first
                // dissolve frames so the handoff is seamless, then let the
                // grains take it away.
                HoleDim(hole: vf, corner: 12)
                    .fill(Color.black.opacity(0.32 * (1 - min(1, progress * 2.2))),
                          style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
            }

            // If Vision is still thinking after the dust settles.
            if dissolveDone && analysis == nil {
                Text("Lifting your subject…")
                    .font(.system(size: 15, design: .serif))
                    .italic()
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
            dbgMark("develop.onAppear")
            Task { @MainActor in
                // Let the frozen frame's first commit land behind the
                // blackout, then lift the curtain and start the wave — the
                // dissolve clock must never race an expensive first frame.
                await afterNextCommit()
                dbgMark("develop.committed")
                model.blackout = false
                try? await Task.sleep(for: .seconds(0.06))
                start = Date()
                model.haptics.grains(duration: duration * 0.85)
            }
        }
        .task {
            var result = await VisionService.analyze(
                capture.cropImage,
                fallbackCutout: capture.fallbackCutout,
                fallbackLabel: capture.fallbackLabel
            )
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
            suggestedTitle: analysis.label,
            tint: analysis.tint
        )
        dbgMark("develop.finished")
        model.developFinished(pending)
    }
}
