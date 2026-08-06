import SwiftUI

/// The stamp itself — the app's hero artifact. One view renders every stage:
/// the raw capture landing from the viewfinder, the grain unmasking, the
/// dressed collectible in the album, and the flattened share render.
///
/// Geometry (relative to stamp width W; total height = 1.3125 W):
///   content rect: x 0.075W, y 0.075W, w 0.85W, h 1.0625W  (exactly 4:5, so
///   the viewfinder crop lands with zero cropping — pixel-continuous handoff)
///   caption line: centered at y ≈ 1.225W
struct StampView: View {

    struct Assembly {
        /// 0 → paper invisible (only content shows), 1 → fully dressed.
        var paper: Double = 1
        /// Caption letter-stagger progress.
        var caption: Double = 1
        /// 0 → sticker at its captured position, 1 → composed at center.
        var settle: Double = 1
        /// Die-cut punch: the white sticker outline pressed into the raw
        /// photo (0 → not cut yet, 1 → cut).
        var border: Double = 1
        /// The cut piece's flight to its composed frame (0 → the sheet
        /// stands at the photo's own position, 1 → flown). Separate from
        /// `border` so the press can strike in place — cut, shatter and
        /// flight are three clocks, and the sheet must never travel on
        /// the punch alone, still wearing its waste.
        var flight: Double = 0
        /// Post-cut photo presence: the plain (unshaded) raw layer under
        /// the wave layer. The reveal drives it complementary to `border`
        /// (one spring), so the overlay + plain photo always cover the
        /// subject through any crossfade. Inert pre-cut: the wave layer at
        /// progress 0 occludes it with identical pixels.
        var photoFade: Double = 0
        /// Die-press dip, swept 0→1 by the first cut only. sin(press·π)
        /// is 0 at both ends, so it parks harmlessly at 1 and switches
        /// never re-dip.
        var press: Double = 0
        /// The waste around the cut sticker (the raw photo). 1 → present,
        /// 0 → faded away, leaving only the sticker.
        var waste: Double = 1
        var content: ContentStage = .final

        enum ContentStage {
            /// The raw viewfinder crop with the die-cut sticker over it.
            /// With waste 0 this is pixel-identical to `.final`.
            case raw
            /// Final display image (sticker on paper / classic photo).
            case final
        }

        static let dressed = Assembly()
    }

    var image: UIImage?
    var style: Stamp.Style
    var tint: Color
    var title: String
    var number: Int
    var date: Date = .now
    var variant: StampVariant = .tinted
    /// Normalized subject box within the crop (sticker start frame).
    var stickerBox: CGRect? = nil
    /// Raw crop retained for the .raw stage.
    var rawCrop: UIImage? = nil
    /// Subject matte for the waste grain-dissolve (reveal only).
    var maskImage: UIImage? = nil
    /// Contour fraction where the sticker's name label anchors.
    var labelAnchor: CGFloat? = nil

    var assembly: Assembly = .dressed

    /// When false, the caption strip (№ / date / title) is omitted entirely —
    /// used to render the stamp as an empty dressed frame for the canvas
    /// template backgrounds (the memory maker prints its own dated header).
    var showCaption: Bool = true

    /// Renders the edition as an empty template for the memory canvas: the
    /// picture window prints as a bare well (there is no photo yet) and the
    /// bar-captioned editions keep their denomination/duty bar as blank
    /// stock. Without this, `image == nil` drops the picture plate and
    /// `showCaption == false` drops the bar — half of what makes those
    /// editions recognisable.
    var templateMode: Bool = false

    /// Set true where shimmer will ever run (reveal, detail); must not change
    /// during the view's lifetime.
    var holoEnabled: Bool = false
    var holoStrength: Double = 0
    var holoSweep: Double = 0.5
    var holoDir: CGPoint = CGPoint(x: 1, y: 0.35)

    /// Liquid poke (reveal only). `liquidEnabled` must be constant for the
    /// view's lifetime; center/time drive the ripple.
    var liquidEnabled: Bool = false
    var liquidCenter: CGPoint = .zero
    var liquidTime: Double = 10

    /// Paper stock per edition. Every sheet keeps clear tonal separation
    /// from the cream album page behind it.
    private var paperFill: Color {
        switch variant {
        case .tinted: tint
        case .ivory: Color(hex: 0xB7A6D6)
        case .ink: Color(hex: 0x2A2621)
        case .airmail: Color(hex: 0xFCFBF6)
        case .commemorative: Color(hex: 0x8A6AA8)
        case .foil: Color(hex: 0x6E5A34)
        case .revenue: Color(hex: 0x2A8390)
        case .botanical: Color(hex: 0x6FA84F)
        case .night: Color(hex: 0x1B2740)
        case .sweetheart: Color(hex: 0xE39AA6)
        case .bleed: tint
        }
    }

    /// Perceived lightness of the tinted paper — legacy pale tints keep
    /// dark ink; the new deep tints print cream.
    private var tintLuminance: Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(tint).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// Caption / motif ink per edition — the stamp's own printed ink,
    /// independent of the app theme, so stored artifacts never shift.
    private var markInk: Color {
        switch variant {
        case .tinted: tintLuminance < 0.62
            ? Color(red: 0.97, green: 0.95, blue: 0.90)
            : Theme.stampInk
        case .ivory, .airmail: Theme.stampInk
        case .ink: Color(hex: 0xEDE6D6)
        case .commemorative: Color(hex: 0xF4EEE1)
        case .foil: Color(hex: 0xFBEFC4)
        case .revenue: Color(hex: 0xECF4F3)
        case .botanical: Color(hex: 0x15331A)
        case .night: Color(hex: 0x8FEEFF)
        case .sweetheart: Color(hex: 0x7A3A3C)
        case .bleed: tintLuminance < 0.62
            ? Color(red: 0.97, green: 0.95, blue: 0.90)
            : Theme.stampInk
        }
    }

    /// № / date ink — sweetheart's meta stays neutral so the rose title
    /// carries the romance alone.
    private var metaInk: Color {
        variant == .sweetheart ? Theme.stampInk : markInk
    }

    var editableTitle: Binding<String>? = nil
    var titleFocused: FocusState<Bool>.Binding? = nil
    var onSubmitTitle: () -> Void = {}
    /// When set, the static caption is tappable (shows a rename affordance).
    var onTapCaption: (() -> Void)? = nil

    /// Plate proportions: height as a multiple of width. The one number the
    /// develop silhouette and the reveal's landing frame both have to agree
    /// on, so it is declared here rather than measured off the layout.
    static let aspect: CGFloat = 1.3125

    /// The plate inscribed in a capture crop: stamp-proportioned, centred,
    /// as large as fits.
    ///
    /// The 4:5 crop is taller than the plate is wide, so this trims ~2.4%
    /// off each side — exactly what `.bleed`'s `scaledToFill` crops away
    /// anyway. That equality is the point: the develop dissolve keeps this
    /// rect, the reveal lands its plate on it, and the same pixels sit in
    /// both, so the handoff has nothing to cover up.
    static func plateRect(inscribedIn r: CGRect) -> CGRect {
        var w = r.height / aspect
        var h = r.height
        if w > r.width { w = r.width; h = w * aspect }
        return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            stampBody(w)
        }
        .aspectRatio(1 / Self.aspect, contentMode: .fit)
    }

    // MARK: Layout

    private func contentRect(_ w: CGFloat) -> CGRect {
        CGRect(x: 0.075 * w, y: 0.075 * w, width: 0.85 * w, height: 1.0625 * w)
    }

    @ViewBuilder
    private func stampBody(_ w: CGFloat) -> some View {
        // `.bleed` has no plate, so it draws on its own minimal path — but
        // that path carries none of the die-cut composite (contentLayer,
        // hoistedWaste, stickerOverlay all live in `platedBody`). Once the
        // reveal started defaulting to `.bleed`, selecting the die cut left
        // the stage with nothing to draw: haptics fired, the option lit up,
        // and the stamp went blank. While a cut is in play, bleed borrows
        // the plated pipeline — its plate is invisible at `paper == 0`, so
        // only the photo, the waste and the sticker show.
        if variant == .bleed && !cutInPlay {
            bleedBody(w)
        } else {
            platedBody(w)
        }
    }

    /// The die-cut composite is on screen and must be rendered.
    private var cutInPlay: Bool {
        style == .cutout && assembly.content == .raw && assembly.border > 0.001
    }

    /// The photo **is** the stamp.
    ///
    /// Every other edition prints a picture onto a paper plate. This one has
    /// no plate at all: the photograph itself is cut to the perforated
    /// silhouette. Routing it through the normal paper→picture→dressing
    /// pipeline is what produced a stamp *template* with a photo sitting
    /// inside it — the plate showed as a coloured rim wherever the picture's
    /// edge fell short of the teeth. Nothing is printed over it and nothing
    /// sits behind it.
    @ViewBuilder
    private func bleedBody(_ w: CGFloat) -> some View {
        let h = 1.3125 * w
        Group {
            if let img = rawCrop ?? image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()
            } else {
                // Template with no capture yet — the bare plate is all there
                // is to show.
                Rectangle().fill(paperFill)
            }
        }
        .frame(width: w, height: h)
        .mask { PerforatedRect().frame(width: w, height: h) }
        // The silhouette casts the shadow, so it follows the teeth rather
        // than a rectangle.
        .shadow(color: Theme.shadow.opacity(0.30), radius: 0.05 * w, y: 0.024 * w)
        .shadow(color: Theme.shadow.opacity(0.16), radius: 0.009 * w, y: 0.005 * w)
        .opacity(assembly.paper)
        .scaleEffect(0.94 + 0.06 * assembly.paper)
        .modifier(HoloModifier(enabled: holoEnabled && editableTitle == nil,
                               strength: holoStrength,
                               sweep: holoSweep, dir: holoDir))
        .modifier(LiquidModifier(enabled: liquidEnabled && editableTitle == nil,
                                 center: liquidCenter,
                                 time: liquidTime))
        .frame(width: w, height: h, alignment: .topLeading)
    }

    @ViewBuilder
    private func platedBody(_ w: CGFloat) -> some View {
        // Bleed's picture is the entire plate. Using the inset `contentRect`
        // here would jump the photo's scale at the moment bleed hands over
        // to this path for a cut.
        let content = variant == .bleed
            ? CGRect(x: 0, y: 0, width: w, height: 1.3125 * w)
            : contentRect(w)

        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                // ── Paper ────────────────────────────────────────────
                paper(w)
                    .opacity(assembly.paper)
                    .scaleEffect(0.94 + 0.06 * assembly.paper)

                // ── Content ──────────────────────────────────────────
                contentLayer(w, content: content)

                // ── Edition dressing printed over the picture ────────
                dressing(w)
                    .opacity(assembly.paper)
                    .scaleEffect(0.94 + 0.06 * assembly.paper)
                    .allowsHitTesting(false)

                // ── Caption strip ────────────────────────────────────
                if showCaption && !variant.hidesCaption {
                    captionLayer(w)
                        .opacity(assembly.paper)
                        // Invisible in sticker form (paper 0.001) but still
                        // laid out — it must not catch rename taps there.
                        .allowsHitTesting(assembly.paper > 0.5)
                } else if templateMode, barCaptioned {
                    // The bar IS the edition's furniture; the memory canvas
                    // prints its own date into it.
                    captionBarStock(w)
                        .opacity(assembly.paper)
                        .allowsHitTesting(false)
                }
            }
            .compositingGroup()
            // Shader effects cannot rasterize platform-backed views: with
            // the rename TextField mounted they render as a yellow
            // prohibition placeholder. Drop them during editing — the
            // identity change is confined to the edit-mode boundary, where
            // nothing is in flight.
            .modifier(HoloModifier(enabled: holoEnabled && editableTitle == nil,
                                   strength: holoStrength,
                                   sweep: holoSweep, dir: holoDir))
            .modifier(LiquidModifier(enabled: liquidEnabled && editableTitle == nil,
                                     center: liquidCenter,
                                     time: liquidTime))

            // ── The first cut's shatter ──────────────────────────────
            // ABOVE the shader modifiers: those wrappers rasterize the
            // stamp at its own frame, so dust rendered beneath them clips
            // at the image's edge. Out here the grains own the window —
            // they stream across the screen and off its right side.
            hoistedWaste(w, content: content)
        }
    }

    /// The waste wave, hoisted out of the holo/liquid raster. Mounted only
    /// when a mask exists (constant for the view's lifetime); held at 0.001
    /// opacity until the wave's first tick so the un-poked duplicate never
    /// occludes the liquid-poke ripple, and culled once the shader is
    /// provably blank (waste < 0.03 — kept-pixel fade ends at progress
    /// 0.97, all waste dead by 0.903). Replicates the sheet's exact
    /// box→frame mapping and press dip so no state combination can show
    /// dust and sheet at two different scales.
    @ViewBuilder
    private func hoistedWaste(_ w: CGFloat, content: CGRect) -> some View {
        if assembly.content == .raw, maskImage != nil, let raw = rawCrop ?? image {
            let boxRect = wasteBox(content: content)
            let sheet = sheetTargetRect(w, content: content, box: boxRect)
            let sx = boxRect.width > 0 ? sheet.width / boxRect.width : 1
            let sy = boxRect.height > 0 ? sheet.height / boxRect.height : 1
            let waveLive = assembly.waste < 1 && assembly.waste >= 0.03

            rawView(raw, content: content)
                .layerEffect(
                    ShaderLibrary.grainDissolveWaste(
                        .float2(content.width, content.height),
                        .float2(content.minX, content.minY),
                        .image(Image(uiImage: maskImage ?? UIImage())),
                        .float4(boxRect.minX, boxRect.minY,
                                boxRect.width, boxRect.height),
                        .float(1 - assembly.waste),
                        .float(max(2.5, w * 0.011))
                    ),
                    // Room for the full flight: gust (≤~430) + a cell wide,
                    // rise (≤~170) + a cell tall. Paid only while the wave
                    // is live — the idle duplicate stays cheap.
                    maxSampleOffset: assembly.waste < 1
                        ? CGSize(width: 440, height: 240)
                        : CGSize(width: 8, height: 8)
                )
                .frame(width: w, height: 1.3125 * w, alignment: .topLeading)
                .scaleEffect(x: sx, y: sy, anchor: .topLeading)
                .offset(x: sheet.minX - boxRect.minX * sx,
                        y: sheet.minY - boxRect.minY * sy)
                .scaleEffect(1 - 0.018 * sin(min(1, max(0, assembly.press)) * .pi))
                .opacity(waveLive ? 1 : 0.001)
                .allowsHitTesting(false)
        }
    }

    // MARK: Paper

    @ViewBuilder
    private func paper(_ w: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            PerforatedRect()
                .fill(paperFill)
                .colorEffect(ShaderLibrary.paperGrain(.float(0.62), .float(0.55)))
                .shadow(color: Theme.shadow.opacity(0.30), radius: 0.05 * w, y: 0.024 * w)
                .shadow(color: Theme.shadow.opacity(0.16), radius: 0.009 * w, y: 0.005 * w)

            // Under-picture plates: mounted only for the variant that needs it
            switch variant {
            case .foil:
                // Foil — the gold plate the picture is set into.
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0xB8862F), Color(hex: 0xF6E7B0),
                                 Color(hex: 0xC9A24B), Color(hex: 0xF8EFCB),
                                 Color(hex: 0xA9791F)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 0.90 * w, height: 1.11 * w)
                    .offset(x: 0.05 * w, y: 0.05 * w)
            case .night:
                // Night — the aurora glow the picture floats on.
                RadialGradient(
                    colors: [Color(hex: 0x6FE9FF).opacity(0.45),
                             Color(hex: 0xB478FF).opacity(0.16), .clear],
                    center: UnitPoint(x: 0.5, y: 0.45),
                    startRadius: 0, endRadius: 0.62 * w
                )
                .frame(width: 0.96 * w, height: 1.17 * w)
                .offset(x: 0.02 * w, y: 0.02 * w)
                .blur(radius: 3)
            default:
                EmptyView()
            }
        }
    }

    // MARK: Edition dressing

    /// Everything an edition prints OVER the picture: keylines, bars, scrims, marks.
    /// Evaluated lazily per active variant to avoid mounting 10 overlapping view trees.
    @ViewBuilder
    private func dressing(_ w: CGFloat) -> some View {
        let content = contentRect(w)

        ZStack(alignment: .topLeading) {
            switch variant {
            case .bleed:
                // Nothing. No keyline, no rings, no bar — the photo is the
                // whole stamp, and any furniture would break the bleed.
                EmptyView()

            case .tinted:
                Rectangle()
                    .strokeBorder(Color(red: 0.97, green: 0.94, blue: 0.88).opacity(0.7),
                                  lineWidth: 1)
                    .frame(width: content.width, height: content.height)
                    .offset(x: content.minX, y: content.minY)
                if tintLuminance >= 0.62 {
                    Rectangle()
                        .strokeBorder(Theme.stampInk.opacity(0.34), lineWidth: 1)
                        .frame(width: content.width - 0.04 * w,
                               height: content.height - 0.04 * w)
                        .offset(x: content.minX + 0.02 * w, y: content.minY + 0.02 * w)
                }

            case .ivory:
                // Ivory — the engraved cameo: double oval ring + spandrel rosettes.
                Ellipse()
                    .strokeBorder(Theme.stampInk.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 0.70 * w, height: 0.90 * w)
                    .offset(x: 0.15 * w, y: 0.57 * w - 0.45 * w)
                Ellipse()
                    .strokeBorder(Theme.stampInk.opacity(0.28), lineWidth: 0.8)
                    .frame(width: 0.64 * w, height: 0.82 * w)
                    .offset(x: 0.18 * w, y: 0.57 * w - 0.41 * w)
                ForEach(0..<4, id: \.self) { i in
                    Text("✦")
                        .font(.system(size: 0.05 * w))
                        .foregroundStyle(Theme.stampInk.opacity(0.5))
                        .position(x: i % 2 == 0 ? 0.135 * w : 0.865 * w,
                                  y: i < 2 ? 0.145 * w : 0.945 * w)
                }

            case .ink:
                // Ink — the poster scrim the picture melts into, and a red tick.
                LinearGradient(
                    colors: [.clear, Color(hex: 0x2A2621)],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.66)
                )
                .frame(width: w, height: 0.58 * w)
                .offset(y: 0.74 * w)
                Rectangle()
                    .fill(Color(hex: 0xE0644A))
                    .frame(width: 0.07 * w, height: max(1.5, 0.0076 * w))
                    .position(x: 0.5 * w, y: 1.05 * w)

            case .airmail:
                // Airmail — chevron ring + the par avion mark.
                AirmailBorder(inset: 0.038 * w, band: 0.028 * w)
                if !templateMode {
                    Text("PAR AVION")
                        .font(.system(size: 0.036 * w, weight: .semibold, design: .serif))
                        .italic()
                        .kerning(0.036 * w * 0.12)
                        .foregroundStyle(Color(hex: 0x274896))
                        .shadow(color: Color(hex: 0xFCFBF6), radius: 1.5)
                        .shadow(color: Color(hex: 0xFCFBF6), radius: 1.5)
                        .position(x: 0.5 * w, y: 0.13 * w)
                }

            case .commemorative:
                // Commemorative — red keyline + the denomination bar at the foot.
                Rectangle()
                    .strokeBorder(Theme.postalRed, lineWidth: 2)
                    .frame(width: content.width, height: content.height)
                    .offset(x: content.minX, y: content.minY)

            case .foil:
                // Foil — hairline around the picture, the edition mark, and a sheen.
                Rectangle()
                    .strokeBorder(Color(red: 0.24, green: 0.17, blue: 0.12).opacity(0.4),
                                  lineWidth: 1)
                    .frame(width: 0.844 * w, height: 1.054 * w)
                    .offset(x: 0.078 * w, y: 0.078 * w)
                LinearGradient(
                    stops: [.init(color: .clear, location: 0.30),
                            .init(color: .white.opacity(0.28), location: 0.46),
                            .init(color: Color(hex: 0xBEE6FF).opacity(0.20), location: 0.50),
                            .init(color: Color(hex: 0xFFCDEB).opacity(0.22), location: 0.54),
                            .init(color: .clear, location: 0.70)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(width: 0.90 * w, height: 1.11 * w)
                .offset(x: 0.05 * w, y: 0.05 * w)
                .blendMode(.screen)
                if !templateMode {
                    Text("SPECIAL EDITION ✦")
                        .font(.system(size: 0.03 * w, weight: .semibold).width(.condensed))
                        .kerning(0.03 * w * 0.3)
                        .foregroundStyle(Color(hex: 0xFBEFC4))
                        .shadow(color: Color(red: 0.24, green: 0.16, blue: 0.06).opacity(0.6),
                                radius: 1, y: 1)
                        .position(x: 0.5 * w, y: 0.115 * w)
                }

            case .revenue:
                // Revenue — double rule, revenue strip, duty bar.
                Rectangle()
                    .strokeBorder(Color(hex: 0x2A3C52), lineWidth: 1.2)
                    .frame(width: content.width, height: content.height)
                    .offset(x: content.minX, y: content.minY)
                Rectangle()
                    .strokeBorder(Color(hex: 0x2A3C52).opacity(0.8), lineWidth: 1)
                    .frame(width: content.width - 0.024 * w,
                           height: content.height - 0.024 * w)
                    .offset(x: content.minX + 0.012 * w, y: content.minY + 0.012 * w)

            case .botanical:
                // Botanical — fine double rule + the series line.
                Rectangle()
                    .strokeBorder(Color(hex: 0x2E422C).opacity(0.5), lineWidth: 1)
                    .frame(width: content.width, height: content.height)
                    .offset(x: content.minX, y: content.minY)
                Rectangle()
                    .strokeBorder(Color(hex: 0x2E422C).opacity(0.3), lineWidth: 0.8)
                    .frame(width: content.width - 0.046 * w,
                           height: content.height - 0.046 * w)
                    .offset(x: content.minX + 0.023 * w, y: content.minY + 0.023 * w)
                if !templateMode {
                    Text("DEFINITIVE SERIES")
                        .font(.system(size: 0.028 * w, weight: .semibold, design: .serif))
                        .kerning(0.028 * w * 0.22)
                        .foregroundStyle(Color(hex: 0x2E422C).opacity(0.85))
                        .position(x: 0.5 * w, y: 0.12 * w)
                }

            case .night:
                // Night — the neon keyline glowing around the picture.
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color(hex: 0x6FE9FF), lineWidth: 1.5)
                    .frame(width: content.width, height: content.height)
                    .offset(x: content.minX, y: content.minY)
                    .shadow(color: Color(hex: 0x6FE9FF).opacity(0.7), radius: 0.038 * w)
                    .shadow(color: Color(hex: 0x6FE9FF).opacity(0.45), radius: 0.012 * w)

            case .sweetheart:
                // Sweetheart — white + rose hairlines and the corner florets.
                Rectangle()
                    .strokeBorder(Color(red: 1.0, green: 0.96, blue: 0.95).opacity(0.72),
                                  lineWidth: 1)
                    .frame(width: content.width, height: content.height)
                    .offset(x: content.minX, y: content.minY)
                Rectangle()
                    .strokeBorder(Color(hex: 0x7A3A3C).opacity(0.42), lineWidth: 1)
                    .frame(width: content.width - 0.046 * w,
                           height: content.height - 0.046 * w)
                    .offset(x: content.minX + 0.023 * w, y: content.minY + 0.023 * w)
                ForEach(0..<2, id: \.self) { i in
                    Text("✦")
                        .font(.system(size: 0.04 * w))
                        .foregroundStyle(Color(hex: 0x7A3A3C).opacity(0.6))
                        .position(x: i == 0 ? 0.13 * w : 0.87 * w, y: 0.12 * w)
                }
            }
        }
        .frame(width: w, height: 1.3125 * w, alignment: .topLeading)
    }

    // MARK: Content

    @ViewBuilder
    private func contentLayer(_ w: CGFloat, content: CGRect) -> some View {
        switch assembly.content {
        case .raw:
            // The die press: the whole sheet dips as the cutter strikes and
            // the white outline appears; the waste then fades away beneath
            // the cut sticker. sin(border·π) is 0 at both ends, so the crop
            // is pixel-exact before and after the punch, and waste 0 leaves
            // exactly the sticker — the swap to .final is invisible.
            //
            // The raw photo, its waste and the cut outline are ONE sheet:
            // everything rides a single box→frame mapping (identity until
            // the cut piece takes flight, the composed sticker frame once
            // flown), so no state combination — mid-switch, stalled wave,
            // reversed wave — can show the photo and the sticker at two
            // different scales.
            let boxRect = wasteBox(content: content)
            let sheet = sheetTargetRect(w, content: content, box: boxRect)
            let sx = boxRect.width > 0 ? sheet.width / boxRect.width : 1
            let sy = boxRect.height > 0 ? sheet.height / boxRect.height : 1
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    if let raw = rawCrop ?? image {
                        // Plain layer — the post-cut photo. Covers the waste
                        // at full opacity until the wave's first tick (the
                        // shatter itself lives in hoistedWaste, ABOVE the
                        // shader modifiers); during an interrupted cut the
                        // photo heals BEHIND the dying grains. 0.001 floor =
                        // pre-warm pattern.
                        rawView(raw, content: content)
                            .opacity(max(0.001, assembly.photoFade,
                                         assembly.waste >= 1 ? 1 : 0))
                    }
                    stickerOverlay(w, content: content, box: boxRect)
                }
                .scaleEffect(x: sx, y: sy, anchor: .topLeading)
                .offset(x: sheet.minX - boxRect.minX * sx,
                        y: sheet.minY - boxRect.minY * sy)
                stickerTag(w, content: content, frame: sheet)
            }
            .scaleEffect(1 - 0.018 * sin(min(1, max(0, assembly.press)) * .pi))
        case .final:
            finalContent(w, content: content)
            if labelAnchor != nil, let image {
                stickerTag(w, content: content,
                           frame: stickerFrame(w, content: content,
                                               imageSize: image.size))
            }
        }
    }

    /// The sticker's coverage rect in content coordinates — the grain
    /// wave's origin.
    private func wasteBox(content: CGRect) -> CGRect {
        guard let box = stickerBox else {
            return CGRect(x: content.midX - 1, y: content.midY - 1, width: 2, height: 2)
        }
        return CGRect(
            x: content.minX + box.minX * content.width,
            y: content.minY + box.minY * content.height,
            width: box.width * content.width,
            height: box.height * content.height
        )
    }

    /// Where the sticker's coverage box is headed: pinned to itself until
    /// the cut piece takes flight (flight 0), the composed sticker frame
    /// once flown (flight 1). The interpolation is what the flight animates
    /// through — the whole sheet shrinks or grows as one piece.
    private func sheetTargetRect(_ w: CGFloat, content: CGRect, box: CGRect) -> CGRect {
        guard style == .cutout, stickerBox != nil, let image else { return box }
        let t = min(1, max(0, assembly.flight))
        guard t > 0 else { return box }
        let frame = stickerFrame(w, content: content, imageSize: image.size)
        return CGRect(
            x: box.minX + (frame.minX - box.minX) * t,
            y: box.minY + (frame.minY - box.minY) * t,
            width: box.width + (frame.width - box.width) * t,
            height: box.height + (frame.height - box.height) * t
        )
    }

    /// The sticker's name — part of its die cut, CapWords-style: a white
    /// tag pressed onto the subject's lower edge. Interactive contexts
    /// (reveal) always show it, with a NAME IT placeholder when empty;
    /// static previews only show a real name.
    @ViewBuilder
    private func stickerTag(_ w: CGFloat, content: CGRect, frame: CGRect) -> some View {
        if style == .cutout, stickerBox != nil || labelAnchor != nil, image != nil,
           !title.isEmpty || editableTitle != nil || onTapCaption != nil {
            Group {
                if let binding = editableTitle {
                    // The editor keeps the die-cut idiom: the white contour
                    // mirrors the live text beneath a bare field — same
                    // font, same cut, no pill, no style jump. The mirror's
                    // clear core lets the field supply the ink glyphs (and
                    // the caret); the fat contour forgives sub-pixel drift.
                    ZStack {
                        DieCutText(
                            text: binding.wrappedValue.isEmpty
                                ? "Name it" : binding.wrappedValue,
                            fontSize: 0.068 * w,
                            ink: .clear
                        )
                        TextField("Name it", text: binding)
                            .font(.system(size: 0.068 * w, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .tint(Theme.postalRed)
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit(onSubmitTitle)
                            .fixedSize()
                            .modifier(FocusedIfAvailable(focus: titleFocused))
                    }
                } else {
                    DieCutText(
                        text: title.isEmpty ? "Name it" : title,
                        fontSize: 0.068 * w,
                        ink: title.isEmpty ? Theme.stampInk.opacity(0.45) : .black
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onTapCaption?() }
                }
            }
            .rotationEffect(.degrees(-3))
            .position(x: frame.midX, y: tagY(frame: frame, w: w))
            // Sharper than the outline: dies in the bottom half of every
            // melt, appears in the top half of every punch — the tag must
            // be gone before the paper caption rises, while `border`
            // itself stays complementary to the photo fade.
            .opacity(max(0.001, 2 * assembly.border - 1))
            // At rest in paper form this sits at 0.001 opacity over the
            // subject — it must not swallow taps meant for the stamp.
            .allowsHitTesting(assembly.border > 0.5)
        }
    }

    /// The label rides the measured contour (anchor fraction of the sticker
    /// frame), half on the subject, half off — fused with the cut. Falls
    /// back to the analytic margin when no measurement exists.
    private func tagY(frame: CGRect, w: CGFloat) -> CGFloat {
        let contour = labelAnchor.map { frame.minY + $0 * frame.height }
            ?? (frame.maxY - 0.055 * max(frame.width, frame.height))
        return contour + 0.068 * w * 0.55
    }

    /// The die-cut sticker (white border + subject) over the raw photo. Its
    /// subject pixels match the crop beneath exactly, so only the outline
    /// reads as it fades in. The 0.001 floor keeps the layer alive from the
    /// reveal's first frame — its one-time composite must never land
    /// mid-choreography.
    @ViewBuilder
    private func stickerOverlay(_ w: CGFloat, content: CGRect, box: CGRect) -> some View {
        if style == .cutout, stickerBox != nil, let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
                .opacity(max(0.001, assembly.border))
        }
    }

    private func rawView(_ raw: UIImage, content: CGRect) -> some View {
        Image(uiImage: raw)
            .resizable()
            .scaledToFill()
            .frame(width: content.width, height: content.height)
            // Same corner proportion the develop dissolve leaves on the
            // viewfinder (12pt on a ~340pt rect), so the snap → reveal
            // handoff keeps one silhouette.
            .clipShape(RoundedRectangle(cornerRadius: content.width * 0.035))
            .offset(x: content.minX, y: content.minY)
    }

    // MARK: Picture window

    /// Where the classic photo prints, per edition: the poster bleeds, the
    /// cameo sits in its oval, airmail and foil pull inside their rings.
    private func pictureRect(_ w: CGFloat) -> CGRect {
        switch variant {
        case .ink:     CGRect(x: 0, y: 0, width: w, height: 1.05 * w)
        case .airmail: CGRect(x: 0.10 * w, y: 0.115 * w, width: 0.80 * w, height: 1.00 * w)
        case .foil:    CGRect(x: 0.078 * w, y: 0.078 * w, width: 0.844 * w, height: 1.054 * w)
        case .ivory:   CGRect(x: 0.18 * w, y: 0.16 * w, width: 0.64 * w, height: 0.82 * w)
        // The whole plate: the picture runs under the perforation itself.
        case .bleed:   CGRect(x: 0, y: 0, width: w, height: 1.3125 * w)
        default:       contentRect(w)
        }
    }

    /// Print treatments as continuous values — variant switches animate
    /// numbers on ONE image view, never its identity, so the switch
    /// choreography survives mid-flight.
    private var pictureGrayscale: Double { variant == .botanical ? 1 : 0 }
    private var pictureSaturation: Double {
        switch variant {
        case .ivory: 0.72
        case .revenue: 0.6
        default: 1
        }
    }
    private var pictureContrast: Double {
        switch variant {
        case .botanical: 1.3
        case .ivory: 1.02
        default: 1
        }
    }
    /// Multiply wash: sepia warmth for the cameo, single green ink for the
    /// definitive. White is the identity.
    private var pictureWash: Color {
        switch variant {
        case .ivory: Color(red: 1.0, green: 0.94, blue: 0.84)
        case .botanical: Color(hex: 0xCDE8B4)
        default: .white
        }
    }

    /// The classic photo, printed per edition.
    private func classicPicture(_ img: UIImage, _ w: CGFloat) -> some View {
        let rect = pictureRect(w)
        return Image(uiImage: img)
            .resizable()
            .scaledToFill()
            .frame(width: rect.width, height: rect.height)
            .grayscale(pictureGrayscale)
            .saturation(pictureSaturation)
            .contrast(pictureContrast)
            .colorMultiply(pictureWash)
            .mask {
                ZStack {
                    RoundedRectangle(cornerRadius: rect.width * 0.01)
                        .opacity(variant == .ivory || variant == .bleed ? 0 : 1)
                    Ellipse()
                        .opacity(variant == .ivory ? 1 : 0)
                    PerforatedRect()
                        .opacity(variant == .bleed ? 1 : 0)
                }
            }
            .offset(x: rect.minX, y: rect.minY)
    }

    @ViewBuilder
    private func finalContent(_ w: CGFloat, content: CGRect) -> some View {
        if style == .cutout, let image {
            let frame = stickerFrame(w, content: content, imageSize: image.size)

            // Contact shadow: arrives with the paper.
            Ellipse()
                .fill(Theme.shadow.opacity(0.16 * assembly.paper))
                .frame(width: frame.width * 0.62, height: 0.04 * w)
                .blur(radius: 0.018 * w)
                .position(x: frame.midX, y: frame.maxY - 0.004 * w)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: frame.width, height: frame.height)
                .rotationEffect(.degrees(
                    variant == .airmail ? -2.5 * assembly.settle : 0))
                .shadow(color: Theme.shadow.opacity(0.12 * assembly.paper),
                        radius: 0.012 * w, y: 0.008 * w)
                .position(x: frame.midX, y: frame.midY)
        } else if let image {
            classicPicture(image, w)
        }
    }

    /// Interpolates the die-cut sticker between its captured position inside
    /// the crop (settle = 0) and its composed position (settle = 1).
    private func stickerFrame(_ w: CGFloat, content: CGRect, imageSize: CGSize) -> CGRect {
        // Each paper composes the subject differently: the definitive
        // centers it, the vignette tucks it inside the oval, the poster
        // bleeds it past the picture area, airmail pastes it a touch high.
        let (fw, fh, dy): (CGFloat, CGFloat, CGFloat) = switch variant {
        case .tinted: (0.82, 0.82, -0.012)
        case .ivory: (0.60, 0.60, -0.055)
        case .ink: (1.12, 0.97, 0.006)
        case .airmail: (0.74, 0.74, -0.026)
        case .commemorative: (0.80, 0.74, -0.055)
        case .foil: (0.76, 0.76, -0.012)
        case .revenue: (0.78, 0.68, -0.010)
        case .botanical: (0.78, 0.78, -0.012)
        case .night: (0.80, 0.80, -0.012)
        case .sweetheart: (0.80, 0.80, -0.012)
        case .bleed: (0.94, 0.94, 0)
        }
        let avail = CGSize(width: content.width * fw, height: content.height * fh)
        let fit = min(avail.width / imageSize.width, avail.height / imageSize.height)
        let finalSize = CGSize(width: imageSize.width * fit, height: imageSize.height * fit)
        let finalRect = CGRect(
            x: content.midX - finalSize.width / 2,
            y: content.midY - finalSize.height / 2 + dy * w,
            width: finalSize.width, height: finalSize.height
        )
        guard let box = stickerBox, assembly.settle < 1 else { return finalRect }

        let startRect = CGRect(
            x: content.minX + box.minX * content.width,
            y: content.minY + box.minY * content.height,
            width: box.width * content.width,
            height: box.height * content.height
        )
        let t = assembly.settle
        return CGRect(
            x: startRect.minX + (finalRect.minX - startRect.minX) * t,
            y: startRect.minY + (finalRect.minY - startRect.minY) * t,
            width: startRect.width + (finalRect.width - startRect.width) * t,
            height: startRect.height + (finalRect.height - startRect.height) * t
        )
    }

    // MARK: Caption

    /// Each edition sets the caption's voice: engraved caps (tinted, foil,
    /// botanical), italic serif title case (ivory, sweetheart), airy
    /// tracked caps (ink, night), condensed (commemorative), mono (revenue).
    private func titleSize(_ w: CGFloat) -> CGFloat {
        switch variant {
        case .ivory, .sweetheart: 0.055 * w
        case .ink: 0.046 * w
        case .commemorative: 0.050 * w
        case .night: 0.048 * w
        case .revenue: 0.044 * w
        default: 0.052 * w
        }
    }

    private func titleFont(size: CGFloat) -> Font {
        switch variant {
        case .ivory: .system(size: size, weight: .medium, design: .serif).italic()
        case .sweetheart: .system(size: size, weight: .semibold, design: .serif).italic()
        case .ink: .system(size: size, weight: .regular, design: .serif)
        case .commemorative: .system(size: size, weight: .semibold).width(.condensed)
        case .night: .system(size: size, weight: .medium).width(.condensed)
        case .revenue: .system(size: size, weight: .bold, design: .monospaced)
        default: Theme.stampEngraved(size)
        }
    }

    private func titleFont(_ w: CGFloat) -> Font { titleFont(size: titleSize(w)) }

    /// № and the struck date share the line's quieter voice.
    private func metaFont(_ w: CGFloat) -> Font {
        switch variant {
        case .ivory: .system(size: 0.036 * w, weight: .medium, design: .serif).italic()
        case .sweetheart: .system(size: 0.035 * w, weight: .medium, design: .serif)
        case .commemorative, .revenue: .system(size: 0.033 * w, design: .monospaced)
        case .night: .system(size: 0.033 * w).width(.condensed)
        default: .system(size: 0.035 * w, weight: .medium, design: .serif)
        }
    }

    private var lowercaseTitle: Bool {
        variant == .ivory || variant == .sweetheart
    }

    private var titleDisplay: String {
        // One localized placeholder, cased by the edition's own voice. The
        // two hardcoded spellings never reached the catalog — `Text(String)`
        // doesn't localize — so an untitled stamp printed "UNTITLED" in
        // every language, on an artifact the user then shares.
        let base = title.isEmpty ? L("Untitled") : title
        return lowercaseTitle ? base : base.uppercased()
    }

    /// Letter tracking as an em fraction of the title size.
    private var titleTracking: CGFloat {
        switch variant {
        case .ivory, .sweetheart: 0.015
        case .ink: 0.34
        case .night: 0.24
        case .commemorative: 0.14
        case .revenue: 0.08
        case .airmail: 0.10
        default: 0.13
        }
    }

    private static let struckDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private var dateText: String {
        let s = Self.struckDate.string(from: date)
        return lowercaseTitle ? s : s.uppercased()
    }

    /// Commemorative and revenue print their caption inside a filled bar
    /// sitting in the band below the picture — no separate caption line.
    private var barCaptioned: Bool {
        variant == .commemorative || variant == .revenue
    }

    /// The caption bar: title left (tappable to rename, editable in
    /// place), struck date right, on the edition's bar stock.
    private func captionBar(_ w: CGFloat) -> some View {
        let barColor = variant == .commemorative
            ? Theme.postalRed : Color(hex: 0x2A3C52)
        let dateFont: Font = variant == .commemorative
            ? .system(size: 0.032 * w, weight: .semibold).width(.condensed)
            : .system(size: 0.030 * w, design: .monospaced)
        let dateInk = variant == .commemorative
            ? Color(hex: 0xFCEDE4) : Color(hex: 0xB9C6A6)

        return HStack {
            if let binding = editableTitle {
                TextField("NAME IT", text: binding)
                    .font(titleFont(w))
                    .foregroundStyle(markInk)
                    .tint(.white)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(onSubmitTitle)
                    .modifier(FocusedIfAvailable(focus: titleFocused))
            } else {
                staggeredTitle(font: titleFont(w), width: w)
                    .overlay(alignment: .bottom) {
                        // Rename affordance, same dashed rule as the line.
                        Line()
                            .stroke(markInk.opacity(
                                onTapCaption == nil ? 0 : 0.38 * assembly.caption),
                                    style: StrokeStyle(lineWidth: 1, dash: [2.5, 3]))
                            .frame(height: 1)
                            .offset(y: 0.018 * w)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onTapCaption?() }
            }
            Spacer(minLength: 0.03 * w)
            Text(dateText)
                .font(dateFont)
                .foregroundStyle(dateInk)
        }
        .padding(.horizontal, 0.045 * w)
        .frame(width: 0.85 * w, height: 0.12 * w)
        .background(barColor)
        .position(x: 0.5 * w, y: 1.205 * w)
    }

    /// The caption bar's stock with no type on it — the commemorative's
    /// denomination bar, the revenue's duty bar. Same rect and colour as
    /// `captionBar`, so a template and a real stamp print the same band.
    private func captionBarStock(_ w: CGFloat) -> some View {
        Rectangle()
            .fill(variant == .commemorative ? Theme.postalRed : Color(hex: 0x2A3C52))
            .frame(width: 0.85 * w, height: 0.12 * w)
            .position(x: 0.5 * w, y: 1.205 * w)
    }

    @ViewBuilder
    private func captionLayer(_ w: CGFloat) -> some View {
        let lineY = variant == .ink ? 1.135 * w : 1.19 * w
        let titleFont = titleFont(w)

        ZStack {
            if barCaptioned {
                captionBar(w)
            }

            // № holds the left of the line, the struck date the right.
            if !barCaptioned {
                HStack {
                    Text("№\u{2009}\(number)")
                    Spacer()
                    Text(dateText)
                }
                .font(metaFont(w))
                .foregroundStyle(metaInk.opacity(0.6))
                .padding(.horizontal, 0.075 * w)
                .frame(width: w)
                .position(x: w / 2, y: lineY)
            }

            if let binding = editableTitle, !barCaptioned {
                editableCaption(binding, font: titleFont, width: w)
                    .position(x: w / 2, y: lineY)
            } else if editableTitle == nil, !barCaptioned {
                // One stable branch whether or not renaming is available —
                // conditional branches here would re-mount the title
                // mid-letter-stagger when chrome appears.
                staggeredTitle(font: titleFont, width: w)
                    .overlay(alignment: .bottom) {
                        // Rename affordance: a faint dashed rule under the title.
                        Line()
                            .stroke(markInk.opacity(
                                onTapCaption == nil ? 0 : 0.38 * assembly.caption),
                                    style: StrokeStyle(lineWidth: 1, dash: [2.5, 3]))
                            .frame(height: 1)
                            .offset(y: 0.022 * w)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onTapCaption?() }
                    .position(x: w / 2, y: lineY)
            }
        }
    }

    @ViewBuilder
    private func staggeredTitle(font: Font, width w: CGFloat) -> some View {
        let chars = Array(titleDisplay.prefix(18))
        let n = max(chars.count, 1)
        let base = titleSize(w)
        let condensed = variant == .commemorative || variant == .night
        let estimated = CGFloat(n) * base * ((condensed ? 0.55 : 0.72) + titleTracking)
        let fit = min(1, 0.40 * w / max(estimated, 1))
        let size = base * fit

        if assembly.caption >= 1.0 {
            Text(titleDisplay)
                .font(titleFont(size: size))
                .foregroundStyle(markInk.opacity(variant == .night ? 1 : 0.82))
                .shadow(color: variant == .night
                            ? Color(hex: 0x6FE9FF).opacity(0.8) : .clear,
                        radius: variant == .night ? 0.03 * w : 0)
                .lineLimit(1)
                .fixedSize()
        } else {
            HStack(spacing: size * titleTracking) {
                ForEach(Array(chars.enumerated()), id: \.offset) { i, ch in
                    let p = letterProgress(i, of: n)
                    Text(String(ch))
                        .font(titleFont(size: size))
                        .foregroundStyle(markInk.opacity(variant == .night ? 1 : 0.82))
                        .shadow(color: variant == .night
                                    ? Color(hex: 0x6FE9FF).opacity(0.8) : .clear,
                                radius: variant == .night ? 0.03 * w : 0)
                        .opacity(p)
                        .offset(y: (1 - p) * 0.03 * w)
                        .blur(radius: (1 - p) * 1.5)
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
    }

    private func letterProgress(_ i: Int, of n: Int) -> Double {
        let window = 0.45
        let start = (1 - window) * Double(i) / Double(max(n - 1, 1))
        return min(1, max(0, (assembly.caption - start) / window))
    }

    @ViewBuilder
    private func editableCaption(
        _ binding: Binding<String>, font: Font, width w: CGFloat
    ) -> some View {
        let field = TextField("NAME IT", text: binding)
            .font(font)
            .foregroundStyle(markInk.opacity(0.82))
            .tint(Theme.postalRed)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit(onSubmitTitle)
            .frame(width: 0.66 * w)
        if let focus = titleFocused {
            field.focused(focus)
        } else {
            field
        }
    }
}

/// Letterforms cut like the sticker itself: ink glyphs wearing the same
/// white die-cut contour as the subject.
struct DieCutText: View {
    var text: String
    var fontSize: CGFloat
    var ink: Color = .black
    /// Contour reach around the glyphs, as an em fraction.
    var spread: CGFloat = 0.34
    /// The glyph voice — nil keeps the app's heavy-rounded chrome default.
    var font: Font? = nil

    var body: some View {
        let margin = max(2, fontSize * spread)
        let base = Text(text)
            .font(font ?? .system(size: fontSize, weight: .heavy, design: .rounded))
            .lineLimit(1)

        base
            .foregroundStyle(ink)
            .background {
                // The cut: blur the glyph silhouette, threshold the tail —
                // one smooth dilation that hugs every letterform. Color
                // glyphs (emoji) need no special casing; whatever alpha
                // they carry, the threshold turns white. The low threshold
                // keeps script hairlines from dropping out of the contour.
                Canvas { context, size in
                    context.addFilter(.alphaThreshold(min: 0.08, color: .white))
                    context.addFilter(.blur(radius: margin / 1.4))
                    context.drawLayer { layer in
                        if let glyphs = context.resolveSymbol(id: 0) {
                            layer.draw(glyphs, at: CGPoint(x: size.width / 2,
                                                           y: size.height / 2))
                        }
                    }
                } symbols: {
                    base.tag(0)
                }
                // Room for the contour beyond the text's own bounds — a
                // Canvas clips at its edges.
                .padding(-margin * 2)
            }
    }
}

/// Applies .focused only when a binding exists.
struct FocusedIfAvailable: ViewModifier {
    var focus: FocusState<Bool>.Binding?
    func body(content: Content) -> some View {
        if let focus { content.focused(focus) } else { content }
    }
}

/// The stored sticker artifact: subject + its die-cut name tag, rendered
/// once at keep time so every surface (album, Messages, share) shows the
/// same object.
struct StickerArtifact: View {
    let image: UIImage
    let title: String
    /// Contour fraction from the alpha scan — the label fuses to the real
    /// silhouette, not the padded image edge.
    var anchor: CGFloat = 0.945

    var body: some View {
        let w = min(image.size.width * image.scale, 1200)
        let scale = w / max(image.size.width * image.scale, 1)
        let h = image.size.height * image.scale * scale
        let fontSize = w * 0.085

        ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .frame(width: w, height: h)
            if !title.isEmpty {
                DieCutText(text: title, fontSize: fontSize, ink: .black)
                    .rotationEffect(.degrees(-3))
                    .position(x: w / 2, y: anchor * h + fontSize * 0.55)
            }
        }
        .frame(width: w, height: h)
        .padding(w * 0.04)
        .padding(.bottom, fontSize * 1.2)
    }
}

/// A 1-pt horizontal line shape (dashed rules).
struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// Applies the holographic shimmer. `enabled` must be constant for a view's
/// lifetime — branching on live values (like strength) would change the whole
/// stamp's view identity mid-flight and silently kill in-progress animations.
/// Shared with the detail view, which wears it around the flat artifact
/// kinds (polaroid, card, canvas).
struct HoloModifier: ViewModifier {
    var enabled: Bool
    var strength: Double
    var sweep: Double
    var dir: CGPoint

    func body(content: Content) -> some View {
        if enabled {
            content.colorEffect(ShaderLibrary.holoShimmer(
                .boundingRect,
                .float(sweep),
                .float2(dir),
                .float(strength)
            ))
        } else {
            content
        }
    }
}

/// Applies the liquid poke ripple. `enabled` must be constant for a view's
/// lifetime — branching on live values would change the stamp's identity and
/// silently kill in-flight animations. Shared with the detail view.
struct LiquidModifier: ViewModifier {
    var enabled: Bool
    var center: CGPoint
    var time: Double

    func body(content: Content) -> some View {
        if enabled {
            content.distortionEffect(
                ShaderLibrary.liquidPoke(
                    .float2(center),
                    .float(time),
                    .float(13)
                ),
                maxSampleOffset: CGSize(width: 15, height: 15)
            )
        } else {
            content
        }
    }
}

/// Par avion border: alternating red/blue slanted dashes in a ring just
/// inside the perforations — the classic airmail envelope edge.
struct AirmailBorder: View {
    var inset: CGFloat
    var band: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let outer = CGRect(origin: .zero, size: size)
                .insetBy(dx: inset, dy: inset)
            let inner = outer.insetBy(dx: band, dy: band)
            var ring = Path(outer)
            ring.addPath(Path(inner))
            ctx.clip(to: ring, style: FillStyle(eoFill: true))

            let red = Theme.postalRed.opacity(0.82)
            let blue = Color(red: 0.17, green: 0.29, blue: 0.60).opacity(0.82)
            let stripe = band * 1.9
            let gap = stripe * 0.62
            var x = -size.height - stripe
            var i = 0
            while x < size.width + size.height {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                p.addLine(to: CGPoint(x: x + size.height + stripe, y: 0))
                p.addLine(to: CGPoint(x: x + stripe, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(i % 2 == 0 ? red : blue))
                i += 1
                x += stripe + gap
            }
        }
        .allowsHitTesting(false)
    }
}

/// Convenience for album/drawer rendering. Sticker items render bare —
/// no paper, no caption, no cancellation.
extension StampView {
    init(stamp: Stamp, image: UIImage?) {
        self.init(
            image: image,
            style: stamp.style,
            tint: stamp.tint.color,
            title: stamp.displayTitle,
            number: stamp.number,
            date: stamp.date,
            variant: stamp.variant,
            labelAnchor: stamp.kind == .sticker ? stamp.labelAnchor : nil,
            assembly: stamp.kind == .sticker
                ? Assembly(paper: 0, caption: 0, content: .final)
                : .dressed
        )
    }
}
