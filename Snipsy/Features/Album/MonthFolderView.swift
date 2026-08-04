import SwiftUI

// MARK: - Geometry

// MARK: - Geometry

/// Every measurement of the folder object, as a fraction of its width, so
/// the whole thing scales from a shelf row to a hero without re-tuning.
/// The numbers are read off the reference object; the comments say which
/// ones are measured and which are the two coupled tuning knobs.
/// A direct port of the reference implementation, whose CSS is the source
/// of truth here rather than anything measured off a screenshot:
///
///     .archive-container { perspective: 1200px; width: 320px; height: 400px }
///     .folder-front { transform-origin: left center; border-radius: 28px;
///                     background: rgba(tint, .75); backdrop-filter: blur(20px) }
///     .is-open .folder-front { transform: rotateY(-60deg); z-index: 1 }
///     .stamp { width: 176px; height: 240px }            /* centred at rest */
///     .is-open .stamp-1 { translate(280px,-40px) rotate(2deg);  z-index: 50 }
///     .is-open .stamp-2 { translate(120px, 40px) rotate(-2deg); z-index: 45 }
///     transition: .7s cubic-bezier(.23,1,.32,1)
///
/// Everything below is those numbers divided by 320 (width) or 400 (height).
enum FolderGeometry {
    /// 400 ÷ 320.
    static let aspect: CGFloat = 1.25
    /// 28 ÷ 320 — equal on all four corners, as the reference has it.
    static let corner: CGFloat = 0.0875

    /// rotateY(-60deg) about `transform-origin: left center`.
    ///
    /// It stops well short of 90°, which is the whole reason the reference
    /// never needs a backface rule: you are always looking at the front of
    /// the cover. An earlier pass here swung past 90° and then mirrored the
    /// face back to keep the label readable — which is exactly why the
    /// label was appearing on the *back* of the cover. Deleted.
    static let openAngle: Double = -60
    /// The reference's lighter hover state, kept for tuning.
    static let previewAngle: Double = -25

    /// How tall the free edge stands once open, as a multiple of the shut
    /// height — 1200/(1200 − 320·sin60°). The row has to reserve half of
    /// the excess at each end or the scroll view clips the cover.
    static let openMagnification: CGFloat = 1.30

    /// CSS `perspective: 1200px` on a 320px-wide element. Calibrated by
    /// rendering the transform and measuring: at this value the hinge edge
    /// holds 1.000 H and the free edge magnifies to 1.304 H — which is the
    /// 1200/(1200 - 320·sin60°) = 1.30 the browser computes.
    static let perspective: CGFloat = 0.34

    /// 176 ÷ 320 and 240 ÷ 400. The stamps sit centred and fully covered
    /// when shut; the folder shows nothing but its own face.
    static let stampWidth: CGFloat = 0.55       // × width
    static let stampHeight: CGFloat = 0.60      // × height

    /// translate(280,-40) and translate(120,40), over 320 × 400.
    static let fanOut: [CGSize] = [
        CGSize(width: 0.875, height: -0.10),
        CGSize(width: 0.375, height:  0.10),
    ]
    /// rotate(2deg) / rotate(-2deg).
    static let fanTilt: [Double] = [2, -2]

    static let maxPreview = 2

    /// 0.7s cubic-bezier(.23,1,.32,1) — a hard ease-out that glides to a
    /// stop. Deliberately not a spring: the reference does not bounce.
    static let curve = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.7)

    /// How far right of the folder's own centre the fan reaches, so the
    /// shelf row can guarantee it never clips.
    static func fanExtent(width: CGFloat) -> CGFloat {
        width * (fanOut.map(\.width).max()! + stampWidth / 2)
    }

    /// Total width the object occupies once fanned. The view must CLAIM
    /// this, not just draw into it: SwiftUI happily renders a child offset
    /// beyond its parent's frame, but will not hit-test it there — which
    /// left the fanned stamps visible and untappable, so taps on them fell
    /// through to the row and shut the folder instead of opening it.
    static func rowWidth(_ width: CGFloat) -> CGFloat {
        width * 0.5 + fanExtent(width: width)
    }

    /// Where the open cover's far edge falls, as a fraction of the folder's
    /// width — measured off the rendered transform (0.655 W at -60° with
    /// perspective 0.34). Left of this you are touching the cover; right of
    /// it you are touching what came out of the pocket.
    ///
    /// The shelf decides between "close" and "go inside" from the tap's x
    /// against this, rather than from a gesture attached to each slip. The
    /// slips are offset outside the folder's own frame, and hanging a
    /// competing gesture off a descendant of an already-nested tap pair is
    /// how the stamp tap ended up shutting the folder instead.
    static let openCoverExtent: CGFloat = 0.655
}

// MARK: - Stock

/// The folder's board. A curated cycle, indexed by position on the shelf —
/// deliberately not derived from content, so the shelf always reads as a
/// designed set of objects.
///
/// Every stock is pitched light enough to take BLACK ink. Cream-on-colour
/// looked washed out on the gold, and a label you have to squint at is not
/// a label. `pocket` is a full step darker than `deep`, because the back
/// board and the cover being the same colour was what collapsed the whole
/// object into one flat shape.
struct FolderStock: Equatable {
    var hi: Color
    var base: Color
    var deep: Color
    var pocket: Color

    var ink: Color { Color(hex: 0x1E1B16).opacity(0.92) }
    var inkSoft: Color { Color(hex: 0x1E1B16).opacity(0.58) }

    static let cycle: [FolderStock] = [
        FolderStock(0xF0CE72, 0xE2B44E, 0xC1922F, 0x8F6B1E), // ochre
        FolderStock(0xE87FBE, 0xD75FA8, 0xB33F86, 0x7E2A5D), // magenta
        FolderStock(0xB9BCC4, 0x9DA2AC, 0x7C828E, 0x545A65), // slate
        FolderStock(0xF29B84, 0xE87B60, 0xC65A41, 0x8E3C29), // coral
        FolderStock(0xA9C6A0, 0x8CB081, 0x6C8F62, 0x4A6642), // sage
        FolderStock(0x9FC2E0, 0x7FA9CE, 0x5F87AC, 0x40607E), // sky
    ]

    static func stock(at index: Int) -> FolderStock {
        cycle[((index % cycle.count) + cycle.count) % cycle.count]
    }

    private init(_ hi: UInt32, _ base: UInt32, _ deep: UInt32, _ pocket: UInt32) {
        self.hi = Color(hex: hi)
        self.base = Color(hex: base)
        self.deep = Color(hex: deep)
        self.pocket = Color(hex: pocket)
    }
}

// MARK: - Folder

/// A month of the collection as a physical object: a back board with the
/// month's stamps seated in it, and a front cover hinged along the spine.
///
/// Shut, the cover lies over the pocket and the top stamp's corner shows
/// past the board's right edge. Tapped, the cover swings back on the spine —
/// which stays exactly where it is, because that is what a hinge does — and
/// uncovers the pocket, letting the stamps come out to the right.
///
/// Everything animates off the single `open` value; there are no internal
/// animations to fall out of step with the caller's spring.
struct MonthFolderView: View {
    let folder: MonthFolder
    let store: StampStore
    let stock: FolderStock
    /// 0 = shut, 1 = cover swung back with the stamps out. Animated.
    var open: CGFloat
    var width: CGFloat

    private var height: CGFloat { width * FolderGeometry.aspect }
    /// Clamped, for anything that must not overshoot.
    private var p: CGFloat { min(max(open, 0), 1) }

    private var board: RoundedRectangle {
        RoundedRectangle(cornerRadius: width * FolderGeometry.corner,
                         style: .continuous)
    }

    var body: some View {
        ZStack {
            pocketBoard.zIndex(0)
            slips.zIndex(2)
            // The cover stays in FRONT, always.
            //
            // The reference drops it behind on open (`z-index: 1`), and the
            // near stamp lands back over the cover's footprint — so it ends
            // up painted on top of the flap, which reads as a stamp lying
            // ON the folder rather than coming out of it. Physically the
            // cover's free edge is the nearest thing in the object, so it
            // has to occlude. Keeping it in front also puts the overlap
            // behind the glass, where it belongs: the stamp shows through,
            // tinted and soft, as it slides clear.
            frontCover.zIndex(3)
        }
        .frame(width: width, height: height)
        // Claim the fan's full span, anchored so the folder itself does not
        // move. Without this the slips render outside the frame and are not
        // tappable. Never clip.
        .frame(width: FolderGeometry.rowWidth(width), height: height,
               alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: Pocket board

    /// `.folder-back { box-shadow: 0 10px 40px rgba(0,0,0,0.1) }`.
    /// A CSS blur radius is about twice SwiftUI's, so 40px → radius 20.
    private var pocketBoard: some View {
        board
            .fill(LinearGradient(colors: [stock.base, stock.deep],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: height)
            .shadow(color: Theme.shadow.opacity(0.10), radius: 20, y: 10)
    }

    // MARK: Slips

    private var previews: [Stamp] {
        Array(folder.stamps.prefix(FolderGeometry.maxPreview))
    }

    private var slips: some View {
        let previewCount = previews.count
        return ZStack {
            ForEach(Array(previews.indices), id: \.self) { index in
                let stamp = previews[index]
                return slip(stamp, index: index)
                    .zIndex(Double(previewCount - index))
            }
        }
    }

    /// One `.stamp`: centred and hidden when shut, translated out when open.
    /// Every number is hoisted out and explicitly typed — left inline in the
    /// modifier chain, the mixed CGFloat/Double arithmetic blows the type
    /// checker's budget.
    @ViewBuilder
    private func slip(_ stamp: Stamp, index i: Int) -> some View {
        let wobble = FolderWobble(stamp.id)
        let t: CGFloat = p

        // Sized off the width, so mixed artifact kinds all seat the same way
        // in the pocket instead of each claiming its own height.
        let slipWidth: CGFloat =
            width * FolderGeometry.stampWidth * (0.97 + 0.06 * wobble.size)

        let out = FolderGeometry.fanOut[min(i, FolderGeometry.fanOut.count - 1)]
        let x: CGFloat = width * out.width * t
        let y: CGFloat = height * out.height * t
        // The reference's fixed 2°/-2°, nudged per stamp so a shelf full of
        // folders never looks stamped from one die.
        let tilt = FolderGeometry.fanTilt[min(i, FolderGeometry.fanTilt.count - 1)]
        let angle = Double(t) * (tilt + Double(wobble.tilt) * 1.6)

        // `backdrop-filter: blur(20px)` on a 320px folder. Shut, the stamps
        // sit right behind the pane, so this is what you actually see
        // through it — a soft bloom of what's inside. Relying on the
        // material alone left them invisible: a 0.75 tint over a light
        // material leaves too little of a pale stamp to register.
        let bloom: CGFloat = (1 - t) * width * 0.0625

        // `.stamp { filter: drop-shadow(0 4px 12px rgba(0,0,0,.08)) }` going
        // to `drop-shadow(15px 15px 30px rgba(0,0,0,.1))` when open.
        // The reference animates the blur too (12→30px); we hold it at the
        // midpoint because animating a shadow's radius re-rasterises the
        // layer every frame — most of why the fan felt rough. Offset and
        // opacity are nearly free, so those still travel.
        let shadowAlpha = 0.08 + 0.02 * Double(t)
        let shadowOffset: CGFloat = 4 + 11 * t

        ArtifactView(stamp: stamp, image: store.thumbnail(for: stamp))
            .frame(width: slipWidth)
            .rotationEffect(.degrees(angle))
            .shadow(color: Theme.shadow.opacity(shadowAlpha),
                    radius: 11, x: shadowOffset, y: shadowOffset)
            .offset(x: x, y: y)
            .blur(radius: bloom)
    }

    // MARK: Front cover

    /// `transform-origin: left center` + `rotateY(-60deg)`. No slide, no
    /// backface rule — it never turns far enough to show one.
    private var frontCover: some View {
        let angle = FolderGeometry.openAngle * Double(open)
        return coverFace
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                anchorZ: 0,
                perspective: FolderGeometry.perspective
            )
    }

    /// `background: rgba(tint, .75)` over `backdrop-filter: blur(20px)`.
    ///
    /// The tint has to stay translucent for any of this to be visible. A
    /// previous pass laid an 80%-opaque gradient over the glass, which
    /// meant the glass was doing nothing whatsoever — hence "where is the
    /// glass effect". Nothing opaque goes on top of it now.
    private var coverFace: some View {
        board
            // The reference sits at .75, but its stamps are saturated blue
            // and cream against a dark folder. Ours are photographs on a
            // light stock, so the pane opens up further to let them read.
            .fill(stock.base.opacity(0.5))
            .background { board.fill(.ultraThinMaterial) }
            .overlay { board.fill(sheen) }
            .overlay { board.fill(turnShade) }
            .overlay(alignment: .bottomLeading) { label }
            // `box-shadow: inset 0 1px 1px rgba(255,255,255,.2)` — an INSET
            // highlight catching the top edge, not a drop shadow …
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.20), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 2)
            }
            // … and `border: 1px solid rgba(255,255,255,.15)`. Those two
            // rules are the whole reason the pane reads as separate glass.
            .overlay { board.strokeBorder(.white.opacity(0.15), lineWidth: 1) }
            .clipShape(board)
            .frame(width: width, height: height)
            // No drop shadow: `.folder-front` has none. Its separation comes
            // from the inset highlight and border above. Adding one made the
            // pane read as a card floating off the folder.
    }

    /// The inset top highlight, spread into a soft sheen across the pane.
    private var sheen: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.26), location: 0),
                .init(color: .white.opacity(0.06), location: 0.34),
                .init(color: .clear,               location: 0.72),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// Turning off the light, the pane darkens toward its free edge.
    private var turnShade: LinearGradient {
        LinearGradient(
            colors: [.clear, Theme.shadow.opacity(0.22 * Double(p))],
            startPoint: .leading, endPoint: .trailing
        )
    }

    /// The written label: month, year and count over two ruled lines. The
    /// folder is its own month header, so the shelf needs no chrome beside
    /// it.
    private var label: some View {
        let rowGap: CGFloat = height * 0.018
        // `padding: 30px` on a 320 box; `.label-sub { margin-bottom: 24px }`;
        // `.lines { margin-top: 8px }`.
        let inset: CGFloat = width * 0.094
        let ruleGap: CGFloat = height * 0.060
        let lineGap: CGFloat = height * 0.020

        return VStack(alignment: .leading, spacing: rowGap) {
            // The reference sets 24px/14px on a 320px folder. At shelf size
            // that lands under 8pt, so type is pitched up relative to the
            // object — the one place this deliberately departs from it.
            Text(folder.name)
                .font(Theme.display(width * 0.125))
                .foregroundStyle(stock.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("\(folder.year)  ·  \(folder.countLine)")
                .font(Theme.ui(width * 0.062, .semibold))
                .foregroundStyle(stock.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer().frame(height: ruleGap)

            VStack(spacing: lineGap) {
                ForEach(0..<2, id: \.self) { _ in
                    Rectangle()
                        .fill(stock.ink.opacity(0.20))
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, inset)
        .padding(.bottom, inset)
    }
}

// MARK: - Wobble

/// Deterministic per-stamp variation, seeded from the stamp's id — a stamp
/// always sits at the same angle, so the fan never reshuffles between
/// renders or across launches.
private struct FolderWobble {
    /// All in -1…1.
    let tilt: CGFloat
    let lift: CGFloat
    let size: CGFloat

    init(_ id: UUID) {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes { h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        }
        func next() -> CGFloat {
            h = (h ^ (h >> 33)) &* 0xff51_afd7_ed55_8ccd
            return CGFloat(Double(h >> 40) / Double(1 << 24)) * 2 - 1
        }
        tilt = next()
        lift = next()
        size = next()
    }
}
