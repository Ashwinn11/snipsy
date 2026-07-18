import SwiftUI

/// Bundled decoration registry. Ids are namespaced so the persisted model
/// never changes when art upgrades: `builtin.*` are code-drawn, `emoji.*`
/// are glyphs, `asset.*` is reserved for future catalog art.
enum DoodleCatalog {

    static let all: [String] = [
        "washi.rose", "washi.sage", "washi.sun",
        "tag.scallop", "frame.dash",
        "emoji.❤️", "emoji.✨", "emoji.⭐️", "emoji.🌸",
        "emoji.💌", "emoji.☁️", "emoji.🎞️", "emoji.🫶",
    ]

    /// Rendered height / width for a given doodle.
    static func aspect(id: String) -> CGFloat {
        if id.hasPrefix("washi.") { return 0.30 }
        if id == "tag.scallop" { return 0.52 }
        return 1
    }

    @ViewBuilder
    static func view(id: String, width: CGFloat) -> some View {
        switch id {
        case "washi.rose":
            WashiTape(base: Color(hex: 0xD98A94), stripe: Color(hex: 0xF3D3D7))
                .frame(width: width, height: width * 0.30)
        case "washi.sage":
            WashiTape(base: Color(hex: 0x9DB894), stripe: Color(hex: 0xDCE8D4))
                .frame(width: width, height: width * 0.30)
        case "washi.sun":
            WashiTape(base: Color(hex: 0xE3B84F), stripe: Color(hex: 0xF6E7B0))
                .frame(width: width, height: width * 0.30)
        case "tag.scallop":
            ScallopTag()
                .frame(width: width, height: width * 0.52)
        case "frame.dash":
            RoundedRectangle(cornerRadius: width * 0.06)
                .stroke(Theme.stampInk.opacity(0.65),
                        style: StrokeStyle(lineWidth: max(1.5, width * 0.014),
                                           dash: [width * 0.05, width * 0.035]))
                .frame(width: width, height: width)
        default:
            // emoji.<glyph>
            Text(String(id.dropFirst("emoji.".count)))
                .font(.system(size: width * 0.85))
                .frame(width: width, height: width)
        }
    }
}

/// A strip of translucent patterned tape — sticks over anything beneath.
struct WashiTape: View {
    let base: Color
    let stripe: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Rectangle().fill(base)
                Canvas { ctx, size in
                    let stripeW = size.height * 0.42
                    var x = -size.height
                    while x < size.width + size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: size.height))
                        p.addLine(to: CGPoint(x: x + size.height, y: 0))
                        p.addLine(to: CGPoint(x: x + size.height + stripeW, y: 0))
                        p.addLine(to: CGPoint(x: x + stripeW, y: size.height))
                        p.closeSubpath()
                        ctx.fill(p, with: .color(stripe.opacity(0.75)))
                        x += stripeW * 2.4
                    }
                }
            }
            .clipShape(TornEnds(bite: h * 0.16))
            .opacity(0.85)
            .shadow(color: Theme.shadow.opacity(0.12), radius: w * 0.01, y: w * 0.006)
        }
    }
}

/// Jagged left/right edges — the torn tape read.
struct TornEnds: Shape {
    var bite: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let teeth = 5
        let step = rect.height / CGFloat(teeth)
        p.move(to: CGPoint(x: bite, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - bite, y: rect.minY))
        for i in 0..<teeth {
            let y = rect.minY + CGFloat(i) * step
            p.addLine(to: CGPoint(x: i.isMultiple(of: 2) ? rect.maxX : rect.maxX - bite,
                                  y: y + step))
        }
        p.addLine(to: CGPoint(x: bite, y: rect.maxY))
        for i in 0..<teeth {
            let y = rect.maxY - CGFloat(i) * step
            p.addLine(to: CGPoint(x: i.isMultiple(of: 2) ? rect.minX : bite,
                                  y: y - step))
        }
        p.closeSubpath()
        return p
    }
}

/// A scalloped-edge paper tag with a punched hole.
struct ScallopTag: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            RoundedRectangle(cornerRadius: h * 0.24)
                .fill(Color(hex: 0xFBF5E8))
                .overlay(
                    RoundedRectangle(cornerRadius: h * 0.24)
                        .strokeBorder(Theme.stampInk.opacity(0.25),
                                      style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
                        .padding(h * 0.09)
                )
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(Theme.paperDeep)
                        .overlay(Circle().strokeBorder(
                            Theme.stampInk.opacity(0.3), lineWidth: 1))
                        .frame(width: h * 0.2, height: h * 0.2)
                        .padding(.leading, w * 0.06)
                }
                .shadow(color: Theme.shadow.opacity(0.15), radius: w * 0.012, y: w * 0.008)
        }
    }
}
