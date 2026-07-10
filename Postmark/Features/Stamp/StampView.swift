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
        static let bare = Assembly(paper: 0, caption: 0, settle: 0, border: 0, content: .raw)
    }

    var image: UIImage?
    var style: Stamp.Style
    var tint: Color
    var title: String
    var number: Int
    var year: String
    var date: Date = .now
    var variant: StampVariant = .tinted
    var showsPostmark = false
    var postmarkScale: CGFloat = 1
    /// Normalized subject box within the crop (sticker start frame).
    var stickerBox: CGRect? = nil
    /// Raw crop retained for the .raw / .unmasking stages.
    var rawCrop: UIImage? = nil

    var assembly: Assembly = .dressed

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

    /// Paper fill for the current variant.
    private var paperFill: Color {
        switch variant {
        // Every paper keeps clear tonal separation from the album backdrop
        // (#F4EFE6): tinted and ivory sit deeper, ink far darker, airmail
        // brighter — a white envelope on cream, carried by its stripes.
        case .tinted: tint
        case .ivory: Color(red: 0.885, green: 0.830, blue: 0.700)
        case .ink: Color(red: 0.165, green: 0.150, blue: 0.130)
        case .airmail: Color(red: 0.995, green: 0.990, blue: 0.980)
        }
    }

    /// Caption / hairline / cancellation ink — prints light on ink paper.
    private var markInk: Color {
        variant == .ink ? Color(red: 0.93, green: 0.90, blue: 0.84) : Theme.ink
    }

    var editableTitle: Binding<String>? = nil
    var titleFocused: FocusState<Bool>.Binding? = nil
    var onSubmitTitle: () -> Void = {}
    /// When set, the static caption is tappable (shows a rename affordance).
    var onTapCaption: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            stampBody(w)
        }
        .aspectRatio(1 / 1.3125, contentMode: .fit)
    }

    // MARK: Layout

    private func contentRect(_ w: CGFloat) -> CGRect {
        CGRect(x: 0.075 * w, y: 0.075 * w, width: 0.85 * w, height: 1.0625 * w)
    }

    @ViewBuilder
    private func stampBody(_ w: CGFloat) -> some View {
        let content = contentRect(w)

        ZStack(alignment: .topLeading) {
            // ── Paper ────────────────────────────────────────────────
            paper(w)
                .opacity(assembly.paper)
                .scaleEffect(0.94 + 0.06 * assembly.paper)

            // ── Content ──────────────────────────────────────────────
            contentLayer(w, content: content)

            // ── Caption strip ────────────────────────────────────────
            captionLayer(w)
                .opacity(assembly.paper)

            // ── Cancellation: rubber-stamped date, nothing more ─────
            if showsPostmark {
                DateStamp(
                    date: date,
                    fontSize: 0.052 * w,
                    ink: variant == .ink
                        ? Color(red: 0.94, green: 0.52, blue: 0.42)
                        : Theme.postalRed
                )
                .blendMode(variant == .ink ? .normal : .multiply)
                .opacity(0.88)
                .scaleEffect(postmarkScale)
                .rotationEffect(.degrees(-7))
                .position(x: 0.72 * w, y: 0.135 * w)
                .allowsHitTesting(false)
            }
        }
        .compositingGroup()
        // Shader effects cannot rasterize platform-backed views: with the
        // rename TextField mounted they render as a yellow prohibition
        // placeholder. Drop them during editing — the identity change is
        // confined to the edit-mode boundary, where nothing is in flight.
        .modifier(HoloModifier(enabled: holoEnabled && editableTitle == nil,
                               strength: holoStrength,
                               sweep: holoSweep, dir: holoDir))
        .modifier(LiquidModifier(enabled: liquidEnabled && editableTitle == nil,
                                 center: liquidCenter,
                                 time: liquidTime))
    }

    // MARK: Paper

    @ViewBuilder
    private func paper(_ w: CGFloat) -> some View {
        let content = contentRect(w)
        let fw = content.width + 0.032 * w
        let fh = content.height + 0.032 * w
        let fx = content.minX - 0.016 * w
        let fy = content.minY - 0.016 * w

        ZStack(alignment: .topLeading) {
            PerforatedRect()
                .fill(paperFill)
                .colorEffect(ShaderLibrary.paperGrain(.float(0.62), .float(0.55)))
                .shadow(color: Theme.ink.opacity(0.22), radius: 0.05 * w, y: 0.024 * w)
                .shadow(color: Theme.ink.opacity(0.12), radius: 0.009 * w, y: 0.005 * w)

            // Each paper has its own signature framing. All treatments stay
            // mounted; switching variants only animates opacity, never view
            // identity.

            // Tinted — the engraved hairline.
            Rectangle()
                .strokeBorder(markInk.opacity(0.28), lineWidth: 1)
                .frame(width: fw, height: fh)
                .offset(x: fx, y: fy)
                .opacity(variant == .tinted ? 1 : 0)

            // Ivory — a Penny Black-style oval vignette: double engraved
            // ring around the subject, rosettes in the spandrels.
            ZStack(alignment: .topLeading) {
                Ellipse()
                    .strokeBorder(markInk.opacity(0.55), lineWidth: 1.5)
                Ellipse()
                    .strokeBorder(markInk.opacity(0.30), lineWidth: 0.8)
                    .padding(0.016 * w)
            }
            .frame(width: content.width * 0.94, height: content.height * 0.90)
            .offset(x: content.midX - content.width * 0.47,
                    y: content.midY - content.height * 0.45)
            .opacity(variant == .ivory ? 1 : 0)
            ForEach(0..<4, id: \.self) { i in
                Text("✦")
                    .font(.system(size: 0.042 * w))
                    .foregroundStyle(markInk.opacity(0.5))
                    .position(
                        x: i % 2 == 0 ? content.minX + 0.028 * w
                                      : content.maxX - 0.028 * w,
                        y: i < 2 ? content.minY + 0.030 * w
                                 : content.maxY - 0.030 * w
                    )
                    .opacity(variant == .ivory ? 1 : 0)
            }

            // Ink — no frame at all: a poster. The subject itself bleeds
            // past the picture area and the type prints in light ink.

            // Airmail — striped border and the envelope mark.
            AirmailBorder(inset: 0.040 * w, band: 0.028 * w)
                .opacity(variant == .airmail ? 1 : 0)
            Text("PAR AVION")
                .font(.system(size: 0.032 * w, weight: .semibold, design: .serif))
                .italic()
                .kerning(0.032 * w * 0.28)
                .foregroundStyle(Color(red: 0.17, green: 0.29, blue: 0.60).opacity(0.75))
                .position(x: content.minX + 0.17 * w, y: content.minY + 0.045 * w)
                .opacity(variant == .airmail ? 1 : 0)
        }
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
            ZStack(alignment: .topLeading) {
                if let raw = rawCrop ?? image {
                    rawView(raw, content: content)
                        .opacity(assembly.waste)
                }
                stickerOverlay(w, content: content)
                stickerTag(w, content: content)
            }
            .scaleEffect(1 - 0.018 * sin(min(1, max(0, assembly.border)) * .pi))
        case .final:
            finalContent(w, content: content)
        }
    }

    /// The sticker's name — part of its die cut, CapWords-style: a white
    /// tag pressed onto the subject's lower edge. Interactive contexts
    /// (reveal) always show it, with a NAME IT placeholder when empty;
    /// static previews only show a real name.
    @ViewBuilder
    private func stickerTag(_ w: CGFloat, content: CGRect) -> some View {
        if style == .cutout, stickerBox != nil, let image,
           !title.isEmpty || editableTitle != nil || onTapCaption != nil {
            let frame = stickerFrame(w, content: content, imageSize: image.size)
            Group {
                if let binding = editableTitle {
                    TextField("Name it", text: binding)
                        .font(.system(size: 0.055 * w, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .tint(Theme.postalRed)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(onSubmitTitle)
                        .frame(width: 0.44 * w)
                        .modifier(FocusedIfAvailable(focus: titleFocused))
                        .padding(.horizontal, 0.04 * w)
                        .padding(.vertical, 0.02 * w)
                        .background(Capsule().fill(.white.opacity(0.95)))
                } else {
                    DieCutText(
                        text: title.isEmpty ? "Name it" : title,
                        fontSize: 0.06 * w,
                        ink: title.isEmpty ? Theme.inkSoft.opacity(0.8) : .black
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onTapCaption?() }
                }
            }
            .rotationEffect(.degrees(-3))
            .position(x: frame.midX, y: frame.maxY - 0.045 * w)
            .opacity(max(0.001, assembly.border))
        }
    }

    /// The die-cut sticker (white border + subject) over the raw photo. Its
    /// subject pixels match the crop beneath exactly, so only the outline
    /// reads as it fades in. The 0.001 floor keeps the layer alive from the
    /// reveal's first frame — its one-time composite must never land
    /// mid-choreography.
    @ViewBuilder
    private func stickerOverlay(_ w: CGFloat, content: CGRect) -> some View {
        if style == .cutout, stickerBox != nil, let image {
            let frame = stickerFrame(w, content: content, imageSize: image.size)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .opacity(max(0.001, assembly.border))
        }
    }

    private func rawView(_ raw: UIImage, content: CGRect) -> some View {
        Image(uiImage: raw)
            .resizable()
            .scaledToFill()
            .frame(width: content.width, height: content.height)
            .clipShape(RoundedRectangle(cornerRadius: content.width * 0.01))
            .offset(x: content.minX, y: content.minY)
    }

    @ViewBuilder
    private func finalContent(_ w: CGFloat, content: CGRect) -> some View {
        if style == .cutout, let image {
            let frame = stickerFrame(w, content: content, imageSize: image.size)

            // Contact shadow: arrives with the paper.
            Ellipse()
                .fill(Theme.ink.opacity(0.16 * assembly.paper))
                .frame(width: frame.width * 0.62, height: 0.04 * w)
                .blur(radius: 0.018 * w)
                .position(x: frame.midX, y: frame.maxY - 0.004 * w)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: frame.width, height: frame.height)
                .rotationEffect(.degrees(
                    variant == .airmail ? -2.5 * assembly.settle : 0))
                .shadow(color: Theme.ink.opacity(0.12 * assembly.paper),
                        radius: 0.012 * w, y: 0.008 * w)
                .position(x: frame.midX, y: frame.midY)
        } else if let image {
            rawView(image, content: content)
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
        case .ivory: (0.64, 0.64, -0.020)
        case .ink: (1.12, 0.97, 0.006)
        case .airmail: (0.74, 0.74, -0.026)
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

    /// Each paper sets the caption's voice: engraved caps (tinted/airmail),
    /// italic serif title case (ivory), airy tracked caps (ink).
    private func titleFont(_ w: CGFloat) -> Font {
        switch variant {
        case .ivory: .system(size: 0.054 * w, weight: .medium, design: .serif).italic()
        case .ink: Theme.engraved(0.048 * w)
        default: Theme.engraved(0.052 * w)
        }
    }

    private var titleDisplay: String {
        let base = title.isEmpty ? (variant == .ivory ? "Untitled" : "UNTITLED")
                                 : title
        return variant == .ivory ? base : base.uppercased()
    }

    private func titleSpacing(_ w: CGFloat) -> CGFloat {
        switch variant {
        case .ivory: 0.052 * w * 0.02
        case .ink: 0.052 * w * 0.34
        default: 0.052 * w * 0.14
        }
    }

    @ViewBuilder
    private func captionLayer(_ w: CGFloat) -> some View {
        let lineY = 1.225 * w
        let titleFont = titleFont(w)
        let cornerFont = Font.system(size: 0.036 * w, weight: .medium, design: .serif)

        ZStack {
            Text("№\u{2009}\(number)")
                .font(cornerFont)
                .italic(variant == .ivory)
                .foregroundStyle(markInk.opacity(0.55))
                .position(x: 0.135 * w, y: lineY)

            Text(year)
                .font(cornerFont)
                .italic(variant == .ivory)
                .foregroundStyle(markInk.opacity(0.55))
                .position(x: w - 0.135 * w, y: lineY)

            if let binding = editableTitle {
                editableCaption(binding, font: titleFont, width: w)
                    .position(x: w / 2, y: lineY)
            } else {
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

    private func staggeredTitle(font: Font, width w: CGFloat) -> some View {
        let chars = Array(titleDisplay.prefix(18))
        let n = max(chars.count, 1)
        return HStack(spacing: titleSpacing(w)) {
            ForEach(Array(chars.enumerated()), id: \.offset) { i, ch in
                let p = letterProgress(i, of: n)
                Text(String(ch))
                    .font(font)
                    .foregroundStyle(markInk.opacity(0.82))
                    .opacity(p)
                    .offset(y: (1 - p) * 0.03 * w)
                    .blur(radius: (1 - p) * 1.5)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .frame(maxWidth: 0.62 * w)
        .minimumScaleFactor(0.5)
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
/// white die-cut contour as the subject (offset-stacked copies build the
/// outline).
struct DieCutText: View {
    var text: String
    var fontSize: CGFloat
    var ink: Color = Theme.ink.opacity(0.85)

    var body: some View {
        let base = Text(text)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .lineLimit(1)
        let r = fontSize * 0.24

        return ZStack {
            ForEach(0..<12, id: \.self) { i in
                let a = Double(i) / 12 * 2 * .pi
                base
                    .foregroundStyle(.white)
                    .offset(x: cos(a) * r, y: sin(a) * r)
            }
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) / 8 * 2 * .pi + 0.35
                base
                    .foregroundStyle(.white)
                    .offset(x: cos(a) * r * 0.55, y: sin(a) * r * 0.55)
            }
            base.foregroundStyle(ink)
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
    var tint: Color = Theme.ink

    var body: some View {
        let w = min(image.size.width * image.scale, 1200)
        let scale = w / max(image.size.width * image.scale, 1)
        let h = image.size.height * image.scale * scale

        VStack(spacing: -w * 0.075) {
            Image(uiImage: image)
                .resizable()
                .frame(width: w, height: h)
            if !title.isEmpty {
                DieCutText(text: title, fontSize: w * 0.066, ink: .black)
                    .rotationEffect(.degrees(-3))
            }
        }
        .padding(w * 0.04)
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
private struct HoloModifier: ViewModifier {
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
/// silently kill in-flight animations.
private struct LiquidModifier: ViewModifier {
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
            year: stamp.year,
            date: stamp.date,
            variant: stamp.variant,
            showsPostmark: stamp.kind == .stamp,
            assembly: stamp.kind == .sticker
                ? Assembly(paper: 0, caption: 0, content: .final)
                : .dressed
        )
    }
}
