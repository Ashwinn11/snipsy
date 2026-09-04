import SwiftUI

/// Page 1: the hook. Shows the one transformation that happens to every
/// single photo, no exceptions: the photo itself becomes the stamp, masked
/// straight to the perforated silhouette — no paper plate, no caption, no
/// keyline. That is `StampVariant.bleed`, confirmed as the real default
/// twice over: it is what `DevelopOverlay` produces after every capture
/// ("the kept region is the perforated silhouette"), and it is
/// `RevealScreen`'s own starting `selectedVariant`, whose comment there
/// explicitly rules out `.tinted` for this exact moment — "Starting on
/// `.tinted` meant the handoff drew a plateless crop and then dressed it —
/// the beat this whole chain exists to remove."
///
/// Not the die-cut: that only fires when Vision finds a liftable subject,
/// and even then it's just `RevealScreen`'s suggested starting *style*, not
/// a separate guaranteed step. `.bleed` is universal; the die-cut isn't —
/// so `.bleed` is the honest thing to open on. This also protects the
/// sticker/stamp fork for page 4's reveal, not by omission but because
/// there is no die-cut here to spoil.
///
/// Tap response reuses `RevealScreen`'s real poke — a liquid ripple from
/// the touch point (`StampView`'s `liquidEnabled`/`liquidCenter`/
/// `liquidTime`, the same `LiquidModifier` the real reveal pokes). Not
/// invented here: two earlier attempts at a custom tap reaction (a hard
/// reset, then a scale/opacity dip) both animated `paper`, and `.bleed`'s
/// entire visibility rides on `paper` — so both read as the stamp
/// blinking. The real interaction never touches visibility at all.
///
/// Deliberately stamp-first: no Canvas, no multi-item page, no "lay things
/// out" pitch. The paywall already made this call in its own comment —
/// turning a photo into a stamp can't be what's sold, since several free
/// apps already do it — so it isn't what onboarding leads with either.
/// Canvas gets exactly one sentence, near the very end, once the user
/// already has something worth building a page out of.
struct OnboardingHookPage: View {
    let demo: OnboardingDemo
    let haptics: Haptics
    let isActive: Bool
    let screenSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Mirrors `Assembly.paper` — the only field `.bleed` reads (its
    /// `bleedBody` drives opacity + a 0.94→1 scale-in off it directly;
    /// `.caption` is a no-op here, `.bleed.hidesCaption == true`).
    @State private var paper: Double = 0
    /// Bumped on every restart/stop; a cycle that wakes into a different
    /// generation must exit silently.
    @State private var gen = 0

    /// Poke ripple state — mirrors `RevealScreen.rippleCenter`/`.rippleStart`
    /// exactly.
    @State private var rippleCenter: CGPoint = .zero
    @State private var rippleStart: Date? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                OnboardingTitle("PHOTOS PILE UP. THIS ONE GETS KEPT.")
                Text("It's a stamp now, on your phone —\ndone in seconds.")
                    .font(.system(size: 14.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            stage
                .frame(height: stampWidth * 1.3125)

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.top, 30)
        .onAppear {
            demo.load()
            if isActive { startCycle() }
        }
        .onChange(of: isActive) { _, active in
            if active { startCycle() } else { stopCycle() }
        }
        .onChange(of: demo.subject(Self.subjectKey) == nil) { _, _ in
            if isActive { startCycle() }
        }
        .onDisappear { stopCycle() }
    }

    private static let subjectKey = "puppy"

    private var stampWidth: CGFloat { min(screenSize.width * 0.58, 250) }

    @ViewBuilder
    private var stage: some View {
        if let subject = demo.subject(Self.subjectKey) {
            TimelineView(.animation(paused: rippleStart == nil)) { timeline in
                let rippleTime = rippleStart.map { timeline.date.timeIntervalSince($0) } ?? 10
                StampView(
                    image: subject.photo,
                    style: .classic,
                    tint: subject.tint.color,
                    title: subject.title,
                    number: 1,
                    variant: .bleed,
                    assembly: assembly,
                    liquidEnabled: true,
                    liquidCenter: rippleCenter,
                    liquidTime: rippleTime
                )
                .frame(width: stampWidth)
                .gesture(
                    SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                        pokeStamp(at: value.location)
                    }
                )
            }
            .frame(width: stampWidth, height: stampWidth * 1.3125)
        } else {
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

    private var assembly: StampView.Assembly {
        var a = StampView.Assembly()
        a.paper = paper
        return a
    }

    /// Poke the stamp: a liquid ripple rolls out from the touch point.
    /// Verbatim `RevealScreen.pokeStamp` — same duration, same haptic.
    private func pokeStamp(at point: CGPoint) {
        rippleCenter = point
        let start = Date()
        rippleStart = start
        haptics.tick()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if rippleStart == start { rippleStart = nil }
        }
    }

    // MARK: Cycle — plays once, holds on the finished stamp (no loop,
    // matching the "stays on the finished piece" rule every other animated
    // onboarding page already follows)

    private func stopCycle() {
        gen += 1
    }

    private func startCycle() {
        guard demo.subject(Self.subjectKey) != nil else { return }
        gen += 1
        let g = gen

        if reduceMotion {
            paper = 1
            return
        }

        Task { @MainActor in
            await runCycle(g)
        }
    }

    private func runCycle(_ g: Int) async {
        await afterNextCommit()
        try? await Task.sleep(for: .seconds(0.3))
        guard gen == g else { return }

        // Photo settles into the perforated silhouette — the same beat
        // `DevelopOverlay`'s dissolve leaves on every real capture.
        haptics.tick()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            paper = 1
        }
        try? await Task.sleep(for: .seconds(0.3))
        guard gen == g else { return }
        haptics.thunk()
    }
}
