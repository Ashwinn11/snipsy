import SwiftUI

/// Stamp assembly. Continuity chain:
///   develop leaves the *stamp* at the viewfinder → it glides to center →
///   the die cutter punches the sticker outline into the photo → the waste
///   fades away → perforated paper unfurls behind it → the caption rises
///   letter by letter → on Keep, the cancellation mark strikes and the stamp flies
///   into the collection pill.
struct RevealScreen: View {
    let pending: PendingStamp
    let model: AppModel
    let screenSize: CGSize
    let safeArea: EdgeInsets

    // Stage state
    @State private var centered = false
    /// How much sticker the artifact is right now: one spring owns the
    /// whole crossfade. The outline rides it directly and the plain photo
    /// rides its complement, so overlay + photo always cover the subject
    /// through any switch — no curve combination can blank or double it.
    @State private var stickerness: Double = 0
    /// Waste grain-dissolve progress (0 intact → 1 gone), one-shot and
    /// FORWARD-ONLY: switches never reverse it. Advanced per display tick
    /// with a clamped dt (shader args don't tween, and a main-thread hitch
    /// must pause the wave, never teleport it).
    @State private var wasteProgress: Double = 0
    /// Seconds for a full 0→1 sweep; 0.25 when an interrupt finishes the
    /// shatter early.
    @State private var waveDuration: Double = 1.15
    @State private var waveDriver = DisplayLinkDriver()
    /// The first cut's wave has been committed (target 1, forever). Set
    /// immediately before driveWave — a punch-phase abort leaves this
    /// false, so the next sticker tap replays the full first cut.
    @State private var waveCommitted = false
    /// The cut piece's flight to its composed frame (Assembly.flight).
    @State private var flight: Double = 0
    /// Die-press dip, swept 0→1 by the first cut only (Assembly.press).
    @State private var press: Double = 0
    /// Bumped on every select (and Keep); a choreography that awakes from
    /// an await into a different generation must not touch the stage.
    @State private var switchGen = 0
    /// Rename entry swaps shader-modifier identity, which snaps every
    /// in-flight spring — hold it off while a switch settles.
    @State private var lastSelectAt = Date.distantPast
    /// Up from the first frame. The develop dissolve already handed over a
    /// perforated plate, so fading paper in here would mean fading in
    /// something the user is looking at.
    @State private var paper: Double = 1
    @State private var caption: Double = 0
    @State private var settle: Double = 0
    @State private var chromeVisible = false
    /// Keep pill's measured width — re-centers the lone retake button
    /// before a selection exists (Keep hidden), exact for any locale.
    @State private var keepWidth: CGFloat = 0

    /// One row: the bare sticker, the instant formats, then the papers.
    enum ArtifactChoice: Equatable {
        case sticker
        case polaroid
        case card
        case paper(StampVariant)
    }
    @State private var options = false
    @State private var selection: ArtifactChoice? = nil
    /// True while the showing selection is the one the reveal made for the
    /// user (the default die cut) rather than one they tapped — keeps the
    /// chooser's prompt up so the default doesn't read as final.
    @State private var autoSelected = false
    /// The edition already on screen when the reveal opens. Bleed is the
    /// landing (`runEntrance` confirms it a beat later) and the photo *is*
    /// its plate, so this is the only variant that can be up before the
    /// user has chosen anything without inventing furniture they didn't ask
    /// for. Starting on `.tinted` meant the handoff drew a plateless crop
    /// and then dressed it — the beat this whole chain exists to remove.
    @State private var selectedVariant: StampVariant = .bleed

    // Instant formats — crossfaded over the stamp stack by value, one fade
    // per format so polaroid ↔ card animates too. Both views stay mounted
    // from the first frame (0.001 floor) so their grain shaders pre-pay.
    @State private var polaroidFade: Double = 0
    @State private var cardFade: Double = 0
    /// One-shot polaroid develop beat (photo prints 65% → full).
    @State private var polaroidDevelop: Double = 1
    @State private var firstPolaroidDone = false

    /// Whether an instant format owns the stage (gates hit-testing and the
    /// stamp's rename wiring).
    private var altSelected: Bool {
        selection == .polaroid || selection == .card
    }

    /// The stage frame's height/width for the current selection.
    private var currentAspect: CGFloat {
        switch selection {
        case .polaroid: PolaroidView.aspect
        case .card: CardView.aspect
        default: 1.3125
        }
    }

    // Liquid poke on the die-cut sticker
    @State private var rippleCenter: CGPoint = .zero
    @State private var rippleStart: Date? = nil

    // Holo sweep on dress
    @State private var holoSweep: Double = -0.4
    @State private var holoStrength: Double = 0

    // Keep flow
    /// Set the moment Keep is accepted — re-entry guard for the flight.
    @State private var keeping = false
    @State private var flying = false
    @State private var stampGone = false

    // Title
    @State private var title: String
    @State private var editingTitle = false
    @FocusState private var titleFocused: Bool

    init(pending: PendingStamp, model: AppModel, screenSize: CGSize, safeArea: EdgeInsets) {
        self.pending = pending
        self.model = model
        self.screenSize = screenSize
        self.safeArea = safeArea
        _title = State(initialValue: pending.suggestedTitle ?? "")
    }

    // MARK: Frames

    /// Where the develop dissolve left the plate — the entry frame, and the
    /// only frame this is ever asked for (`stampFrame` uses it until the
    /// glide starts, by which time bleed is the selection).
    ///
    /// Same derivation the dissolve cut its silhouette from, so the plate
    /// materialises exactly on top of itself: no scale step, no shape step,
    /// nothing for the phase crossfade to hide. The old frame inflated the
    /// crop to a *plated* stamp's content rect — right for `.tinted`, but
    /// 18% too wide for the bleed the reveal actually lands on.
    private var landedFrame: CGRect {
        StampView.plateRect(inscribedIn: pending.capture.viewfinderRect)
    }

    private var centeredFrame: CGRect {
        let w = min(screenSize.width * 0.72, 330)
        let h = w * currentAspect
        return CGRect(x: (screenSize.width - w) / 2,
                      y: screenSize.height * 0.42 - h / 2,
                      width: w, height: h)
    }

    private var flyFrame: CGRect {
        let pill = model.pillFrame
        guard pill != .zero else { return centeredFrame }
        let h: CGFloat = 42
        let w = h / currentAspect
        return CGRect(x: pill.midX - w / 2, y: pill.midY - h / 2, width: w, height: h)
    }

    private var stampFrame: CGRect {
        if flying { return flyFrame }
        return centered ? centeredFrame : landedFrame
    }

    // MARK: Body

    var body: some View {
        ZStack {
            // Texture pre-warm: force the sticker bitmap through upload
            // during the entrance beat, so its first real composite costs
            // nothing. Tiny, invisible, and behind paper.
            Group {
                if let sticker = pending.sticker {
                    Image(uiImage: sticker).resizable().frame(width: 2, height: 2)
                }
                if let cutout = pending.cutout {
                    Image(uiImage: cutout).resizable().frame(width: 2, height: 2)
                }
            }
            .opacity(0.001)
            .allowsHitTesting(false)

            PaperBackdrop()
                .opacity(flying ? 0 : 1)
                .animation(.easeInOut(duration: 0.4), value: flying)

            stampLayer

            optionsChooser

            chrome
        }
        // Same pinning as CameraScreen/DevelopOverlay: placement must not
        // depend on the parent's (occasionally overshooting) proposal.
        .frame(width: screenSize.width, height: screenSize.height)
        .onAppear {
            stampNumber = model.store.nextNumber
            wireWaveDriver()
            runEntrance()
        }
        .onDisappear { waveDriver.stop() }
        .onTapGesture { if editingTitle { stopEditingTitle() } }
    }

    private func startEditingTitle() {
        // Edit mode drops the holo/liquid shader modifiers (identity swap),
        // which snaps every in-flight presentation value — not while a
        // switch is still settling.
        guard Date().timeIntervalSince(lastSelectAt) > 0.6 else { return }
        model.haptics.tick()
        editingTitle = true
        titleFocused = true
    }

    private func stopEditingTitle() {
        editingTitle = false
        titleFocused = false
    }

    @State private var stampNumber: Int = 1

    @ViewBuilder
    private var stampLayer: some View {
        let frame = stampFrame

        TimelineView(.animation(paused: rippleStart == nil)) { timeline in
            let rippleTime = rippleStart.map { timeline.date.timeIntervalSince($0) } ?? 10

            ZStack {
                StampView(
                    image: pending.displayImage,
                    style: pending.style,
                    tint: pending.tint.color,
                    title: title,
                    number: stampNumber,
                    date: .now,
                    variant: selectedVariant,
                    stickerBox: pending.stickerBox,
                    rawCrop: pending.capture.cropImage,
                    maskImage: pending.cutout,
                    labelAnchor: pending.stickerLabelAnchor,
                    assembly: assembly(),
                    holoEnabled: true,
                    holoStrength: holoStrength,
                    holoSweep: holoSweep,
                    liquidEnabled: true,
                    liquidCenter: rippleCenter,
                    liquidTime: rippleTime,
                    editableTitle: editingTitle && !altSelected ? $title : nil,
                    titleFocused: $titleFocused,
                    onSubmitTitle: { stopEditingTitle() },
                    onTapCaption: chromeVisible && !flying && !altSelected
                        ? { startEditingTitle() } : nil
                )
                .opacity(max(0.001, 1 - max(polaroidFade, cardFade)))
                .allowsHitTesting(!altSelected)

                // Instant formats ride their own fades over the stamp
                // stack, wearing the poke ripple externally. Off while
                // renaming — a live TextField never sits under a shader.
                PolaroidView(
                    image: pending.capture.cropImage,
                    title: title,
                    date: .now,
                    develop: polaroidDevelop,
                    editableTitle: editingTitle && selection == .polaroid ? $title : nil,
                    titleFocused: $titleFocused,
                    onSubmitTitle: { stopEditingTitle() },
                    onTapCaption: chromeVisible && !flying && selection == .polaroid
                        ? { startEditingTitle() } : nil
                )
                .modifier(LiquidModifier(enabled: !editingTitle,
                                         center: rippleCenter, time: rippleTime))
                .opacity(max(0.001, polaroidFade))
                .allowsHitTesting(selection == .polaroid)

                CardView(
                    image: pending.capture.cropImage,
                    title: title,
                    date: .now,
                    editableTitle: editingTitle && selection == .card ? $title : nil,
                    titleFocused: $titleFocused,
                    onSubmitTitle: { stopEditingTitle() },
                    onTapCaption: chromeVisible && !flying && selection == .card
                        ? { startEditingTitle() } : nil
                )
                .modifier(LiquidModifier(enabled: !editingTitle,
                                         center: rippleCenter, time: rippleTime))
                .opacity(max(0.001, cardFade))
                .allowsHitTesting(selection == .card)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .gesture(
            SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                pokeStamp(at: value.location)
            }
        )
        .position(x: frame.midX, y: frame.midY)
        .rotationEffect(.degrees(flying ? -8 : 0))
        .opacity(stampGone ? 0 : 1)
        .animation(Theme.spring, value: flying)
    }

    /// Poke the die-cut: a liquid ripple rolls out from the touch point.
    private func pokeStamp(at point: CGPoint) {
        guard !flying, !stampGone else { return }
        if editingTitle {
            stopEditingTitle()
            return
        }
        rippleCenter = point
        let start = Date()
        rippleStart = start
        model.haptics.tick()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if rippleStart == start { rippleStart = nil }
        }
    }

    /// The grain wave's integrator: per display frame, clamped dt, so a
    /// hitch pauses the wave rather than teleporting it — and, unlike a
    /// timeline `.onChange`, it cannot starve mid-wave under load.
    /// Forward-only by construction: there is no reverse branch to race.
    private func wireWaveDriver() {
        waveDriver.onTick = { dt in
            wasteProgress = min(1, wasteProgress + dt / waveDuration)
            return wasteProgress < 1
        }
    }

    /// Run the wave toward 1 at the given full-range rate. Re-invoking
    /// only retunes the rate — progress never rewinds.
    private func driveWave(duration: Double) {
        waveDuration = duration
        waveDriver.start()
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

    /// Wait until the grain wave has consumed most of the waste (or a
    /// stall timeout passes). Flights are gated on the wave itself, not
    /// the clock: if a hitch pauses the grains, the piece must not fly
    /// out from beneath them.
    private func waveReached(_ threshold: Double) async {
        let start = Date()
        while wasteProgress < threshold,
              Date().timeIntervalSince(start) < 3 {
            try? await Task.sleep(for: .seconds(0.05))
        }
    }

    // MARK: Choreography

    private func runEntrance() {
        Task { @MainActor in
            // The first frame carries the raw crop's texture and the glass
            // chrome's one-time setup; gate the glide on its commit so the
            // spring plays on screen instead of finishing during a stall.
            // The longer hold also lets the develop overlay's teardown
            // (a big texture + shader raster) finish on this static frame
            // instead of inside the glide.
            await afterNextCommit()
            try? await Task.sleep(for: .seconds(0.08))
            await afterNextCommit()
            withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                centered = true
            }
            // Options rise WHILE the crop glides to center — the chooser
            // is tappable the moment the glide settles, not a beat after.
            try? await Task.sleep(for: .seconds(0.16))
            // Pre-render the caption glyphs invisibly while the glide covers
            // the cost. `paper` is NOT pre-warmed here any more: it is
            // already 1, carrying the plate the develop handed over, and
            // dropping it to 0.001 for a frame would blank the stamp
            // mid-glide.
            caption = 0.001
            await afterNextCommit()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                options = true
            }

            // Bleed is already on screen — the develop handed it over cut.
            // This only *commits* it as the selection, which is what lights
            // the option, runs the holo sweep and raises the chrome. A tap
            // inside this beat still wins.
            try? await Task.sleep(for: .seconds(0.3))
            guard case .reveal = model.phase else { return }
            if selection == nil { select(.paper(.bleed), auto: true) }

            // The first-ever output screen is the wow moment — worth one
            // of the year's three rating prompts. Held until after the cut
            // has run (punch 0.45s + wave 1.15s + settle), so the prompt
            // never lands mid-shatter.
            try? await Task.sleep(for: .seconds(2.8))
            if case .reveal = model.phase {
                model.reviews.fire(.firstReveal)
            }
        }
    }


    /// An option was tapped. The FIRST cut is the hero moment: punch →
    /// grain shatter → flight, gated on the wave itself. Every later
    /// switch is a fast morph (~0.45s): the plain photo and the outline
    /// crossfade on one complementary spring while the piece glides — no
    /// wave, no punch, nothing that can leave leftovers. The wave is
    /// one-shot and forward-only; interrupting the first cut finishes the
    /// shatter fast, never reverses it. Gen guards protect only the
    /// stage-mutating tails — one-shot ambient tails (chrome reveal, holo
    /// decay) must run regardless, or an early re-tap strands them.
    private func select(_ choice: ArtifactChoice, auto: Bool = false) {
        guard selection != choice else { return }
        model.haptics.tick()
        autoSelected = auto
        let first = selection == nil
        switchGen += 1
        let gen = switchGen
        lastSelectAt = Date()
        withAnimation(Theme.spring) { selection = choice }
        if case .paper(let v) = choice {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                selectedVariant = v
            }
        }
        Task { @MainActor in
            switch choice {
            case .sticker:
                // Coming from an instant format: hand the stage back to
                // the stamp stack before (or while) the cut plays.
                if polaroidFade > 0 || cardFade > 0 {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        polaroidFade = 0
                        cardFade = 0
                    }
                }
                if !waveCommitted {
                    // FIRST CUT — cinematic. The press dips the sheet and
                    // the outline appears…
                    await afterNextCommit()
                    guard gen == switchGen else { break }
                    model.haptics.tick()
                    // The sheet has to leave WITH the punch, not after the
                    // wave. `assembly()` ties `photoFade` to `1 - stickerness`,
                    // so once the reveal started defaulting to a dressed
                    // stamp (`paper == 1`) rather than the bare crop, the
                    // photo faded out while the paper was still up — a blank
                    // stamp for the whole cut. The switch path below already
                    // drops both together; this is the same move.
                    withAnimation(.easeOut(duration: 0.10)) { caption = 0.001 }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        stickerness = 1
                        press = 1
                        paper = 0.001
                    }
                    try? await Task.sleep(for: .seconds(0.45))
                    guard gen == switchGen else { break }
                    // …then the waste shatters off the cut line — a grain
                    // wave radiating outward — and the piece settles. From
                    // here the wave only ever moves forward.
                    waveCommitted = true
                    model.haptics.grains(duration: 0.8)
                    driveWave(duration: 1.15)
                    await waveReached(0.90)
                    guard gen == switchGen else { break }
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        settle = 1
                        flight = 1
                        paper = 0.001
                        caption = 0.001
                    }
                } else {
                    // SWITCH → sticker: one complementary crossfade while
                    // the piece lifts. The caption dies before the tag can
                    // rise (the tag lives in the top half of the outline).
                    withAnimation(.easeOut(duration: 0.10)) { caption = 0.001 }
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.86)) {
                        stickerness = 1
                        settle = 1
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        paper = 0.001
                    }
                    // Immediate in steady state; only suspends inside the
                    // ≤0.25s accelerated-shatter race — the sheet must
                    // never travel wearing waste.
                    await waveReached(0.90)
                    guard gen == switchGen else { break }
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.86)) {
                        flight = 1
                    }
                }
            case .polaroid, .card:
                // Instant format: land the photo (finish any shatter
                // forward, melt any half punch) and crossfade the format
                // over the stamp stack — the raw photo showing through
                // mid-fade reads as the print re-framing.
                if waveCommitted {
                    if wasteProgress < 1 { driveWave(duration: 0.25) }
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.86)) {
                        stickerness = 0
                        flight = 0
                        settle = 1
                    }
                } else {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                        stickerness = 0
                        press = 0
                        flight = 0
                        settle = 1
                    }
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    paper = 0.001
                    caption = 0.001
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    polaroidFade = choice == .polaroid ? 1 : 0
                    cardFade = choice == .card ? 1 : 0
                }
                if choice == .polaroid, !firstPolaroidDone {
                    // The develop beat: the print rises to full exposure.
                    firstPolaroidDone = true
                    polaroidDevelop = 0
                    withAnimation(.easeOut(duration: 0.9).delay(0.25)) {
                        polaroidDevelop = 1
                    }
                }
            case .paper:
                if waveCommitted {
                    // SWITCH → stamp: finish any unfinished shatter fast
                    // (forward — un-shattering reads as broken), then one
                    // crossfade home: photo in, outline out, piece lands.
                    if wasteProgress < 1 { driveWave(duration: 0.25) }
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.86)) {
                        stickerness = 0
                        flight = 0
                        paper = 1
                        settle = 1
                        polaroidFade = 0
                        cardFade = 0
                    }
                } else {
                    // Nothing was ever cut (or the punch was aborted) —
                    // the whole photo, framed; melt any half punch back.
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                        stickerness = 0
                        press = 0
                        flight = 0
                        paper = 1
                        settle = 1
                        polaroidFade = 0
                        cardFade = 0
                    }
                }
                if first {
                    // Holographic sweep across the fresh stamp.
                    holoStrength = 0.4
                    withAnimation(.easeInOut(duration: 1.15).delay(0.35)) {
                        holoSweep = 1.4
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(.easeOut(duration: 0.4)) { holoStrength = 0 }
                    }
                }
                if caption < 0.5 {
                    // After the die-cut tag is provably dead (border 0.5).
                    // No `break` on staleness: the chrome tail below must
                    // still run for a superseded FIRST selection.
                    try? await Task.sleep(for: .seconds(0.2))
                    if gen == switchGen {
                        withAnimation(.linear(duration: 0.5)) { caption = 1 }
                    }
                }
            }
            if first {
                // One-shot ambient tail: NOT gen-guarded — a quick re-tap
                // must not strand the chrome unreachable. Keep hides it
                // through the flying guard instead.
                try? await Task.sleep(for: .seconds(0.4))
                if !flying {
                    withAnimation(Theme.spring) { chromeVisible = true }
                }
            }
        }
    }

    private func keepTapped() {
        guard !flying, !keeping else { return }
        stopEditingTitle()
        model.haptics.thunk()
        // Supersede any in-flight switch choreography and land the current
        // selection at its terminal values — the artifact must fly whole,
        // and no stale tail may mutate the stage mid-flight.
        switchGen += 1
        if wasteProgress < 1, waveCommitted { driveWave(duration: 0.25) }

        if selection == .sticker {
            // Stickers fly uncancelled — no date strike.
            Task { @MainActor in
                withAnimation(Theme.spring) {
                    stickerness = 1
                    flight = 1
                    settle = 1
                    paper = 0.001
                    caption = 0.001
                    flying = true
                    chromeVisible = false
                }
                withAnimation(.easeIn(duration: 0.18).delay(0.34)) {
                    stampGone = true
                }
                try? await Task.sleep(for: .seconds(0.52))
                model.keep(pending, title: title, variant: .tinted, kind: .sticker)
            }
            return
        }

        if altSelected {
            // Instant formats fly whole — the format view already owns the
            // stage, nothing to restore underneath it.
            let kind: ArtifactKind = selection == .polaroid ? .polaroid : .card
            keeping = true
            Task { @MainActor in
                withAnimation(Theme.spring) {
                    stickerness = 0
                    flight = 0
                    settle = 1
                }
                await afterNextCommit()
                try? await Task.sleep(for: .seconds(0.35))
                withAnimation(Theme.spring) {
                    flying = true
                    chromeVisible = false
                }
                withAnimation(.easeIn(duration: 0.18).delay(0.34)) {
                    stampGone = true
                }
                try? await Task.sleep(for: .seconds(0.52))
                model.keep(pending, title: title, variant: .tinted, kind: kind)
            }
            return
        }

        withAnimation(Theme.spring) {
            stickerness = 0
            flight = 0
            settle = 1
            paper = 1
            caption = 1
        }
        keeping = true
        Task { @MainActor in
            await afterNextCommit()
            try? await Task.sleep(for: .seconds(0.55))
            withAnimation(Theme.spring) {
                flying = true
                chromeVisible = false
            }
            withAnimation(.easeIn(duration: 0.18).delay(0.34)) {
                stampGone = true
            }
            try? await Task.sleep(for: .seconds(0.52))
            model.keep(pending, title: title, variant: selectedVariant, kind: .stamp)
        }
    }

    // MARK: Options

    /// One scrolling row: sticker first, then the ten editions. Mounted
    /// from the reveal's first frame at near-zero opacity so the one-time
    /// render cost (mini paper shaders + textures) is pre-paid, never
    /// inside its spring.
    private var optionsChooser: some View {
        let shown = options && !flying && !editingTitle
        let rowY = screenSize.height - max(safeArea.bottom, 16) - 158

        return VStack(spacing: 14) {
            // The default cut isn't a decision the user made — keep the
            // prompt up (reworded) until they actually pick something.
            Text(autoSelected ? "Or make it a…" : "Make it a…")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .opacity(selection == nil || autoSelected ? 1 : 0)

            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 13) {
                if pending.style == .cutout, let sticker = pending.sticker {
                    optionButton(.sticker, selected: selection == .sticker) {
                        Image(uiImage: sticker)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 68)
                            .shadow(color: Theme.shadow.opacity(0.22), radius: 3, y: 2)
                    }
                }
                optionButton(.paper(.bleed), selected: selection == .paper(.bleed)) {
                    StampView(
                        image: pending.displayImage,
                        style: pending.style,
                        tint: pending.tint.color,
                        title: "",
                        number: stampNumber,
                        variant: .bleed,
                        stickerBox: pending.stickerBox,
                        rawCrop: pending.capture.cropImage,
                        assembly: thumbAssembly
                    )
                    .frame(width: 52)
                }
                optionButton(.polaroid, selected: selection == .polaroid) {
                    PolaroidView(image: pending.capture.cropImage,
                                 title: "", appear: 0)
                        .frame(width: 52)
                }
                optionButton(.card, selected: selection == .card) {
                    CardView(image: pending.capture.cropImage,
                             title: "", appear: 0)
                        .frame(width: 52)
                }
                ForEach(StampVariant.allCases.filter { $0 != .bleed }) { v in
                    optionButton(.paper(v), selected: selection == .paper(v)) {
                        StampView(
                            image: pending.displayImage,
                            style: pending.style,
                            tint: pending.tint.color,
                            title: "",
                            number: stampNumber,
                            variant: v,
                            stickerBox: pending.stickerBox,
                            rawCrop: pending.capture.cropImage,
                            assembly: thumbAssembly
                        )
                        .frame(width: 52)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            }
            .frame(width: screenSize.width)
        }
        .position(x: screenSize.width / 2, y: rowY)
        .opacity(shown ? 1 : 0.001)
        .offset(y: shown ? 0 : 18)
        .allowsHitTesting(shown)
        .animation(.easeOut(duration: 0.2), value: editingTitle)
    }

    private func optionButton<Preview: View>(
        _ choice: ArtifactChoice, selected: Bool,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        Button {
            select(choice)
        } label: {
            preview()
                .frame(width: 56, height: 70)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.postalRed, lineWidth: 1.6)
                        .padding(-4)
                        .opacity(selected ? 1 : 0)
                }
        }
        .buttonStyle(PressableButtonStyle())
        .scaleEffect(selected ? 1.07 : 1)
    }

    /// Full photo on paper, caption hidden — the minis are about the paper.
    private var thumbAssembly: StampView.Assembly {
        StampView.Assembly(paper: 1, caption: 0, settle: 1,
                           border: 0, waste: 1, content: .raw)
    }

    // MARK: Chrome

    /// Always mounted, opacity/offset-driven: the glass materials pay their
    /// one-time setup with the reveal's first frame (behind a static beat),
    /// so showing the chrome is a pure animation with nothing left to build.
    @ViewBuilder
    private var chrome: some View {
        let barY = screenSize.height - max(safeArea.bottom, 16) - 50
        // Retake is the only exit before a choice is made — it rises with
        // the options row. Keep still waits for a selection. Both hide
        // while editing text so they don't stick over the keyboard/field.
        let retakeShown = options && !flying && !editingTitle
        let keepShown = chromeVisible && !editingTitle

        Group {
            HStack(spacing: 14) {
                Button {
                    model.haptics.tick()
                    model.retake()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 54, height: 54)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .opacity(retakeShown ? 1 : 0)
                .offset(y: retakeShown ? 0 : 14)
                .allowsHitTesting(retakeShown)

                Button(action: keepTapped) {
                    HStack(spacing: 8) {
                        Image(systemName: "seal.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Keep")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 34)
                    .frame(height: 54)
                    .background(Theme.postalRed, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .opacity(keepShown ? 1 : 0)
                .offset(y: keepShown ? 0 : 14)
                .allowsHitTesting(keepShown)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                    keepWidth = $0
                }
            }
            // Lone retake sits dead-center; when Keep fades in it glides
            // left into the pair. chromeVisible flips inside springs, so
            // the slide rides the same animation.
            .offset(x: keepShown ? 0 : (keepWidth + 14) / 2)
            .position(x: screenSize.width / 2, y: barY)
        }
    }
}

/// Gentle scale-on-press for filled buttons.
///
/// Used on nearly every button in the app, including ones tapped
/// repeatedly in a single sitting (paywall plan cards, onboarding
/// continues, "Take a photo" / "Make another"). `springBouncy` (response
/// 0.5) reads fine for a one-off celebration but turns a workhorse tap
/// into a slow squish-and-rebound when it fires dozens of times a
/// session — `springTight` settles in roughly a third of the time with
/// almost no overshoot, which reads as responsive rather than springy.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.springTight, value: configuration.isPressed)
    }
}
