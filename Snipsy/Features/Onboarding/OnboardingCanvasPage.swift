import SwiftUI

/// Page 1: the pitch. The memory page builds itself — a dated stamp
/// template filling with photos, die-cuts and hand lettering. Two-column
/// grid, animates once top → bottom then **stays** on the finished
/// composition — no loop.
///
///   Left col (top → bottom): couple1 photo | lily sticker | ransom "love"
///   Right col (top → bottom): couple2 sticker | puppy sticker
///   Full-width bottom: die-cut "forever & always"
struct OnboardingCanvasPage: View {
    let demo: OnboardingDemo
    let haptics: Haptics
    let isActive: Bool
    let screenSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var canvasScale: Double = 0.88
    @State private var canvasOpacity: Double = 0
    @State private var dateEl: Double = 0      // top corners
    @State private var photoEl: Double = 0     // couple1 photo — upper-left
    @State private var stickerEl: Double = 0   // couple2 die-cut — upper-right
    @State private var lilyEl: Double = 0      // lily die-cut — lower-left
    @State private var puppyEl: Double = 0     // puppy die-cut — lower-right
    @State private var ransomEl: Double = 0    // ransom "love" — below lily
    @State private var diecutEl: Double = 0    // die-cut text — bottom

    @State private var gen = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                RansomText(text: "SNIPSY", fontSize: 24, ink: Theme.ink)
                Text("Turn a day together into something\nthey'll actually keep.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            canvasCard
                .scaleEffect(canvasScale)
                .opacity(canvasOpacity)

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.top, 30)
        .onAppear { if isActive { start() } }
        .onChange(of: isActive) { _, active in
            if active { start() } else { cancel() }
        }
        .onDisappear { cancel() }
    }

    // MARK: Sizing

    private var cardWidth: CGFloat  { min(screenSize.width * 0.72, 306) }
    private var cardHeight: CGFloat { cardWidth * 1.3125 }

    // MARK: Canvas card

    private var canvasCard: some View {
        ZStack(alignment: .topLeading) {
            // Powder-blue paper stock
            Color(hex: 0xD6E7F2)
                .overlay {
                    Canvas { ctx, size in
                        let step: CGFloat = 18
                        var x = step
                        while x < size.width {
                            var y = step
                            while y < size.height {
                                ctx.fill(
                                    Path(ellipseIn: CGRect(x: x - 0.7, y: y - 0.7,
                                                           width: 1.4, height: 1.4)),
                                    with: .color(Color(hex: 0x6A9EC0).opacity(0.20)))
                                y += step
                            }
                            x += step
                        }
                    }
                }

            canvasElements
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(PerforatedRect())
        .overlay {
            PerforatedRect()
                .stroke(Color(hex: 0x7AADC8).opacity(0.65),
                        style: StrokeStyle(lineWidth: 1.4, dash: [3.5, 4.0]))
        }
        .shadow(color: Color(hex: 0x2A5070).opacity(0.22), radius: 22, y: 11)
    }

    // MARK: Canvas elements — two-column, no overlaps

    @ViewBuilder
    private var canvasElements: some View {
        let w = cardWidth
        let h = cardHeight

        // ── Date labels ─────────────────────────────────────────────────────
        Text(Self.shortDate)
            .font(.system(size: w * 0.044, weight: .semibold, design: .serif))
            .foregroundStyle(Color(hex: 0x24445E).opacity(0.78))
            .opacity(dateEl)
            .scaleEffect(dateEl == 0 ? 0.5 : 1, anchor: .leading)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: dateEl)
            .offset(x: w * 0.056, y: h * 0.028)

        Text(Self.dayName)
            .font(.system(size: w * 0.044, weight: .semibold, design: .serif))
            .foregroundStyle(Color(hex: 0x24445E).opacity(0.78))
            .opacity(dateEl)
            .scaleEffect(dateEl == 0 ? 0.5 : 1, anchor: .trailing)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: dateEl)
            .offset(x: w * 0.63, y: h * 0.028)

        // ── Upper-left: couple1 raw photo ───────────────────────────────────
        // Occupies x[3%,45%]  y[8%,46%]
        if let photo = demo.canvasPhoto {
            rawPhoto(photo, width: w * 0.42)
                .rotationEffect(.degrees(-7))
                .scaleEffect(photoEl == 0 ? 0.25 : 1)
                .opacity(photoEl)
                .animation(.spring(response: 0.42, dampingFraction: 0.60), value: photoEl)
                .offset(x: w * 0.03, y: h * 0.085)
        }

        // ── Upper-right: couple2 die-cut ────────────────────────────────────
        // Occupies x[52%,95%]  y[7%,46%]
        if let couple = stickerAt(1) {
            Image(uiImage: couple)
                .resizable().scaledToFit()
                .frame(width: w * 0.43)
                .rotationEffect(.degrees(6))
                .scaleEffect(stickerEl == 0 ? 0.25 : 1)
                .opacity(stickerEl)
                .animation(.spring(response: 0.42, dampingFraction: 0.56), value: stickerEl)
                .shadow(color: Color(hex: 0x2A5070).opacity(0.22), radius: 7, y: 4)
                .offset(x: w * 0.52, y: h * 0.07)
        }

        // ── Lower-left: lily die-cut ────────────────────────────────────────
        // Occupies x[3%,31%]  y[49%,75%]
        if let lily = stickerAt(2) {
            Image(uiImage: lily)
                .resizable().scaledToFit()
                .frame(width: w * 0.28)
                .rotationEffect(.degrees(-10))
                .scaleEffect(lilyEl == 0 ? 0.25 : 1)
                .opacity(lilyEl)
                .animation(.spring(response: 0.42, dampingFraction: 0.56), value: lilyEl)
                .shadow(color: Color(hex: 0x2A5070).opacity(0.20), radius: 5, y: 3)
                .offset(x: w * 0.03, y: h * 0.49)
        }

        // ── Lower-right: puppy die-cut ──────────────────────────────────────
        // Occupies x[52%,82%]  y[49%,81%]
        if let puppy = stickerAt(3) {
            Image(uiImage: puppy)
                .resizable().scaledToFit()
                .frame(width: w * 0.30)
                .rotationEffect(.degrees(7))
                .scaleEffect(puppyEl == 0 ? 0.25 : 1)
                .opacity(puppyEl)
                .animation(.spring(response: 0.44, dampingFraction: 0.54), value: puppyEl)
                .shadow(color: Color(hex: 0x2A5070).opacity(0.20), radius: 5, y: 3)
                .offset(x: w * 0.52, y: h * 0.49)
        }

        // ── Below lily: ransom "love" ────────────────────────────────────────
        // Occupies x[3%,37%]  y[76%,84%]
        RansomLettering(text: "love", fontSize: w * 0.062)
            .rotationEffect(.degrees(-4))
            .scaleEffect(ransomEl == 0 ? 0.40 : 1, anchor: .leading)
            .opacity(ransomEl)
            .animation(.spring(response: 0.40, dampingFraction: 0.62), value: ransomEl)
            .offset(x: w * 0.03, y: h * 0.76)

        // ── Bottom: die-cut "forever & always" ──────────────────────────────
        // The real die-cut text — same heavy-rounded voice and dilated
        // contour the canvas editor cuts, so the pitch shows the product.
        DieCutText(text: "forever & always", fontSize: w * 0.076,
                   ink: Color(hex: 0x1C3050))
            .scaleEffect(diecutEl == 0 ? 0.60 : 1)
            .opacity(diecutEl)
            .animation(.spring(response: 0.44, dampingFraction: 0.64), value: diecutEl)
            .offset(x: w * 0.08, y: h * 0.87)
    }

    // MARK: Helpers

    private func stickerAt(_ index: Int) -> UIImage? {
        guard demo.subjects.count > index else { return nil }
        return demo.subjects[index].sticker
    }

    private func rawPhoto(_ image: UIImage, width: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: width * 1.18)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.04))
            .overlay(RoundedRectangle(cornerRadius: width * 0.04)
                .strokeBorder(.white.opacity(0.88), lineWidth: 2.5))
            .shadow(color: Color(hex: 0x2A5070).opacity(0.24), radius: 8, y: 5)
    }

    private static let shortDate: String = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: .now).uppercased()
    }()

    private static let dayName: String = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE"
        return f.string(from: .now).uppercased()
    }()

    // MARK: Animation — runs once, settles on final state (no loop)

    private func cancel() { gen += 1 }

    private func start() {
        gen += 1
        let g = gen
        resetPose()

        if reduceMotion {
            showAll()
            return
        }

        Task { @MainActor in
            await animate(g)
            // Intentionally does NOT loop — canvas stays on the finished composition.
        }
    }

    private func resetPose() {
        canvasScale = 0.88; canvasOpacity = 0
        dateEl = 0; photoEl = 0; stickerEl = 0
        lilyEl = 0; puppyEl = 0; ransomEl = 0; diecutEl = 0
    }

    private func showAll() {
        canvasScale = 1; canvasOpacity = 1
        dateEl = 1; photoEl = 1; stickerEl = 1
        lilyEl = 1; puppyEl = 1; ransomEl = 1; diecutEl = 1
    }

    /// Wait for Vision to finish processing all subjects (up to ~6 s),
    /// then build up the canvas top → bottom.
    private func animate(_ g: Int) async {
        // Give the Vision pipeline time to finish — puppy/lily/couple2 run live.
        var waited = 0
        while demo.subjects.count < 4 && waited < 30 {
            try? await Task.sleep(for: .milliseconds(200))
            waited += 1
            guard gen == g else { return }
        }

        // Canvas entrance
        withAnimation(.spring(response: 0.50, dampingFraction: 0.80)) {
            canvasScale = 1; canvasOpacity = 1
        }
        try? await Task.sleep(for: .seconds(0.34))
        guard gen == g else { return }

        // Date labels
        haptics.tick()
        withAnimation { dateEl = 1 }
        try? await Task.sleep(for: .seconds(0.30))
        guard gen == g else { return }

        // Upper row: photo (left) then sticker (right) — quick stagger
        haptics.tick()
        withAnimation { photoEl = 1 }
        try? await Task.sleep(for: .seconds(0.20))
        guard gen == g else { return }
        haptics.thunk()
        withAnimation { stickerEl = 1 }
        try? await Task.sleep(for: .seconds(0.32))
        guard gen == g else { return }

        // Lower row: lily (left) then puppy (right) — quick stagger
        haptics.tick()
        withAnimation { lilyEl = 1 }
        try? await Task.sleep(for: .seconds(0.20))
        guard gen == g else { return }
        haptics.thunk()
        withAnimation { puppyEl = 1 }
        try? await Task.sleep(for: .seconds(0.30))
        guard gen == g else { return }

        // Ransom "love"
        haptics.tick()
        withAnimation { ransomEl = 1 }
        try? await Task.sleep(for: .seconds(0.28))
        guard gen == g else { return }

        // Die-cut text — finale, stays forever
        haptics.thunk()
        withAnimation { diecutEl = 1 }
        // Done — composition holds. No fade, no reset.
    }
}

// MARK: - Ransom lettering

struct RansomLettering: View {
    let text: String
    var fontSize: CGFloat = 16

    private static let tiles: [(bg: Color, fg: Color)] = [
        (Color(hex: 0xC5B49A), Color(hex: 0x1A1A1A)),
        (Color(hex: 0x24445E), .white),
        (Color(hex: 0xA8C5D8), Color(hex: 0x1A1A1A)),
        (Color(hex: 0xD4A87A), Color(hex: 0x1A1A1A)),
        (Color(hex: 0xEEE4D8), Color(hex: 0x1A1A1A)),
        (Color(hex: 0x6B8FA8), .white),
    ]
    private static let rotations: [Double] = [-5, 4, -7, 3, -4, 6]
    private static let designs: [Font.Design] = [.serif, .rounded, .default, .serif, .monospaced, .rounded]

    var body: some View {
        HStack(spacing: fontSize * 0.14) {
            ForEach(Array(text.enumerated()), id: \.offset) { i, char in
                if char == " " {
                    Color.clear.frame(width: fontSize * 0.45)
                } else {
                    letterTile(char: char, index: i)
                }
            }
        }
    }

    private func letterTile(char: Character, index: Int) -> some View {
        let tile = Self.tiles[index % Self.tiles.count]
        let rot  = Self.rotations[index % Self.rotations.count]
        let dsn  = Self.designs[index % Self.designs.count]
        return Text(String(char).uppercased())
            .font(.system(size: fontSize * 0.92, weight: .bold, design: dsn))
            .foregroundStyle(tile.fg)
            .frame(width: fontSize * 1.28, height: fontSize * 1.28)
            .background(tile.bg, in: RoundedRectangle(cornerRadius: fontSize * 0.18))
            .rotationEffect(.degrees(rot))
    }
}

