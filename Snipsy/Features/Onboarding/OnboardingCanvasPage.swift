import SwiftUI

/// Page 1: the pitch. The memory page builds itself — a dated stamp
/// template filling with photos, stamps, die-cuts and hand lettering.
/// Animates once top → bottom then **stays** on the finished composition.
///
///   Left col (top → bottom): couple1 polaroid | lily stamp | ransom "love"
///   Right col (top → bottom): couple2 die-cut | puppy die-cut
///   Full-width bottom: die-cut "forever & always"
///
/// Every element is the app's own component — `CanvasBackgroundView`,
/// `PolaroidView`, `StampView`, `RansomText`, `DieCutText` — so the pitch
/// cannot drift from the product. Nothing here is a mock-up of a stamp.
struct OnboardingCanvasPage: View {
    let demo: OnboardingDemo
    let haptics: Haptics
    let isActive: Bool
    let screenSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var canvasScale: Double = 0.88
    @State private var canvasOpacity: Double = 0
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
                Text("SNIPSY")
                    .font(Theme.display(27))
                    .tracking(3)
                    .foregroundStyle(Theme.ink)
                Text("Photos pile up.\nNone of them get kept.")
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

    /// The real template the canvas editor puts under a memory:
    /// `StampTemplateBackground` — perforated stock, keylines, denomination
    /// furniture and the dated header, all of it the genuine `StampView`
    /// dressing. This used to be a powder-blue hex with a hand-drawn dot
    /// grid, a dashed `PerforatedRect` and two hand-placed date labels: a
    /// drawing of the product rather than the product.
    private static let template = CanvasDocument.Background.paper(.ink)
    // (If anything here ever needs the sheet's type colour, it is
    // `StampVariant.canvasInk` — do not re-type the hex.)

    private var canvasCard: some View {
        ZStack(alignment: .topLeading) {
            CanvasBackgroundView(background: Self.template, date: .now)
            canvasElements
        }
        .frame(width: cardWidth, height: cardHeight)
        .shadow(color: Theme.shadow.opacity(0.30), radius: 22, y: 11)
    }

    // MARK: Canvas elements — two-column, no overlaps

    @ViewBuilder
    private var canvasElements: some View {
        let w = cardWidth
        let h = cardHeight

        // ── Upper-left: couple1 in POLAROID mode ────────────────────────────
        // `PolaroidLayer` — what the canvas actually renders for a photo
        // layer set to `ImageTreatment.polaroid`. Not `PolaroidView` (that
        // is the standalone kept artifact, with its own caption and develop
        // animation) and not the `.polaroid` BACKGROUND (that is the page
        // stock you place things on). This is the layer mode, carrying its
        // own instant-photo stock, recess and shadow.
        if let photo = demo.canvasPhoto {
            PolaroidLayer(image: photo, width: w * 0.42)
                .rotationEffect(.degrees(-7))
                .scaleEffect(photoEl == 0 ? 0.25 : 1)
                .opacity(photoEl)
                .animation(.spring(response: 0.30, dampingFraction: 0.60), value: photoEl)
                .offset(x: w * 0.03, y: h * 0.085)
        }

        // ── Upper-right: couple2 die-cut ────────────────────────────────────
        // Occupies x[52%,95%]  y[7%,46%]
        if let couple = demo.sticker("couple2") {
            Image(uiImage: couple)
                .resizable().scaledToFit()
                .frame(width: w * 0.43)
                .rotationEffect(.degrees(6))
                .scaleEffect(stickerEl == 0 ? 0.25 : 1)
                .opacity(stickerEl)
                .animation(.spring(response: 0.30, dampingFraction: 0.56), value: stickerEl)
                .shadow(color: .black.opacity(0.36), radius: 7, y: 4)
                .offset(x: w * 0.52, y: h * 0.07)
        }

        // ── Lower-RIGHT: lily as a STAMP ────────────────────────────────────
        // A stamp prints the PHOTO in its picture area — `.classic`, which
        // the app defines as "the full crop fills the stamp frame". The die
        // cut belongs to a sticker, so no mask, box or anchor goes in here.
        // Occupies x[55%,85%]  y[45%,75%]
        if let lily = demo.subject("lily") {
            StampView(image: lily.photo,
                      style: .classic,
                      tint: lily.tint.color,
                      title: lily.title,
                      number: 1,
                      variant: .tinted)
                .frame(width: w * 0.30)
                .rotationEffect(.degrees(7))
                .scaleEffect(lilyEl == 0 ? 0.25 : 1)
                .opacity(lilyEl)
                .animation(.spring(response: 0.30, dampingFraction: 0.56), value: lilyEl)
                .shadow(color: .black.opacity(0.34), radius: 5, y: 3)
                .offset(x: w * 0.55, y: h * 0.45)
        }

        // ── Lower-LEFT: puppy die-cut ───────────────────────────────────────
        // Occupies x[3%,31%]  y[49%,75%]
        if let puppy = demo.sticker("puppy") {
            Image(uiImage: puppy)
                .resizable().scaledToFit()
                .frame(width: w * 0.28)
                .rotationEffect(.degrees(-10))
                .scaleEffect(puppyEl == 0 ? 0.25 : 1)
                .opacity(puppyEl)
                .animation(.spring(response: 0.30, dampingFraction: 0.54), value: puppyEl)
                .shadow(color: .black.opacity(0.34), radius: 5, y: 3)
                .offset(x: w * 0.03, y: h * 0.49)
        }

        // ── Below puppy: the puppy's NAME in ransom ─────────────────────────
        // It sits under the puppy, so it reads as a caption for it. Taken
        // from the sticker's own title rather than typed twice.
        // Occupies x[3%,31%]  y[76%,84%]
        RansomLettering(text: demo.subject("puppy")?.title ?? "Buddy",
                        fontSize: w * 0.062)
            .rotationEffect(.degrees(-4))
            .scaleEffect(ransomEl == 0 ? 0.40 : 1, anchor: .leading)
            .opacity(ransomEl)
            .animation(.spring(response: 0.30, dampingFraction: 0.62), value: ransomEl)
            .offset(x: w * 0.03, y: h * 0.76)

        // ── Caption band, right of the date: die-cut "forever & always" ─────
        // `.ink` prints its header LEFT-aligned at y = 1.20w, ending around
        // x = 0.34w. This sits on that same line, starting clear of it, so
        // the band reads as one row: date · day · the cut phrase.
        //
        // y is the TOP edge (the stack is .topLeading), so it is the header
        // centre less half the text's height: 1.20w − 0.04w = 1.16w = 0.884h.
        DieCutText(text: "forever & always", fontSize: w * 0.058,
                   ink: Color(hex: 0x1C3050))
            .scaleEffect(diecutEl == 0 ? 0.60 : 1)
            .opacity(diecutEl)
            .animation(.spring(response: 0.30, dampingFraction: 0.64), value: diecutEl)
            .offset(x: w * 0.42, y: h * 0.884)
    }

    // MARK: Helpers


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
        photoEl = 0; stickerEl = 0
        lilyEl = 0; puppyEl = 0; ransomEl = 0; diecutEl = 0
    }

    private func showAll() {
        canvasScale = 1; canvasOpacity = 1
        photoEl = 1; stickerEl = 1
        lilyEl = 1; puppyEl = 1; ransomEl = 1; diecutEl = 1
    }

    /// Wait for Vision to finish processing all subjects (up to ~6 s),
    /// then build up the canvas top → bottom.
    /// Resolve the moment this one subject exists, rather than when the
    /// whole batch does. Capped so a failed lift can't stall the page.
    private func waitFor(_ key: String, _ g: Int) async {
        var waited = 0
        while demo.subject(key) == nil && waited < 40 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 1
            guard gen == g else { return }
        }
    }

    /// Build the page top → bottom.
    ///
    /// Nothing global is awaited up front. This used to open by polling
    /// `demo.subjects.count < 4` every 200 ms for up to six seconds — so the
    /// very first screen of the app sat empty until the *slowest* Vision
    /// lift finished, on the one launch where Vision is coldest. Now the
    /// paper and the polaroid (bundle-loaded, no Vision) land immediately
    /// and each die-cut arrives as its own subject is ready.
    private func animate(_ g: Int) async {
        withAnimation(.spring(response: 0.40, dampingFraction: 0.82)) {
            canvasScale = 1; canvasOpacity = 1
        }
        try? await Task.sleep(for: .seconds(0.16))
        guard gen == g else { return }

        // Upper-left polaroid — straight from the bundle, never blocked.
        haptics.tick()
        withAnimation { photoEl = 1 }
        try? await Task.sleep(for: .seconds(0.10))
        guard gen == g else { return }

        await waitFor("couple2", g)
        guard gen == g else { return }
        haptics.thunk()
        withAnimation { stickerEl = 1 }
        try? await Task.sleep(for: .seconds(0.10))
        guard gen == g else { return }

        await waitFor("lily", g)
        guard gen == g else { return }
        haptics.tick()
        withAnimation { lilyEl = 1 }
        try? await Task.sleep(for: .seconds(0.10))
        guard gen == g else { return }

        await waitFor("puppy", g)
        guard gen == g else { return }
        haptics.thunk()
        withAnimation { puppyEl = 1 }
        try? await Task.sleep(for: .seconds(0.10))
        guard gen == g else { return }

        // The puppy's name, captioning it.
        haptics.tick()
        withAnimation { ransomEl = 1 }
        try? await Task.sleep(for: .seconds(0.12))
        guard gen == g else { return }

        // Die-cut text — finale, stays forever.
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

