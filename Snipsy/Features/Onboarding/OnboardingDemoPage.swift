import SwiftUI

/// Page 1: the pitch is a performance. The hero photo is die-cut, the
/// waste shatters, the sticker settles, then the piece dresses itself as a
/// stamp and takes the cancellation mark — the real product animations on bundled
/// assets, looping. A standalone driver mirrors RevealScreen's first-cut
/// and dress choreography without touching AppModel or persistence.
struct OnboardingDemoPage: View {
    let demo: OnboardingDemo
    let haptics: Haptics
    let isActive: Bool
    let screenSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Assembly state — same vocabulary as the reveal.
    @State private var stickerness: Double = 0
    @State private var wasteProgress: Double = 0
    @State private var waveDuration: Double = 1.15
    @State private var waveDriver = DisplayLinkDriver()
    @State private var flight: Double = 0
    @State private var press: Double = 0
    @State private var settle: Double = 0
    @State private var paper: Double = 0.001
    @State private var caption: Double = 0.001
    @State private var holoSweep: Double = -0.4
    @State private var holoStrength: Double = 0
    @State private var stampOpacity: Double = 1
    /// Bumped on every restart/stop; a loop that awakes into a different
    /// generation must exit silently.
    @State private var gen = 0
    @State private var phaseLine = "Your subject is lifted and die-cut…"

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                RansomText(text: "CUT ANYONE OUT", fontSize: 16, ink: Theme.ink)
                Text("Any photo lifts into a die-cut sticker\nfor your next page.")
                    .font(.system(size: 14.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            demoStage
                .frame(height: stampWidth * 1.3125 + 30)

            Text(phaseLine)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .animation(.easeOut(duration: 0.25), value: phaseLine)
                .padding(.top, 26)

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.top, 30)
        .onAppear {
            demo.load()
            if isActive { startLoop() }
        }
        .onChange(of: isActive) { _, active in
            if active { startLoop() } else { stopLoop() }
        }
        .onChange(of: demo.hero == nil) { _, _ in
            if isActive { startLoop() }
        }
        .onDisappear { stopLoop() }
    }

    private var stampWidth: CGFloat { min(screenSize.width * 0.62, 280) }

    @ViewBuilder
    private var demoStage: some View {
        if let assets = demo.hero {
            StampView(
                image: assets.sticker,
                style: .cutout,
                tint: OnboardingDemo.heroTint.color,
                title: demo.hero?.title ?? "",
                number: 1,
                date: .now,
                variant: .tinted,
                stickerBox: assets.box,
                rawCrop: assets.photo,
                maskImage: assets.cutout,
                labelAnchor: assets.labelAnchor,
                assembly: assembly(),
                holoEnabled: true,
                holoStrength: holoStrength,
                holoSweep: holoSweep
            )
            .frame(width: stampWidth)
            .opacity(stampOpacity)
            .shadow(color: Theme.shadow.opacity(0.20), radius: 18, y: 10)
            .onTapGesture { if isActive { startLoop() } }   // instant replay
        } else {
            // Assets missing (should never happen): the old static motif.
            PerforatedRect()
                .stroke(Theme.inkSoft.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.4, dash: [4, 5]))
                .frame(width: 116, height: 152)
                .overlay {
                    Image(systemName: "camera")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.inkSoft.opacity(0.8))
                }
        }
    }

    private func assembly() -> StampView.Assembly {
        var a = StampView.Assembly()
        a.paper = paper
        a.caption = caption
        a.settle = settle
        a.border = stickerness
        a.photoFade = 1 - stickerness
        a.press = press
        a.flight = flight
        a.waste = 1 - wasteProgress
        a.content = .raw
        return a
    }

    // MARK: Wave plumbing (mirrors RevealScreen)

    private func wireWaveDriver() {
        waveDriver.onTick = { dt in
            wasteProgress = min(1, wasteProgress + dt / waveDuration)
            return wasteProgress < 1
        }
    }

    private func driveWave(duration: Double) {
        waveDuration = duration
        waveDriver.start()
    }

    private func waveReached(_ threshold: Double) async {
        let start = Date()
        while wasteProgress < threshold,
              Date().timeIntervalSince(start) < 3 {
            try? await Task.sleep(for: .seconds(0.05))
        }
    }

    // MARK: Loop

    private func stopLoop() {
        gen += 1
        waveDriver.stop()
    }

    private func startLoop() {
        guard demo.hero != nil else { return }
        gen += 1
        let g = gen
        wireWaveDriver()
        resetPose()

        if reduceMotion {
            // No choreography: present the finished stamp.
            stickerness = 0
            paper = 1
            caption = 1
            settle = 1
            phaseLine = "Cut, dressed, and dated — on device."
            return
        }

        Task { @MainActor in
            while gen == g {
                await runCycle(g)
            }
        }
    }

    private func resetPose() {
        stickerness = 0; press = 0; flight = 0; settle = 0
        paper = 0.001; caption = 0.001
        wasteProgress = 0
        holoSweep = -0.4; holoStrength = 0
        stampOpacity = 1
    }

    /// One full cycle: raw photo → punch → shatter → sticker → stamp →
    /// hold → fade out and reset. ~8s.
    private func runCycle(_ g: Int) async {
        phaseLine = "Your subject is lifted and die-cut…"
        await afterNextCommit()
        try? await Task.sleep(for: .seconds(0.8))
        guard gen == g else { return }

        // Punch.
        haptics.tick()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            stickerness = 1
            press = 1
        }
        try? await Task.sleep(for: .seconds(0.45))
        guard gen == g else { return }

        // Shatter.
        haptics.grains(duration: 0.8)
        driveWave(duration: 1.15)
        await waveReached(0.90)
        guard gen == g else { return }

        // Settle as a sticker.
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            settle = 1
            flight = 1
        }
        phaseLine = "A sticker, cut on device…"
        try? await Task.sleep(for: .seconds(1.4))
        guard gen == g else { return }

        // Dress as a stamp.
        if wasteProgress < 1 { driveWave(duration: 0.25) }
        withAnimation(.spring(response: 0.40, dampingFraction: 0.86)) {
            stickerness = 0
            flight = 0
            paper = 1
            settle = 1
        }
        phaseLine = "…or a stamp on the paper you choose."
        try? await Task.sleep(for: .seconds(0.2))
        guard gen == g else { return }
        withAnimation(.linear(duration: 0.5)) { caption = 1 }
        holoStrength = 0.4
        withAnimation(.easeInOut(duration: 1.15).delay(0.35)) {
            holoSweep = 1.4
        }
        try? await Task.sleep(for: .seconds(1.2))
        guard gen == g else { return }
        withAnimation(.easeOut(duration: 0.4)) { holoStrength = 0 }

        // The struck date already sits in the caption line — land the beat.
        haptics.thunk()
        phaseLine = "Dated and kept forever."
        try? await Task.sleep(for: .seconds(1.6))
        guard gen == g else { return }

        // Loop seam: fade, reset off-screen, fade back.
        withAnimation(.easeIn(duration: 0.3)) { stampOpacity = 0 }
        try? await Task.sleep(for: .seconds(0.35))
        guard gen == g else { return }
        waveDriver.stop()
        resetPose()
        stampOpacity = 0
        await afterNextCommit()
        guard gen == g else { return }
        withAnimation(.easeOut(duration: 0.3)) { stampOpacity = 1 }
        try? await Task.sleep(for: .seconds(0.5))
    }
}
