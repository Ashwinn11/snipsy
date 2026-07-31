import SwiftUI

/// Bundled decoration registry. Ids are namespaced so the persisted model
/// never changes when art upgrades: `builtin.*` are code-drawn, `asset.*`
/// is the illustrated sticker sheet.
enum DoodleCatalog {

    static let all: [String] = [
        "doodle.heart", "doodle.sparkle", "doodle.arrow",
        "doodle.loop", "doodle.squiggle", "doodle.burst",
        "washi.rose", "washi.sage", "washi.sun",
        "tag.scallop", "frame.dash",
    ] + assetIDs

    /// Illustrated sticker sheet — licensed art (Freepik Free License;
    /// see Settings → About for the required credit line).
    static let assetIDs: [String] = assetAspect.keys.sorted().map { "asset.\($0)" }

    /// Each asset's true height/width, measured off the source art so
    /// nothing renders squished.
    private static let assetAspect: [String: CGFloat] = [
        "broken_heart": 0.904, "camera_heart": 0.651, "champagne_glass": 1.330,
        "chocolate_heart": 1.310, "cupid_bow_v1": 1.208, "cupid_bow_v2": 1.065,
        "diamond_gem": 0.937, "double_hearts": 0.788, "envelope_heart": 0.893,
        "gift_box": 1.408, "gift_heart": 0.986, "heart_arrow": 0.879,
        "heart_jar": 1.566, "heart_lollipop": 1.385, "heart_love_ribbon": 0.814,
        "heart_padlock": 1.239, "heart_ribbon_lilac": 0.844,
        "hearts_holding_hands": 0.466, "i_love_you_tag": 0.313,
        "ice_cream_hearts": 0.870, "kisses_tag": 0.441, "love_banner_heart": 0.683,
        "love_birds": 0.763, "mailbox_love": 1.060, "marry_me_tag": 0.353,
        "marry_me_toast": 1.199, "pink_bow": 1.224, "pink_flower": 0.995,
        "rose_flower": 2.038, "rose_heart": 1.219, "teddy_bear_heart_v1": 1.464,
        "teddy_bear_heart_v2": 1.254, "thought_bubble_heart": 0.726,
        "winged_heart_single": 0.529, "winged_hearts": 0.572,
        "butterfly_moth": 0.980, "candle_purple": 1.192, "cat_portrait": 1.038,
        "cozy_scarf": 0.839, "cozy_socks": 1.026, "daisy_pink": 0.935,
        "feel_cozy_text": 1.008, "floral_branch_line": 0.635,
        "flourish_divider": 0.266, "flower_red": 1.000, "gold_leaf": 0.944,
        "hanging_plant": 1.317, "heart_pink_wash": 1.306, "heather_branch": 2.002,
        "hello_script": 0.358, "kiss_x_pink": 0.942, "little_garden_book": 1.310,
        "monstera_pot": 1.173, "moon_gold": 1.020, "olive_branch": 1.108,
        "paint_swatch_blue": 0.949, "pink_berries_branch": 1.578,
        "rings_blue": 2.015, "rose_pink_watercolor": 0.960,
        "squiggle_teal": 2.894, "sunflower": 0.996, "swallow_bird": 0.989,
        "teacup_floral": 0.875, "teapot_polka": 0.789, "vintage_frame": 0.733,
        "washi_gray_triangle": 0.196, "washi_green_dot": 0.212,
        "washi_pink_heart": 0.318, "washi_red_dot": 0.565,
        "washi_yellow_stripe": 0.300, "yarn_knitting": 0.797,
        "apple_red": 1.184, "autumn_leaves_branch": 1.542, "bell_flower_pink": 0.754,
        "bow_polka_pink_soft": 0.764, "clover_sage": 1.061,
        "envelope_love_you_soft": 1.158, "flower_pink_small": 1.094,
        "flower_pot_striped": 1.487, "gift_box_polka_sage": 0.957,
        "gift_tag_heart_striped": 1.826, "heart_glasses": 0.479,
        "heart_gray_confetti": 1.151, "heart_lollipop_striped": 1.951,
        "heart_mint_solid": 0.899, "heart_padlock_sage": 1.048,
        "heart_pink_solid_soft": 0.838, "ice_cream_sundae": 0.970,
        "jam_jar": 1.162, "key_sage": 0.868, "leaf_petal_gold": 0.986,
        "mushroom_red": 1.411, "mushroom_small_pink": 0.739, "pinecone": 1.054,
        "sparkle_gold": 0.880, "strawberry_dipped": 1.133,
        "sunflower_cottage": 1.638, "teacup_heart_sage": 0.686,
        "teapot_floral": 1.165,
    ]

    /// Rendered height / width for a given doodle.
    static func aspect(id: String) -> CGFloat {
        if id.hasPrefix("washi.") { return 0.30 }
        if id.hasPrefix("asset.") {
            return assetAspect[String(id.dropFirst("asset.".count))] ?? 1
        }
        if id == "tag.scallop" { return 0.52 }
        if id == "doodle.squiggle" { return 0.32 }
        if id == "doodle.arrow" { return 0.72 }
        if id == "doodle.loop" { return 0.62 }
        if id == "doodle.heart" { return 0.92 }
        return 1
    }

    @ViewBuilder
    static func view(id: String, width: CGFloat) -> some View {
        switch id {
        case _ where id.hasPrefix("asset."):
            let name = String(id.dropFirst("asset.".count))
            Image("sticker_\(name)")
                .resizable()
                .scaledToFit()
                .frame(width: width)
        case "doodle.heart":
            DoodleHeart().frame(width: width, height: width * 0.92)
        case "doodle.sparkle":
            DoodleSparkles().frame(width: width, height: width)
        case "doodle.arrow":
            DoodleArrow().frame(width: width, height: width * 0.72)
        case "doodle.loop":
            DoodleLoop().frame(width: width, height: width * 0.62)
        case "doodle.squiggle":
            DoodleSquiggle().frame(width: width, height: width * 0.32)
        case "doodle.burst":
            DoodleBurst().frame(width: width, height: width)
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
            EmptyView()
        }
    }
}

/// One stroked pen path — the doodle voice: round caps, weight relative
/// to size, drawn in a unit-relative rect.
private struct StrokeDoodle: View {
    let color: Color
    let path: (CGRect) -> Path

    var body: some View {
        GeometryReader { geo in
            path(CGRect(origin: .zero, size: geo.size))
                .stroke(color, style: StrokeStyle(
                    lineWidth: max(2, geo.size.width * 0.055),
                    lineCap: .round, lineJoin: .round))
        }
    }
}

/// A hand-drawn open heart outline.
struct DoodleHeart: View {
    var body: some View {
        StrokeDoodle(color: Theme.postalRed) { rect in
            var p = Path()
            let w = rect.width, h = rect.height
            p.move(to: CGPoint(x: 0.5 * w, y: 0.9 * h))
            p.addCurve(to: CGPoint(x: 0.07 * w, y: 0.4 * h),
                       control1: CGPoint(x: 0.3 * w, y: 0.74 * h),
                       control2: CGPoint(x: 0.07 * w, y: 0.6 * h))
            p.addCurve(to: CGPoint(x: 0.5 * w, y: 0.26 * h),
                       control1: CGPoint(x: 0.07 * w, y: 0.16 * h),
                       control2: CGPoint(x: 0.38 * w, y: 0.1 * h))
            p.addCurve(to: CGPoint(x: 0.93 * w, y: 0.4 * h),
                       control1: CGPoint(x: 0.62 * w, y: 0.1 * h),
                       control2: CGPoint(x: 0.93 * w, y: 0.16 * h))
            p.addCurve(to: CGPoint(x: 0.53 * w, y: 0.88 * h),
                       control1: CGPoint(x: 0.93 * w, y: 0.6 * h),
                       control2: CGPoint(x: 0.72 * w, y: 0.74 * h))
            return p
        }
    }
}

/// A trio of four-point sparkles.
struct DoodleSparkles: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                SparkleShape().fill(Color(hex: 0xE3B84F))
                    .frame(width: 0.56 * w, height: 0.56 * w)
                    .position(x: 0.38 * w, y: 0.52 * w)
                SparkleShape().fill(Color(hex: 0xE8C97A))
                    .frame(width: 0.3 * w, height: 0.3 * w)
                    .position(x: 0.78 * w, y: 0.26 * w)
                SparkleShape().fill(Color(hex: 0xE8C97A))
                    .frame(width: 0.2 * w, height: 0.2 * w)
                    .position(x: 0.78 * w, y: 0.72 * w)
            }
        }
    }
}

/// Concave four-point star — the sparkle silhouette.
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: 0.5 * w, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: 0.5 * h),
                       control: CGPoint(x: 0.6 * w, y: 0.4 * h))
        p.addQuadCurve(to: CGPoint(x: 0.5 * w, y: h),
                       control: CGPoint(x: 0.6 * w, y: 0.6 * h))
        p.addQuadCurve(to: CGPoint(x: 0, y: 0.5 * h),
                       control: CGPoint(x: 0.4 * w, y: 0.6 * h))
        p.addQuadCurve(to: CGPoint(x: 0.5 * w, y: 0),
                       control: CGPoint(x: 0.4 * w, y: 0.4 * h))
        p.closeSubpath()
        return p
    }
}

/// A swooping hand-drawn arrow.
struct DoodleArrow: View {
    var body: some View {
        StrokeDoodle(color: Theme.stampInk) { rect in
            var p = Path()
            let w = rect.width, h = rect.height
            p.move(to: CGPoint(x: 0.06 * w, y: 0.85 * h))
            p.addCurve(to: CGPoint(x: 0.9 * w, y: 0.2 * h),
                       control1: CGPoint(x: 0.5 * w, y: 1.05 * h),
                       control2: CGPoint(x: 0.55 * w, y: 0.55 * h))
            p.move(to: CGPoint(x: 0.67 * w, y: 0.27 * h))
            p.addLine(to: CGPoint(x: 0.9 * w, y: 0.2 * h))
            p.addLine(to: CGPoint(x: 0.83 * w, y: 0.43 * h))
            return p
        }
    }
}

/// The circled-in-pen loop — one lap with a crossing overshoot.
struct DoodleLoop: View {
    var body: some View {
        StrokeDoodle(color: Color(hex: 0x274896)) { rect in
            var p = Path()
            let w = rect.width, h = rect.height
            p.move(to: CGPoint(x: 0.58 * w, y: 0.12 * h))
            p.addCurve(to: CGPoint(x: 0.42 * w, y: 0.88 * h),
                       control1: CGPoint(x: 0.06 * w, y: 0.06 * h),
                       control2: CGPoint(x: 0, y: 0.9 * h))
            p.addCurve(to: CGPoint(x: 0.64 * w, y: 0.18 * h),
                       control1: CGPoint(x: w, y: 0.86 * h),
                       control2: CGPoint(x: 0.98 * w, y: 0.1 * h))
            return p
        }
    }
}

/// A wavy underline stroke.
struct DoodleSquiggle: View {
    var body: some View {
        StrokeDoodle(color: Theme.postalRed) { rect in
            var p = Path()
            let w = rect.width, h = rect.height
            p.move(to: CGPoint(x: 0.03 * w, y: 0.55 * h))
            var up = true
            var x: CGFloat = 0.03
            while x < 0.9 {
                let next = x + 0.155
                p.addQuadCurve(
                    to: CGPoint(x: next * w, y: 0.5 * h),
                    control: CGPoint(x: (x + next) / 2 * w,
                                     y: (up ? 0.02 : 0.98) * h))
                up.toggle()
                x = next
            }
            return p
        }
    }
}

/// Radiating emphasis dashes — the "look here" burst.
struct DoodleBurst: View {
    var body: some View {
        StrokeDoodle(color: Theme.stampInk) { rect in
            var p = Path()
            let w = rect.width, h = rect.height
            let center = CGPoint(x: 0.5 * w, y: 0.78 * h)
            for degrees in stride(from: -150.0, through: -30.0, by: 30.0) {
                let a = degrees * .pi / 180
                let dir = CGPoint(x: cos(a), y: sin(a))
                p.move(to: CGPoint(x: center.x + dir.x * 0.34 * w,
                                   y: center.y + dir.y * 0.34 * w))
                p.addLine(to: CGPoint(x: center.x + dir.x * 0.62 * w,
                                      y: center.y + dir.y * 0.62 * w))
            }
            return p
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
