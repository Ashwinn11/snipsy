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
    let resolver: (String) -> UIImage?

    var body: some View {
        switch content {
        case .image(let file, let cutoutFile, let showCutout):
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
            if style.dieCut {
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
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .shadow(color: Theme.shadow.opacity(0.20),
                            radius: canvasWidth * 0.008, y: canvasWidth * 0.004)
                    .frame(width: scale * canvasWidth)
            }
        case .doodle(let id):
            DoodleCatalog.view(id: id, width: scale * canvasWidth)
        }
    }

    /// Text sizes by font, not frame — pinch drives the type size.
    static func fontSize(scale: CGFloat, canvasWidth: CGFloat) -> CGFloat {
        max(10, scale * canvasWidth * 0.5)
    }
}
