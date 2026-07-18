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
                CanvasBackgroundView(background: doc.background)
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

    var body: some View {
        switch background {
        case .paper(let variant):
            GeometryReader { geo in
                PerforatedRect()
                    .fill(variant.canvasPaper)
                    .colorEffect(ShaderLibrary.paperGrain(.float(0.62), .float(0.55)))
                    .shadow(color: Theme.shadow.opacity(0.30),
                            radius: 0.05 * geo.size.width, y: 0.024 * geo.size.width)
            }
            .aspectRatio(1 / 1.3125, contentMode: .fit)
        case .polaroid:
            PolaroidStock(showsRecess: true)
        case .card:
            CardStock()
        }
    }
}

extension StampVariant {
    /// The edition's paper stock as a canvas background. `.tinted` has no
    /// captured photo to tint from, so it falls back to warm kraft.
    var canvasPaper: Color {
        switch self {
        case .tinted: Color(hex: 0xC9B689)
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
        case .image(let file, let cutoutFile, let showCutout):
            // Photos cut through Vision (subject lift), not the contour —
            // layer.dieCut plays no part here.
            let name = showCutout ? (cutoutFile ?? file) : file
            if let image = resolver(name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(
                        cornerRadius: showCutout ? 0 : canvasWidth * 0.012))
                    .shadow(color: Theme.shadow.opacity(0.18),
                            radius: canvasWidth * 0.008, y: canvasWidth * 0.004)
                    .frame(width: scale * canvasWidth)
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
