import SwiftUI

/// Pure composite of a canvas document: background stock + every layer at
/// its committed transform. The editor stacks interaction on top of the
/// same pieces; the save flatten renders THIS view — one renderer, zero
/// drift between what was edited and what ships.
struct CanvasStageView: View {
    let doc: CanvasDocument
    let resolver: (String) -> UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                CanvasBackgroundView(background: doc.background, date: doc.date)
                ForEach(doc.layers) { layer in
                    CanvasLayerContent(content: layer.content,
                                       canvasWidth: geo.size.width,
                                       scale: layer.transform.scale,
                                       dieCut: layer.dieCut,
                                       resolver: resolver)
                        .rotationEffect(.radians(layer.transform.rotation))
                        .position(x: layer.transform.x * geo.size.width,
                                  y: layer.transform.y * geo.size.height)
                }
            }
        }
        .aspectRatio(1 / doc.aspect, contentMode: .fit)
    }
}

/// The stock a composition sits on. Grain shaders live HERE only — layers
/// (which may carry a live TextField) never sit under a shader modifier.
struct CanvasBackgroundView: View {
    let background: CanvasDocument.Background
    /// The memory's date, printed as the stamp template's header. `nil`
    /// still renders the frame (template gallery thumbnails) without the date.
    var date: Date? = nil

    var body: some View {
        switch background {
        case .paper(let variant):
            StampTemplateBackground(variant: variant, date: date)
        case .polaroid:
            PolaroidStock(showsRecess: true)
                .overlay {
                    if let date {
                        GeometryReader { geo in
                            PolaroidTemplateDate(date: date, width: geo.size.width)
                        }
                        .allowsHitTesting(false)
                    }
                }
        case .card:
            CardStock()
                .overlay {
                    if let date {
                        GeometryReader { geo in
                            CardTemplateDate(date: date, width: geo.size.width)
                        }
                        .allowsHitTesting(false)
                    }
                }
        case .texture(let kind):
            // No date chrome — a plain stock is just a surface, not a
            // dated collectible.
            TextureBackground(kind: kind)
        }
    }
}

/// A plain page stock — solid color or a light procedural pattern, no
/// collectible furniture. Grain shaders reuse the same paper/fine grain
/// the stamp and card stocks already wear, just tuned per texture.
struct TextureBackground: View {
    let kind: CanvasTexture

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            base
                .shadow(color: Theme.shadow.opacity(0.22), radius: 0.03 * w, y: 0.015 * w)
        }
        .aspectRatio(1 / 1.30, contentMode: .fit)
    }

    @ViewBuilder
    private var base: some View {
        switch kind {
        case .parchment:
            Rectangle().fill(Color(hex: 0xF6EEDF))
                .colorEffect(ShaderLibrary.paperGrain(.float(0.41), .float(0.32)))
        case .watercolorBloom:
            WatercolorBloomTexture()
        case .coastalWash:
            CoastalWashTexture()
        case .twine:
            TwineTexture()
        case .postmark:
            PostmarkTexture()
        case .slate:
            // Charcoal-blue, not near-black — the default dark-ink text
            // layer stays legible without forcing a color switch.
            Rectangle().fill(Color(hex: 0x3B4452))
                .colorEffect(ShaderLibrary.fineGrain(.float(0.05)))
        case .sweetheartCheck:
            SweetheartCheckTexture()
        case .fadedBloom:
            FadedBloomTexture()
        }
    }
}

/// A tiny deterministic LCG — stable scatter jitter across renders (the
/// same trick a page-theme "wallpaper" needs anywhere it's drawn).
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func unit() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
    mutating func jitter(_ magnitude: CGFloat) -> CGFloat { (unit() - 0.5) * 2 * magnitude }
}

/// Soft diffused blush/lavender watercolor wash — the single most-loved
/// junk-journal background motif, and genuinely a decorating surface
/// rather than a writing-lined one.
private struct WatercolorBloomTexture: View {
    var body: some View {
        Rectangle().fill(Color(hex: 0xFBF6F1))
            .overlay {
                Canvas { ctx, size in
                    let blooms: [(CGPoint, CGFloat, Color)] = [
                        (CGPoint(x: 0.18, y: 0.22), 0.62, Color(hex: 0xE3AEC2)),
                        (CGPoint(x: 0.82, y: 0.16), 0.5, Color(hex: 0xC9B7E0)),
                        (CGPoint(x: 0.72, y: 0.78), 0.68, Color(hex: 0xEBC79A)),
                        (CGPoint(x: 0.15, y: 0.82), 0.48, Color(hex: 0xB7CBE0)),
                    ]
                    for (unit, radiusFrac, color) in blooms {
                        let center = CGPoint(x: unit.x * size.width, y: unit.y * size.height)
                        let r = radiusFrac * size.width * 0.5
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                   width: r * 2, height: r * 2)),
                            with: .radialGradient(
                                Gradient(colors: [color.opacity(0.32), color.opacity(0)]),
                                center: center, startRadius: 0, endRadius: r))
                    }
                }
                .blur(radius: 18)
            }
            .colorEffect(ShaderLibrary.paperGrain(.float(0.27), .float(0.16)))
    }
}

/// Sun-washed dusty blue-to-sand gradient — the coastal stock.
private struct CoastalWashTexture: View {
    var body: some View {
        LinearGradient(
            colors: [Color(hex: 0xAFC4CE), Color(hex: 0xDCD3BE)],
            startPoint: .top, endPoint: .bottom)
            .colorEffect(ShaderLibrary.paperGrain(.float(0.5), .float(0.22)))
    }
}

/// Parcel brown with a whisper of crosshatched string — the wrapped-parcel
/// stock, not a generic craft kraft sheet.
private struct TwineTexture: View {
    var body: some View {
        // Lighter, less saturated than a craft-store kraft sheet — dark
        // ink text and colored decorations both keep good contrast on it.
        Rectangle().fill(Color(hex: 0xDEC49B))
            .colorEffect(ShaderLibrary.paperGrain(.float(0.18), .float(0.34)))
            .overlay {
                Canvas { ctx, size in
                    let step = size.width * 0.1
                    let tint = Color(hex: 0x8F6B3E).opacity(0.14)
                    var path = Path()
                    var x = -size.height
                    while x < size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                        x += step
                    }
                    ctx.stroke(path, with: .color(tint), lineWidth: 1)
                }
            }
    }
}

/// Cream scattered with faint cancellation-mark rings — Snipsy's own motif,
/// echoing the perforated stamp shape used throughout the app.
private struct PostmarkTexture: View {
    var body: some View {
        Rectangle().fill(Color(hex: 0xF5EEE3))
            .overlay {
                Canvas { ctx, size in
                    var rng = SeededRandom(seed: 7)
                    // Sparse — a few postmarks scattered, not a repeating
                    // wallpaper competing with whatever gets decorated on top.
                    let spacing = size.width * 0.42
                    let cols = Int(size.width / spacing) + 2
                    let rows = Int(size.height / spacing) + 2
                    for row in 0..<rows {
                        for col in 0..<cols {
                            let stagger: CGFloat = row.isMultiple(of: 2) ? 0 : spacing / 2
                            let cx = CGFloat(col) * spacing + stagger + rng.jitter(spacing * 0.3)
                            let cy = CGFloat(row) * spacing + rng.jitter(spacing * 0.3)
                            let r = spacing * 0.16
                            let tint = Theme.ink.opacity(0.10)
                            ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r,
                                                              width: r * 2, height: r * 2)),
                                       with: .color(tint), lineWidth: 1)
                            var wave = Path()
                            wave.move(to: CGPoint(x: cx - r * 1.3, y: cy))
                            wave.addCurve(to: CGPoint(x: cx + r * 1.3, y: cy),
                                          control1: CGPoint(x: cx - r * 0.5, y: cy - r * 0.5),
                                          control2: CGPoint(x: cx + r * 0.5, y: cy + r * 0.5))
                            ctx.stroke(wave, with: .color(tint), lineWidth: 1)
                        }
                    }
                }
            }
    }
}

/// A two-tone woven check — the coquette stock, matching the app's own
/// "Sweetheart" edition family rather than a generic picnic-blanket name.
private struct SweetheartCheckTexture: View {
    var body: some View {
        Rectangle().fill(Color(hex: 0xFBF3F5))
            .overlay {
                Canvas { ctx, size in
                    let step = size.width * 0.052
                    let tint = Color(hex: 0xE7A9BB)
                    var x: CGFloat = 0
                    var i = 0
                    while x < size.width {
                        if i % 2 == 0 {
                            ctx.fill(Path(CGRect(x: x, y: 0, width: step, height: size.height)),
                                     with: .color(tint.opacity(0.35)))
                        }
                        x += step
                        i += 1
                    }
                    var y: CGFloat = 0
                    i = 0
                    while y < size.height {
                        if i % 2 == 0 {
                            ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: step)),
                                     with: .color(tint.opacity(0.35)))
                        }
                        y += step
                        i += 1
                    }
                }
            }
    }
}

/// Sage wash scattered with pressed petals and leaves — a keepsake page,
/// not a vague "vintage" label.
private struct FadedBloomTexture: View {
    var body: some View {
        Rectangle().fill(Color(hex: 0xEDF0E4))
            .colorEffect(ShaderLibrary.paperGrain(.float(0.55), .float(0.22)))
            .overlay {
                Canvas { ctx, size in
                    var rng = SeededRandom(seed: 13)
                    // Sparse scatter — pressed petals here and there, not a
                    // repeating print that fights with whatever's decorated on top.
                    let spacing = size.width * 0.36
                    let cols = Int(size.width / spacing) + 2
                    let rows = Int(size.height / spacing) + 2
                    let petal = Color(hex: 0xC98FA0).opacity(0.3)
                    let leaf = Color(hex: 0x7C9468).opacity(0.28)
                    for row in 0..<rows {
                        for col in 0..<cols {
                            let stagger: CGFloat = row.isMultiple(of: 2) ? 0 : spacing / 2
                            let cx = CGFloat(col) * spacing + stagger + rng.jitter(spacing * 0.35)
                            let cy = CGFloat(row) * spacing + rng.jitter(spacing * 0.35)
                            let side = spacing * (0.14 + rng.unit() * 0.1)
                            let isLeaf = rng.unit() > 0.55
                            let rotation = Angle.degrees(Double(rng.unit()) * 360)
                            var resolved = ctx.resolve(
                                Image(systemName: isLeaf ? "leaf.fill" : "circle.fill"))
                            resolved.shading = .color(isLeaf ? leaf : petal)
                            ctx.drawLayer { layer in
                                layer.translateBy(x: cx, y: cy)
                                layer.rotate(by: rotation)
                                layer.draw(resolved, in: CGRect(x: -side/2, y: -side/2,
                                                                width: side, height: side))
                            }
                        }
                    }
                }
            }
    }
}

/// A stamp template as a canvas background: the edition's full dressed frame
/// (perforated paper, keylines, chevrons, denomination motifs — the real
/// `StampView` furniture, minus the caption) with a dated header printed in
/// the top margin. The user drops photos, text and stickers on top; the
/// flatten renders this identically so the kept artifact bakes in the frame.
struct StampTemplateBackground: View {
    let variant: StampVariant
    /// nil → no date printed (gallery thumbnail).
    var date: Date? = nil

    var body: some View {
        // Empty dressed stamp — paper + edition furniture, no photo/caption.
        StampView(image: nil, style: .classic, tint: variant.canvasPaper,
                  title: "", number: 0, variant: variant,
                  showCaption: false, templateMode: true)
            .overlay {
                if let date {
                    GeometryReader { geo in
                        StampTemplateHeader(date: date, ink: variant.canvasInk,
                                            width: geo.size.width, variant: variant)
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

/// The memory's date printed the way its edition would print it — each
/// variant sets its own voice, alignment and height within the band, so no
/// two templates date-stamp alike.
///
/// It always prints in the CAPTION BAND (1.1375w → 1.3125w). That is the
/// only clear real estate: the picture area is where the user's photos land
/// (they'd cover anything under them), the perforation bites 0.032w off
/// every edge, and airmail's chevron ring occupies 0.038w–0.066w of the top
/// margin — there is no top strip wide enough to set type in.
struct StampTemplateHeader: View {
    let date: Date
    let ink: Color
    let width: CGFloat
    var variant: StampVariant = .tinted

    /// Stamp geometry, mirrored from `StampView.contentRect`.
    private var w: CGFloat { width }
    private var sheetH: CGFloat { 1.3125 * width }
    /// Vertical center of the caption band under the picture frame.
    private var bandY: CGFloat { 1.225 * width }
    /// Center of the bar-captioned editions' denomination / duty bar,
    /// matching `StampView.captionBarStock`.
    private var barY: CGFloat { 1.205 * width }

    private var day: String { Self.day.string(from: date).uppercased() }
    private var weekday: String { Self.weekday.string(from: date).uppercased() }

    var body: some View {
        ZStack(alignment: .topLeading) {
            slot
        }
        .frame(width: w, height: sheetH, alignment: .topLeading)
    }

    @ViewBuilder
    private var slot: some View {
        switch variant {

        // Bleed prints nothing on its plate — retired from canvas paper, so
        // this only exists to keep the switch total.
        case .bleed:
            EmptyView()

        // Classic postal line: № side gets the date, the far side the day.
        case .tinted:
            HStack(spacing: 0) {
                Text(day)
                Spacer(minLength: 0)
                Text(weekday)
            }
            .font(Theme.stampEngraved(0.05 * w))
            .kerning(0.05 * w * 0.1)
            .foregroundStyle(ink.opacity(0.82))
            .padding(.horizontal, 0.085 * w)
            .frame(width: w)
            .position(x: 0.5 * w, y: bandY)

        // Cameo plaque: the date engraved between two hairlines, day beneath.
        case .ivory:
            VStack(spacing: 0.012 * w) {
                HStack(spacing: 0.03 * w) {
                    rule(0.14 * w)
                    Text(day)
                        .font(Theme.stampEngraved(0.052 * w))
                        .kerning(0.052 * w * 0.14)
                    rule(0.14 * w)
                }
                Text(weekday)
                    .font(.system(size: 0.028 * w, weight: .regular, design: .serif))
                    .kerning(0.028 * w * 0.4)
            }
            .foregroundStyle(ink.opacity(0.8))
            .position(x: 0.5 * w, y: bandY)

        // Poster: type set large and low-contrast, hanging off the left. The
        // scrim reaches down to 1.32w, so this rides higher than the rest.
        case .ink:
            VStack(alignment: .leading, spacing: -0.006 * w) {
                Text(day)
                    .font(.system(size: 0.072 * w, weight: .bold).width(.condensed))
                Text(weekday)
                    .font(.system(size: 0.026 * w, weight: .light).width(.expanded))
                    .kerning(0.026 * w * 0.3)
                    .opacity(0.75)
            }
            .foregroundStyle(ink.opacity(0.9))
            .frame(width: 0.83 * w, alignment: .leading)
            .position(x: 0.5 * w, y: 1.20 * w)

        // Par avion: the postal line in the edition's two inks.
        case .airmail:
            HStack(spacing: 0.022 * w) {
                Text(day).foregroundStyle(Color(hex: 0x274896))
                Text("·").foregroundStyle(Color(hex: 0x274896).opacity(0.5))
                Text(weekday).foregroundStyle(Theme.postalRed.opacity(0.9))
            }
            .font(.system(size: 0.036 * w, weight: .semibold).width(.condensed))
            .kerning(0.036 * w * 0.22)
            .position(x: 0.5 * w, y: bandY)

        // Reversed out of the denomination bar the edition already prints.
        case .commemorative:
            HStack(spacing: 0) {
                Text(day)
                Spacer(minLength: 0.03 * w)
                Text(weekday)
            }
            .font(.system(size: 0.038 * w, weight: .semibold).width(.condensed))
            .kerning(0.038 * w * 0.16)
            .foregroundStyle(Color(hex: 0xFCEDE4))
            .padding(.horizontal, 0.045 * w)
            .frame(width: 0.85 * w)
            .position(x: 0.5 * w, y: barY)

        // Edition plate: wide-kerned caps between foil asterisks.
        case .foil:
            HStack(spacing: 0.026 * w) {
                Text("✦").opacity(0.7)
                Text(day)
                Text("✦").opacity(0.7)
                Text(weekday)
                Text("✦").opacity(0.7)
            }
            .font(.system(size: 0.034 * w, weight: .semibold).width(.condensed))
            .kerning(0.034 * w * 0.3)
            .foregroundStyle(Color(hex: 0xFBEFC4))
            .shadow(color: Color(red: 0.24, green: 0.16, blue: 0.06).opacity(0.6),
                    radius: 1, y: 1)
            .position(x: 0.5 * w, y: bandY)

        // Struck into the duty bar, in the edition's monospace voice.
        case .revenue:
            HStack(spacing: 0) {
                Text(day)
                Spacer(minLength: 0.03 * w)
                Text(weekday)
            }
            .font(.system(size: 0.028 * w, design: .monospaced))
            .foregroundStyle(Color(hex: 0xB9C6A6))
            .padding(.horizontal, 0.045 * w)
            .frame(width: 0.85 * w)
            .position(x: 0.5 * w, y: barY)

        // Definitive series: the day tracked small over the engraved date.
        case .botanical:
            VStack(spacing: 0.004 * w) {
                Text(weekday)
                    .font(.system(size: 0.026 * w, weight: .semibold, design: .serif))
                    .kerning(0.026 * w * 0.5)
                    .opacity(0.7)
                Text(day)
                    .font(Theme.stampEngraved(0.056 * w))
            }
            .foregroundStyle(ink.opacity(0.88))
            .position(x: 0.5 * w, y: bandY)

        // After dark: the date glows, set hard right under the neon keyline.
        case .night:
            HStack(spacing: 0.02 * w) {
                Text(day)
                Text(weekday).opacity(0.7)
            }
            .font(.system(size: 0.034 * w, weight: .semibold).width(.condensed))
            .kerning(0.034 * w * 0.24)
            .foregroundStyle(Color(hex: 0x6FE9FF))
            .shadow(color: Color(hex: 0x6FE9FF).opacity(0.8), radius: 0.02 * w)
            .frame(width: 0.83 * w, alignment: .trailing)
            .position(x: 0.5 * w, y: bandY)

        // Keepsake: a hand-written line with a heart between.
        case .sweetheart:
            HStack(spacing: 0.018 * w) {
                Text(Self.dayMixed.string(from: date))
                Text("♥").font(.system(size: 0.034 * w))
                    .foregroundStyle(Theme.postalRed.opacity(0.75))
                Text(Self.weekdayMixed.string(from: date))
            }
            .font(Theme.handwritten(0.058 * w))
            .foregroundStyle(Color(hex: 0x7A3A3C).opacity(0.9))
            .position(x: 0.5 * w, y: bandY)
        }
    }

    private func rule(_ length: CGFloat) -> some View {
        Rectangle()
            .fill(ink.opacity(0.4))
            .frame(width: length, height: 1)
    }

    private static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
    private static let dayMixed: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static let weekdayMixed: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
}

/// Pen on the instant-photo band — where a polaroid's caption always goes.
struct PolaroidTemplateDate: View {
    let date: Date
    let width: CGFloat

    var body: some View {
        let w = width
        HStack(spacing: 0.02 * w) {
            Text(Self.day.string(from: date))
            Text("·").opacity(0.5)
            Text(Self.weekday.string(from: date))
        }
        .font(Theme.handwritten(0.062 * w))
        .foregroundStyle(Theme.stampInk.opacity(0.7))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        // The band runs 0.95w → 1.22w; sit in the middle of it.
        .position(x: 0.5 * w, y: 1.085 * w)
        .frame(width: w, height: PolaroidView.aspect * w, alignment: .topLeading)
    }

    private static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
}

/// Engraved on the scrapbook card's caption line.
struct CardTemplateDate: View {
    let date: Date
    let width: CGFloat

    var body: some View {
        let w = width
        VStack(spacing: 0.012 * w) {
            Text(Self.day.string(from: date).uppercased())
                .font(Theme.stampEngraved(0.052 * w))
                .kerning(0.052 * w * 0.13)
                .foregroundStyle(Theme.stampInk.opacity(0.82))
            Text(Self.weekday.string(from: date).uppercased())
                .font(.system(size: 0.028 * w, weight: .medium, design: .serif))
                .kerning(0.028 * w * 0.4)
                .foregroundStyle(Theme.stampInk.opacity(0.45))
        }
        .lineLimit(1)
        // The card's own caption line sits at 1.19w; the photo bottoms at
        // 1.11w, so this whole block clears it.
        .position(x: 0.5 * w, y: 1.205 * w)
        .frame(width: w, height: CardView.aspect * w, alignment: .topLeading)
    }

    private static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
}

extension CanvasDocument.Background {
    /// Where this stock prints its date, in unit coordinates of the stage.
    /// The editor hangs its tap-to-edit region here so the touch target
    /// always lands on the printed date.
    var dateSlot: CGRect {
        switch self {
        // Stamp caption band: 1.1375w → 1.3125w of a 1.3125w sheet.
        case .paper: CGRect(x: 0, y: 0.862, width: 1, height: 0.138)
        // Polaroid band: 0.95w → 1.22w of a 1.22w print.
        case .polaroid: CGRect(x: 0, y: 0.778, width: 1, height: 0.222)
        // Card: below the photo (1.11w) on a 1.30w card.
        case .card: CGRect(x: 0, y: 0.854, width: 1, height: 0.146)
        // A plain stock prints no date — nothing to hang a tap target on.
        case .texture: .zero
        }
    }
}

extension StampVariant {
    /// The edition's paper stock as a canvas background. `.tinted` has no
    /// captured photo to tint from, so it falls back to warm kraft.
    var canvasPaper: Color {
        switch self {
        case .tinted, .bleed: Color(hex: 0xC9B689)
        case .ivory: Color(hex: 0xB7A6D6)
        case .ink: Color(hex: 0x2A2621)
        case .airmail: Color(hex: 0xFCFBF6)
        case .commemorative: Color(hex: 0x8A6AA8)
        case .foil: Color(hex: 0x6E5A34)
        case .revenue: Color(hex: 0x2A8390)
        case .botanical: Color(hex: 0x6FA84F)
        case .night: Color(hex: 0x1B2740)
        case .sweetheart: Color(hex: 0xE39AA6)
        }
    }

    /// Header/footer ink for the stamp template — dark on light papers,
    /// warm cream on dark ones, so the postal furniture always reads.
    var canvasInk: Color {
        let ui = UIColor(canvasPaper)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luma = 0.299 * r + 0.587 * g + 0.114 * b
        return luma >= 0.55 ? Theme.stampInk : Color(hex: 0xF2EADB)
    }
}

/// One layer's pixels/glyphs at a given canvas width — no transform, no
/// interaction. Shared verbatim between the live editor and the flatten.
struct CanvasLayerContent: View {
    let content: LayerContent
    let canvasWidth: CGFloat
    let scale: CGFloat
    var dieCut: Bool = false
    let resolver: (String) -> UIImage?

    var body: some View {
        switch content {
        case .image(let file, let cutoutFile, let treatment):
            // Die-cut renders the lifted subject once Vision has produced it;
            // until then (or if no subject) it falls back to the plain photo.
            let dieCutReady = treatment == .dieCut && cutoutFile != nil
            let name = dieCutReady ? (cutoutFile ?? file) : file
            if let image = resolver(name) {
                let w = scale * canvasWidth
                let shadow = Theme.shadow.opacity(0.18)
                let r = canvasWidth * 0.008
                let y = canvasWidth * 0.004
                switch treatment {
                case .polaroid:
                    PolaroidLayer(image: image, width: w)
                case .outline:
                    DieCutContour(margin: max(3, canvasWidth * 0.012)) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: w)
                    }
                    .shadow(color: shadow, radius: r, y: y)
                case .dieCut where dieCutReady:
                    Image(uiImage: image).resizable().scaledToFit()
                        .shadow(color: shadow, radius: r, y: y)
                        .frame(width: w)
                case .plain, .dieCut:
                    // Plain photo (also the die-cut fallback before/without a lift).
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: canvasWidth * 0.012))
                        .shadow(color: shadow, radius: r, y: y)
                        .frame(width: w)
                }
            }
        case .text(let string, let style):
            let fontSize = Self.fontSize(scale: scale, canvasWidth: canvasWidth)
            if style.design == .ransom {
                // Ransom chips are already paper cutouts; the scissors add
                // one white cut around the whole assembled phrase.
                contoured(margin: 0.18 * fontSize) {
                    RansomText(text: string, fontSize: fontSize,
                               ink: style.color.color)
                }
            } else if dieCut {
                // Snug cut for canvas type — the stamp tag's 0.34 em halo
                // is out of proportion at layer sizes. The cut wears the
                // layer's own voice, not the chrome font.
                DieCutText(text: string, fontSize: fontSize,
                           ink: style.color.color, spread: 0.18,
                           font: style.font(size: fontSize))
                    .fixedSize()
            } else {
                Text(string)
                    .font(style.font(size: fontSize))
                    .foregroundStyle(style.color.color)
                    .multilineTextAlignment(.center)
                    .fixedSize()
            }
        case .sticker(let file):
            if let image = resolver(file) {
                contoured(margin: 0.05 * scale * canvasWidth) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: scale * canvasWidth)
                }
                .shadow(color: Theme.shadow.opacity(0.20),
                        radius: canvasWidth * 0.008, y: canvasWidth * 0.004)
            }
        case .doodle(let id):
            contoured(margin: 0.05 * scale * canvasWidth) {
                DoodleCatalog.view(id: id, width: scale * canvasWidth)
            }
        }
    }

    /// Wraps content in the white cut edge when the layer asks for it.
    @ViewBuilder
    private func contoured<V: View>(
        margin: CGFloat, @ViewBuilder _ view: @escaping () -> V
    ) -> some View {
        if dieCut {
            DieCutContour(margin: max(3, margin), content: view)
        } else {
            view()
        }
    }

    /// Text sizes by font, not frame — pinch drives the type size.
    static func fontSize(scale: CGFloat, canvasWidth: CGFloat) -> CGFloat {
        max(10, scale * canvasWidth * 0.5)
    }
}

/// A photo dropped as a small instant-photo: warm-white frame, thick lower
/// band, no caption. Mirrors PolaroidView's window geometry (aspect 1.22).
struct PolaroidLayer: View {
    let image: UIImage
    let width: CGFloat

    var body: some View {
        let w = width
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 0.02 * w)
                .fill(Color(hex: 0xFDFBF4))
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 0.88 * w, height: 0.89 * w)
                .clipped()
                .overlay(Rectangle().strokeBorder(Theme.shadow.opacity(0.10), lineWidth: 1))
                .offset(x: 0.06 * w, y: 0.06 * w)
        }
        .frame(width: w, height: 1.22 * w)
        .shadow(color: Theme.shadow.opacity(0.20), radius: 0.02 * w, y: 0.01 * w)
    }
}

/// Kidnapper-note lettering: every character clipped from a different
/// magazine — mismatched faces, flipped cases, each glyph on its own
/// paper chip, slightly crooked. Seeded per character so the editor and
/// the flatten cut identical notes.
struct RansomText: View {
    let text: String
    let fontSize: CGFloat
    var ink: Color = Theme.stampInk

    private static let chips: [Color] = [
        Color(hex: 0xF6EFE2),   // cream
        Color(hex: 0xE7DDC8),   // aged paper
        Color(hex: 0xC9B689),   // kraft
        Color(hex: 0xDBD7D0),   // newsprint
        Color(hex: 0xEAD9DD),   // rose wash
        Color(hex: 0xD9E0D2),   // sage wash
    ]

    var body: some View {
        HStack(spacing: fontSize * 0.08) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                if char == " " {
                    Color.clear.frame(width: fontSize * 0.3, height: 1)
                } else {
                    chip(char, seed: Self.seed(index: index, char: char))
                }
            }
        }
    }

    private func chip(_ char: Character, seed: UInt64) -> some View {
        func value(_ shift: UInt64, _ mod: Int) -> Int {
            Int((seed >> shift) % UInt64(mod))
        }
        let s = String(char)
        let flipped: String = s == s.uppercased() ? s.lowercased() : s.uppercased()
        let glyph: String = value(3, 3) == 0 ? flipped : s
        let rotation: Double = Double(value(16, 13)) - 6
        let lift: CGFloat = (CGFloat(value(24, 7)) - 3) * fontSize * 0.02
        let paper: Color = Self.chips[value(40, Self.chips.count)]

        return Text(glyph)
            .font(chipFont(value(8, 5)))
            .foregroundStyle(ink)
            .padding(.horizontal, fontSize * 0.10)
            .padding(.vertical, fontSize * 0.06)
            .background(
                RoundedRectangle(cornerRadius: fontSize * 0.07)
                    .fill(paper)
                    .shadow(color: Theme.shadow.opacity(0.25),
                            radius: fontSize * 0.03, y: fontSize * 0.02)
            )
            .rotationEffect(.degrees(rotation))
            .offset(y: lift)
    }

    private func chipFont(_ pick: Int) -> Font {
        switch pick {
        case 0: return .system(size: fontSize, weight: .black, design: .serif)
        case 1: return .system(size: fontSize * 0.94, weight: .heavy, design: .rounded)
        case 2: return .system(size: fontSize * 0.92, weight: .bold, design: .monospaced)
        case 3: return .system(size: fontSize, weight: .black).width(.condensed)
        default: return .system(size: fontSize * 0.96, weight: .bold,
                                design: .serif).italic()
        }
    }

    /// Stable per-character hash — position and glyph in, chaos out, the
    /// same chaos every render.
    private static func seed(index: Int, char: Character) -> UInt64 {
        var h: UInt64 = 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(index) &* 0xBF58_476D_1CE4_E5B9
        for scalar in char.unicodeScalars {
            h ^= UInt64(scalar.value) &* 0x94D0_49BB_1331_11EB
        }
        h = (h ^ (h >> 31)) &* 0xBF58_476D_1CE4_E5B9
        return h ^ (h >> 27)
    }
}

/// Any view wearing the sticker's white cut edge — the same blur +
/// threshold dilation as DieCutText, generalized. The contour hugs the
/// content's alpha silhouette, whatever it is: doodle strokes, torn tape,
/// emoji, a saved die-cut getting a second border.
struct DieCutContour<Content: View>: View {
    let margin: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background {
                Canvas { context, size in
                    context.addFilter(.alphaThreshold(min: 0.08, color: .white))
                    context.addFilter(.blur(radius: margin / 1.4))
                    context.drawLayer { layer in
                        if let symbol = context.resolveSymbol(id: 0) {
                            layer.draw(symbol, at: CGPoint(x: size.width / 2,
                                                           y: size.height / 2))
                        }
                    }
                } symbols: {
                    content().tag(0)
                }
                .padding(-margin * 2)
            }
    }
}
