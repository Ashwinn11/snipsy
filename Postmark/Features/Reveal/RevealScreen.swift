import SwiftUI

/// Stamp assembly. Continuity chain:
///   develop leaves the crop at the viewfinder → the crop glides to center →
///   a second grain pass eats everything but the subject → perforated paper
///   unfurls behind it → the caption rises letter by letter → on Keep, the
///   postmark strikes and the stamp flies into the collection pill.
struct RevealScreen: View {
    let pending: PendingStamp
    let model: AppModel
    let screenSize: CGSize
    let safeArea: EdgeInsets

    // Stage state
    @State private var centered = false
    @State private var maskStart: Date? = nil
    @State private var maskDone = false
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

    private let maskDuration: TimeInterval = 0.95

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
            PaperBackdrop()
                .opacity(flying ? 0 : 1)
                .animation(.easeInOut(duration: 0.4), value: flying)

            stampLayer

            chrome
        }
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

        TimelineView(.animation(paused: maskStart == nil || maskDone)) { timeline in
            let maskProgress = currentMaskProgress(at: timeline.date)

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
                assembly: assembly(maskProgress: maskProgress),
                holoStrength: holoStrength,
                holoSweep: holoSweep,
                editableTitle: editingTitle ? $title : nil,
                titleFocused: $titleFocused,
                onSubmitTitle: { stopEditingTitle() },
                onTapCaption: chromeVisible && !flying ? { startEditingTitle() } : nil
            )
            .onChange(of: maskProgress >= 1) { _, done in
                if done && !maskDone { finishUnmask() }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .rotationEffect(.degrees(flying ? -8 : 0))
        .opacity(stampGone ? 0 : 1)
        .animation(Theme.spring, value: flying)
    }

    private func currentMaskProgress(at date: Date) -> Double {
        guard let maskStart else { return 0 }
        if maskDone { return 1 }
        return min(1, date.timeIntervalSince(maskStart) / maskDuration)
    }

    private func assembly(maskProgress: Double) -> StampView.Assembly {
        var a = StampView.Assembly()
        a.paper = paper
        a.caption = caption
        a.settle = settle

        if pending.style == .cutout, let cutout = pending.cutout, !maskDone {
            if maskStart != nil {
                a.content = .unmasking(mask: cutout, progress: maskProgress)
            } else {
                a.content = .raw
            }
        } else {
            a.content = .final
        }
        return a
    }

    // MARK: Choreography

    private func runEntrance() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.08))
            withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
                centered = true
            }
            try? await Task.sleep(for: .seconds(0.55))
            if pending.style == .cutout, pending.cutout != nil {
                maskStart = Date()
                model.haptics.grains(duration: maskDuration * 0.8)
            } else {
                dress()
            }
        }
    }

    private func finishUnmask() {
        maskDone = true
        dress()
    }

    private func dress() {
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
        postmarked = true
        withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
            postmarkScale = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.78))
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

    @ViewBuilder
    private var chrome: some View {
        let barY = screenSize.height - max(safeArea.bottom, 16) - 50

        if chromeVisible {
            Text("№ \(model.store.nextNumber) in your collection")
                .font(.system(size: 14, design: .serif))
                .italic()
                .foregroundStyle(Theme.inkSoft)
                .position(x: screenSize.width / 2, y: barY - 64)
                .transition(.opacity.combined(with: .offset(y: 8)))

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
            .transition(.opacity.combined(with: .offset(y: 16)))
        }
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
