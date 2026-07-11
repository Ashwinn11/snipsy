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
    var year: String
    var date: Date = .now
    var variant: StampVariant = .tinted
    var showsDateStamp = false
    var dateStampScale: CGFloat = 1
    /// Normalized subject box within the crop (sticker start frame).
    var stickerBox: CGRect? = nil
    /// Raw crop retained for the .raw stage.
    var rawCrop: UIImage? = nil
    /// Subject matte for the waste grain-dissolve (reveal only).
    var maskImage: UIImage? = nil
    /// Contour fraction where the sticker's name label anchors.
    var labelAnchor: CGFloat? = nil

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
    /// Stamps keep light papers, so their internal ink stays dark even
    /// though the app's screen ink is light (dark-only album).
    private var markInk: Color {
        variant == .ink ? Color(red: 0.93, green: 0.90, blue: 0.84) : Theme.stampInk
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
                // Invisible in sticker form (paper 0.001) but still laid
                // out — it must not catch rename taps there.
                .allowsHitTesting(assembly.paper > 0.5)

            // ── Cancellation: rubber-stamped date, nothing more ─────
            if showsDateStamp {
                DateStamp(
                    date: date,
                    fontSize: 0.052 * w,
                    ink: variant == .ink
                        ? Color(red: 0.94, green: 0.52, blue: 0.42)
                        : Theme.postalRed
                )
                .blendMode(variant == .ink ? .normal : .multiply)
                .opacity(0.88)
                .scaleEffect(dateStampScale)
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
                .shadow(color: Theme.shadow.opacity(0.5), radius: 0.05 * w, y: 0.024 * w)
                .shadow(color: Theme.shadow.opacity(0.25), radius: 0.009 * w, y: 0.005 * w)

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
                        // Plain layer — the post-cut photo. Sits BELOW the
                        // wave layer: pre-cut, the wave layer's progress-0
                        // passthrough occludes it with identical pixels;
                        // during an interrupted cut the photo heals BEHIND
                        // the dying grains. 0.001 floor = pre-warm pattern.
                        rawView(raw, content: content)
                            .opacity(max(0.001, assembly.photoFade))
                        // Wave layer — the first cut's shatter, one-shot.
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
                                // Width bound: wind (≤48pt) + a cell, before
                                // the in-cell test kills anything farther.
                                maxSampleOffset: CGSize(width: 64, height: 180),
                                isEnabled: maskImage != nil
                            )
                            // Cull, never disable: isEnabled false would
                            // resurrect the photo unshaded. The shader is
                            // provably blank for waste < 0.03 (kept-pixel
                            // fade ends at progress 0.97, all waste dead by
                            // 0.903), so the discrete flip is invisible.
                            .opacity(maskImage == nil || assembly.waste >= 0.03 ? 1 : 0)
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
            .clipShape(RoundedRectangle(cornerRadius: content.width * 0.01))
            .offset(x: content.minX, y: content.minY)
    }

    @ViewBuilder
    private func finalContent(_ w: CGFloat, content: CGRect) -> some View {
        if style == .cutout, let image {
            let frame = stickerFrame(w, content: content, imageSize: image.size)

            // Contact shadow: arrives with the paper.
            Ellipse()
                .fill(Theme.shadow.opacity(0.28 * assembly.paper))
                .frame(width: frame.width * 0.62, height: 0.04 * w)
                .blur(radius: 0.018 * w)
                .position(x: frame.midX, y: frame.maxY - 0.004 * w)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: frame.width, height: frame.height)
                .rotationEffect(.degrees(
                    variant == .airmail ? -2.5 * assembly.settle : 0))
                .shadow(color: Theme.shadow.opacity(0.22 * assembly.paper),
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
        // Color glyphs (emoji) ignore foregroundStyle, so the contour
        // copies must be true silhouettes: white masked by the glyph
        // alpha, or an emoji title stacks as a smeared ring of 26 full-
        // color copies instead of a cut line.
        let ghost = base
            .foregroundStyle(.clear)
            .overlay(Color.white)
            .mask(base)
        let r = fontSize * 0.34

        return ZStack {
            ForEach(0..<16, id: \.self) { i in
                let a = Double(i) / 16 * 2 * .pi
                ghost.offset(x: cos(a) * r, y: sin(a) * r)
            }
            ForEach(0..<10, id: \.self) { i in
                let a = Double(i) / 10 * 2 * .pi + 0.3
                ghost.offset(x: cos(a) * r * 0.6, y: sin(a) * r * 0.6)
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
            showsDateStamp: stamp.kind == .stamp,
            labelAnchor: stamp.kind == .sticker ? stamp.labelAnchor : nil,
            assembly: stamp.kind == .sticker
                ? Assembly(paper: 0, caption: 0, content: .final)
                : .dressed
        )
    }
}
