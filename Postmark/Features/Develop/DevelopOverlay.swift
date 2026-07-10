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

    private let duration: TimeInterval = 1.5

    var body: some View {
        let vf = capture.viewfinderRect

        ZStack {
            PaperBackdrop()

            TimelineView(.animation(paused: dissolveDone)) { timeline in
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
        .onAppear {
            start = Date()
            model.haptics.grains(duration: duration * 0.85)
        }
        .task {
            let result = await VisionService.analyze(
                capture.cropImage,
                fallbackCutout: capture.fallbackCutout,
                fallbackLabel: capture.fallbackLabel
            )
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
        model.developFinished(pending)
    }
}
