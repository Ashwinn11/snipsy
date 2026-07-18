import SwiftUI

/// Page 2 (new): the canvas pitch. A mini stamp-paper canvas assembles
/// itself live — a couple photo drops in, washi tape sticks across it,
/// die-cut stickers land with bouncy springs, handwritten text floats in
/// last. The whole cycle is ~10 s, looping.
struct OnboardingCanvasPage: View {
    let demo: OnboardingDemo
    let haptics: Haptics
    let isActive: Bool
    let screenSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Independent appear state for each canvas element — springs fire in
    // sequence but each element owns its own animation curve.
    @State private var canvasScale: Double = 0.88
    @State private var canvasOpacity: Double = 0
    @State private var photo1: Double = 0      // couple1 raw tilted photo
    @State private var washi1: Double = 0      // rose washi tape
    @State private var sticker1: Double = 0    // couple2 die-cut
    @State private var scriptText: Double = 0  // "forever & always"
    @State private var sticker2: Double = 0    // puppy die-cut
    @State private var emoji1: Double = 0      // ❤️
    @State private var handText: Double = 0    // "te amo"
    @State private var washi2: Double = 0      // sage washi tape

    @State private var phaseLine = "Drop in a photo…"
    @State private var gen = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Text("BUILD A MEMORY")
                    .font(Theme.display(21))
                    .tracking(1.5)
                    .foregroundStyle(Theme.ink)
                Text("Layer photos, stickers, and text —\nall on one canvas.")
                    .font(.system(size: 14.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            canvasCard
                .scaleEffect(canvasScale)
                .opacity(canvasOpacity)

            Text(phaseLine)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .animation(.easeOut(duration: 0.25), value: phaseLine)
                .padding(.top, 22)

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.top, 30)
        .onAppear { if isActive { startLoop() } }
        .onChange(of: isActive) { _, active in
            if active { startLoop() } else { stopLoop() }
        }
        .onDisappear { stopLoop() }
    }

    // MARK: Sizing

    private var cardWidth: CGFloat { min(screenSize.width * 0.72, 306) }
    private var cardHeight: CGFloat { cardWidth * 1.3125 }

    // MARK: Canvas card

    /// The whole mock: paper stock + perforated border + layered elements.
    private var canvasCard: some View {
        ZStack(alignment: .topLeading) {
            // Paper base
            Color(hex: 0xFBF5E8)
                .overlay {
                    // Subtle dot grid — mirrors the canvas editor
                    Canvas { ctx, size in
                        let step: CGFloat = 20
                        var x = step
                        while x < size.width {
                            var y = step
                            while y < size.height {
                                let dot = Path(ellipseIn: CGRect(x: x - 0.8, y: y - 0.8,
                                                                 width: 1.6, height: 1.6))
                                ctx.fill(dot, with: .color(Theme.inkSoft.opacity(0.12)))
                                y += step
                            }
                            x += step
                        }
                    }
                }

            canvasElements
        }
        .frame(width: cardWidth, height: cardHeight)
        // Clip to the perforated path so elements don't bleed outside teeth.
        .clipShape(PerforatedRect())
        .overlay {
            PerforatedRect()
                .stroke(Theme.inkSoft.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.3, dash: [3.5, 4]))
        }
        .shadow(color: Theme.shadow.opacity(0.28), radius: 20, y: 10)
        .shadow(color: Theme.shadow.opacity(0.10), radius: 4, y: 2)
    }

    // MARK: Canvas elements

    /// All layered content. Each element has its own appear @State;
    /// ZStack alignment is .topLeading so offsets read from the top-left corner.
    @ViewBuilder
    private var canvasElements: some View {
        let w = cardWidth
        let h = cardHeight

        // ── Photo 1: couple1 raw — tilted photo print, top-left ──────────
        if let photo = demo.canvasPhoto {
            rawPhotoCard(photo, width: w * 0.46)
                .rotationEffect(.degrees(-9))
                .scaleEffect(photo1 == 0 ? 0.35 : 1, anchor: .center)
                .opacity(photo1)
                .animation(.spring(response: 0.52, dampingFraction: 0.64), value: photo1)
                .offset(x: w * 0.02, y: h * 0.03)
        }

        // ── Washi 1: rose — mid-left, slanted ────────────────────────────
        DoodleCatalog.view(id: "washi.rose", width: w * 0.52)
            .rotationEffect(.degrees(-4))
            .scaleEffect(x: washi1 == 0 ? 0 : 1, anchor: .leading)
            .opacity(washi1)
            .animation(.spring(response: 0.44, dampingFraction: 0.70), value: washi1)
            .offset(x: w * 0.02, y: h * 0.37)

        // ── Sticker 1: couple2 die-cut — upper-right ─────────────────────
        if let s = demo.subjects.count > 1 ? demo.subjects[1].sticker : nil {
            Image(uiImage: s)
                .resizable()
                .scaledToFit()
                .frame(width: w * 0.40)
                .rotationEffect(.degrees(7))
                .scaleEffect(sticker1 == 0 ? 0.15 : 1, anchor: .center)
                .opacity(sticker1)
                .animation(.spring(response: 0.46, dampingFraction: 0.58), value: sticker1)
                .shadow(color: Theme.shadow.opacity(0.22), radius: 7, y: 4)
                .offset(x: w * 0.55, y: h * 0.06)
        }

        // ── Script text: "forever & always" — center ─────────────────────
        Text("forever & always")
            .font(Theme.script(w * 0.082))
            .foregroundStyle(Color(hex: 0x3B3025))
            .rotationEffect(.degrees(-5))
            .offset(y: scriptText == 0 ? 8 : 0)
            .opacity(scriptText)
            .animation(.easeOut(duration: 0.48), value: scriptText)
            .shadow(color: Theme.shadow.opacity(0.08), radius: 2, y: 1)
            .offset(x: w * 0.16, y: h * 0.54)

        // ── Washi 2: sage — bottom-right, counter-angle ──────────────────
        DoodleCatalog.view(id: "washi.sage", width: w * 0.44)
            .rotationEffect(.degrees(5))
            .scaleEffect(x: washi2 == 0 ? 0 : 1, anchor: .trailing)
            .opacity(washi2)
            .animation(.spring(response: 0.44, dampingFraction: 0.70), value: washi2)
            .offset(x: w * 0.54, y: h * 0.74)

        // ── Sticker 2: puppy die-cut — lower-left ────────────────────────
        if let s = demo.subjects.count > 3 ? demo.subjects[3].sticker : nil {
            Image(uiImage: s)
                .resizable()
                .scaledToFit()
                .frame(width: w * 0.33)
                .rotationEffect(.degrees(-6))
                .scaleEffect(sticker2 == 0 ? 0.15 : 1, anchor: .center)
                .opacity(sticker2)
                .animation(.spring(response: 0.48, dampingFraction: 0.56), value: sticker2)
                .shadow(color: Theme.shadow.opacity(0.20), radius: 6, y: 3)
                .offset(x: w * 0.05, y: h * 0.64)
        }

        // ── Emoji ❤️ — top-right corner accent ───────────────────────────
        Text("❤️")
            .font(.system(size: w * 0.088))
            .scaleEffect(emoji1 == 0 ? 0.05 : 1, anchor: .center)
            .rotationEffect(.degrees(emoji1 == 0 ? -30 : 0))
            .opacity(emoji1)
            .animation(.spring(response: 0.38, dampingFraction: 0.50), value: emoji1)
            .offset(x: w * 0.80, y: h * 0.44)

        // ── Handwritten text: "te amo" — bottom ──────────────────────────
        Text("te amo")
            .font(Theme.handwritten(w * 0.115))
            .foregroundStyle(Theme.stampInk)
            .rotationEffect(.degrees(-7))
            .scaleEffect(handText == 0 ? 0.40 : 1, anchor: .center)
            .opacity(handText)
            .animation(.spring(response: 0.42, dampingFraction: 0.62), value: handText)
            .offset(x: w * 0.30, y: h * 0.82)
    }

    // MARK: Photo card helper

    private func rawPhotoCard(_ image: UIImage, width: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: width * 1.20)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.04))
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.04)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2.5)
            )
            .shadow(color: Theme.shadow.opacity(0.25), radius: 8, y: 4)
    }

    // MARK: Loop

    private func stopLoop() { gen += 1 }

    private func startLoop() {
        gen += 1
        let g = gen
        resetPose()

        if reduceMotion {
            canvasScale = 1; canvasOpacity = 1
            photo1 = 1; washi1 = 1; sticker1 = 1; scriptText = 1
            washi2 = 1; sticker2 = 1; emoji1 = 1; handText = 1
            phaseLine = "Your canvas, your memory."
            return
        }

        Task { @MainActor in
            while gen == g { await runCycle(g) }
        }
    }

    private func resetPose() {
        // Reset element states instantly (canvas is invisible, so no flash).
        canvasScale = 0.88; canvasOpacity = 0
        photo1 = 0; washi1 = 0; sticker1 = 0; scriptText = 0
        washi2 = 0; sticker2 = 0; emoji1 = 0; handText = 0
        phaseLine = "Drop in a photo…"
    }

    /// One full cycle: empty canvas → all elements build up → hold → fade.
    private func runCycle(_ g: Int) async {
        // Canvas entrance
        withAnimation(.spring(response: 0.55, dampingFraction: 0.80)) {
            canvasScale = 1; canvasOpacity = 1
        }
        try? await Task.sleep(for: .seconds(0.65))
        guard gen == g else { return }

        // Photo 1
        haptics.tick()
        withAnimation { photo1 = 1 }
        phaseLine = "Drop in a photo…"
        try? await Task.sleep(for: .seconds(0.70))
        guard gen == g else { return }

        // Washi 1
        haptics.tick()
        withAnimation { washi1 = 1 }
        phaseLine = "…stick some washi tape…"
        try? await Task.sleep(for: .seconds(0.68))
        guard gen == g else { return }

        // Sticker 1 (couple2)
        haptics.thunk()
        withAnimation { sticker1 = 1 }
        phaseLine = "…peel on a sticker…"
        try? await Task.sleep(for: .seconds(0.72))
        guard gen == g else { return }

        // Script text
        haptics.tick()
        withAnimation { scriptText = 1 }
        phaseLine = "…write something real…"
        try? await Task.sleep(for: .seconds(0.70))
        guard gen == g else { return }

        // Washi 2
        haptics.tick()
        withAnimation { washi2 = 1 }
        try? await Task.sleep(for: .seconds(0.60))
        guard gen == g else { return }

        // Sticker 2 (puppy)
        haptics.thunk()
        withAnimation { sticker2 = 1 }
        phaseLine = "…more stickers…"
        try? await Task.sleep(for: .seconds(0.66))
        guard gen == g else { return }

        // Emoji
        haptics.tick()
        withAnimation { emoji1 = 1 }
        try? await Task.sleep(for: .seconds(0.58))
        guard gen == g else { return }

        // Handwritten text
        haptics.thunk()
        withAnimation { handText = 1 }
        phaseLine = "…your canvas, your memory."
        try? await Task.sleep(for: .seconds(2.20))
        guard gen == g else { return }

        // Fade the whole card out (elements invisible under it → safe to reset).
        withAnimation(.easeIn(duration: 0.38)) { canvasOpacity = 0; canvasScale = 0.92 }
        try? await Task.sleep(for: .seconds(0.42))
        guard gen == g else { return }

        resetPose()
        await afterNextCommit()
        guard gen == g else { return }
        try? await Task.sleep(for: .seconds(0.30))
    }
}
