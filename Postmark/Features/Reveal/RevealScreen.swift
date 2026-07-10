import SwiftUI

/// Stamp assembly. Continuity chain:
///   develop leaves the crop at the viewfinder → the crop glides to center →
///   the die cutter punches the sticker outline into the photo → the waste
///   fades away → perforated paper unfurls behind it → the caption rises
///   letter by letter → on Keep, the postmark strikes and the stamp flies
///   into the collection pill.
struct RevealScreen: View {
    let pending: PendingStamp
    let model: AppModel
    let screenSize: CGSize
    let safeArea: EdgeInsets

    // Stage state
    @State private var centered = false
    /// Die-cut punch: the sticker outline pressed into the raw photo.
    @State private var border: Double = 0
    /// The raw photo around the cut sticker; fades to 0 after the punch.
    @State private var waste: Double = 1
    /// Swapped to .final once the waste is gone (pixel-identical states).
    @State private var assembled = false
    @State private var paper: Double = 0
    @State private var caption: Double = 0
    @State private var settle: Double = 0
    @State private var chromeVisible = false

    // Holo sweep on dress
    @State private var holoSweep: Double = -0.4
    @State private var holoStrength: Double = 0

    // Keep flow
    @State private var postmarked = false
    @State private var postmarkScale: CGFloat = 1.7
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

    /// Frame that puts the stamp's content rect exactly over the viewfinder.
    private var landedFrame: CGRect {
        let vf = pending.capture.viewfinderRect
        let w = vf.width / 0.85
        return CGRect(x: vf.minX - 0.075 * w, y: vf.minY - 0.075 * w,
                      width: w, height: w * 1.3125)
    }

    private var centeredFrame: CGRect {
        let w = min(screenSize.width * 0.72, 330)
        let h = w * 1.3125
        return CGRect(x: (screenSize.width - w) / 2,
                      y: screenSize.height * 0.42 - h / 2,
                      width: w, height: h)
    }

    private var flyFrame: CGRect {
        let pill = model.pillFrame
        guard pill != .zero else { return centeredFrame }
        let h: CGFloat = 42
        let w = h / 1.3125
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
            if let sticker = pending.sticker {
                Image(uiImage: sticker)
                    .resizable()
                    .frame(width: 2, height: 2)
                    .opacity(0.001)
                    .allowsHitTesting(false)
            }

            PaperBackdrop()
                .opacity(flying ? 0 : 1)
                .animation(.easeInOut(duration: 0.4), value: flying)

            stampLayer

            chrome
        }
        // Same pinning as CameraScreen/DevelopOverlay: placement must not
        // depend on the parent's (occasionally overshooting) proposal.
        .frame(width: screenSize.width, height: screenSize.height)
        #if DEBUG
        .background(GeometryReader { g in
            Color.clear.onAppear {
                dbgMark("reveal.globalFrame \(g.frame(in: .global)) landed \(landedFrame)")
            }
        })
        #endif
        .onAppear { runEntrance() }
        .onTapGesture { if editingTitle { stopEditingTitle() } }
    }

    private func startEditingTitle() {
        model.haptics.tick()
        editingTitle = true
        titleFocused = true
    }

    private func stopEditingTitle() {
        editingTitle = false
        titleFocused = false
    }

    @ViewBuilder
    private var stampLayer: some View {
        let frame = stampFrame

        StampView(
            image: pending.displayImage,
            style: pending.style,
            tint: pending.tint.color,
            title: title,
            number: model.store.nextNumber,
            year: String(Calendar.current.component(.year, from: Date())),
            date: .now,
            showsPostmark: postmarked,
            postmarkScale: postmarkScale,
            stickerBox: pending.stickerBox,
            rawCrop: pending.capture.cropImage,
            assembly: assembly(),
            holoEnabled: true,
            holoStrength: holoStrength,
            holoSweep: holoSweep,
            editableTitle: editingTitle ? $title : nil,
            titleFocused: $titleFocused,
            onSubmitTitle: { stopEditingTitle() },
            onTapCaption: chromeVisible && !flying ? { startEditingTitle() } : nil
        )
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .rotationEffect(.degrees(flying ? -8 : 0))
        .opacity(stampGone ? 0 : 1)
        .animation(Theme.spring, value: flying)
    }

    private func assembly() -> StampView.Assembly {
        var a = StampView.Assembly()
        a.paper = paper
        a.caption = caption
        a.settle = settle
        a.border = border
        a.waste = waste
        a.content = pending.style == .cutout && !assembled ? .raw : .final
        return a
    }

    // MARK: Choreography

    private func runEntrance() {
        dbgMark("reveal.onAppear")
        Task { @MainActor in
            // The first frame carries the raw crop's texture and the glass
            // chrome's one-time setup; gate the glide on its commit so the
            // spring plays on screen instead of finishing during a stall.
            // The longer hold also lets the develop overlay's teardown
            // (a big texture + shader raster) finish on this static frame
            // instead of inside the glide.
            await afterNextCommit()
            try? await Task.sleep(for: .seconds(0.3))
            await afterNextCommit()
            dbgMark("reveal.glide")
            withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
                centered = true
            }
            try? await Task.sleep(for: .seconds(0.62))
            await afterNextCommit()
            if pending.style == .cutout, pending.sticker != nil {
                // Die cut first: the press dips the sheet and the outline
                // appears around the subject. Nothing else is scheduled in
                // this window — the punch owns its frames.
                dbgMark("reveal.diecut")
                model.haptics.tick()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    border = 1
                }
                try? await Task.sleep(for: .seconds(0.55))
                // …then the waste sheet fades away, leaving the sticker.
                dbgMark("reveal.waste")
                withAnimation(.easeInOut(duration: 0.5)) {
                    waste = 0
                }
                try? await Task.sleep(for: .seconds(0.62))
                // Waste 0 and .final render identical pixels — swap quietly,
                // then pre-render the dressed layers invisibly (paper shader,
                // path shadows, caption glyphs) on this static beat.
                assembled = true
                paper = 0.001
                caption = 0.001
                await afterNextCommit()
                try? await Task.sleep(for: .seconds(0.1))
                dress()
            } else {
                assembled = true
                paper = 0.001
                caption = 0.001
                await afterNextCommit()
                dress()
            }
        }
    }

    private func dress() {
        dbgMark("reveal.dress")
        model.haptics.tick()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            paper = 1
            settle = 1
        }
        withAnimation(.linear(duration: 0.7).delay(0.22)) {
            caption = 1
        }
        withAnimation(Theme.spring.delay(0.3)) {
            chromeVisible = true
        }
        // Holographic sweep across the fresh stamp.
        holoStrength = 0.4
        withAnimation(.easeInOut(duration: 1.15).delay(0.35)) {
            holoSweep = 1.4
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.4)) { holoStrength = 0 }
        }
        #if DEBUG
        let autokeep = ProcessInfo.processInfo.environment["POSTMARK_AUTOKEEP"]
        if autokeep == "1" || autokeep == "2" {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.8))
                keepTapped()
                if autokeep == "2" {
                    try? await Task.sleep(for: .seconds(2.2))
                    withAnimation(Theme.spring) { model.showAlbum = true }
                }
            }
        }
        #endif
    }

    private func keepTapped() {
        guard !flying, !postmarked else { return }
        stopEditingTitle()
        model.haptics.thunk()
        dbgMark("reveal.keep")
        postmarked = true   // seal mounts at 1.7
        Task { @MainActor in
            await afterNextCommit()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                postmarkScale = 1
            }
            try? await Task.sleep(for: .seconds(0.75))
            dbgMark("reveal.fly")
            withAnimation(Theme.spring) {
                flying = true
                chromeVisible = false
            }
            withAnimation(.easeIn(duration: 0.18).delay(0.34)) {
                stampGone = true
            }
            try? await Task.sleep(for: .seconds(0.52))
            model.keep(pending, title: title)
        }
    }

    // MARK: Chrome

    /// Always mounted, opacity/offset-driven: the glass materials pay their
    /// one-time setup with the reveal's first frame (behind a static beat),
    /// so showing the chrome is a pure animation with nothing left to build.
    @ViewBuilder
    private var chrome: some View {
        let barY = screenSize.height - max(safeArea.bottom, 16) - 50

        Group {
            Text("№ \(model.store.nextNumber) in your collection")
                .font(.system(size: 14, design: .serif))
                .italic()
                .foregroundStyle(Theme.inkSoft)
                .position(x: screenSize.width / 2, y: barY - 64)

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

                Button(action: keepTapped) {
                    HStack(spacing: 8) {
                        Image(systemName: "seal.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Keep")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 34)
                    .frame(height: 54)
                    .background(Theme.postalRed, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .position(x: screenSize.width / 2, y: barY)
        }
        .opacity(chromeVisible ? 1 : 0)
        .offset(y: chromeVisible ? 0 : 14)
        .allowsHitTesting(chromeVisible)
    }
}

/// Gentle scale-on-press for filled buttons.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Theme.springTight, value: configuration.isPressed)
    }
}
