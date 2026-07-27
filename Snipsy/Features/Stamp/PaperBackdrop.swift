import SwiftUI

/// The page: a flat warm off-white, given tooth by the fine-grain shader so
/// it reads as stock rather than as a hex value.
///
/// This used to be a drifting 3×3 mesh gradient. It was doing the work of a
/// background *and* of a subject, and on a page whose whole job is to hold
/// stamps and folders, that is one subject too many — so it is gone, along
/// with the per-frame TimelineView tick it cost every mounted copy.
struct PaperBackdrop: View {
    var showsGrid = false

    var body: some View {
        ZStack {
            Theme.paper
                .colorEffect(ShaderLibrary.fineGrain(.float(0.03)))

            if showsGrid {
                Canvas(opaque: false, rendersAsynchronously: true) { ctx, size in
                    let spacing: CGFloat = 26
                    let dot = CGSize(width: 2.2, height: 2.2)
                    var y: CGFloat = spacing / 2
                    while y < size.height {
                        var x: CGFloat = spacing / 2
                        while x < size.width {
                            ctx.fill(
                                Path(ellipseIn: CGRect(origin: CGPoint(x: x, y: y), size: dot)),
                                with: .color(Theme.ink.opacity(0.06))
                            )
                            x += spacing
                        }
                        y += spacing
                    }
                }
            }

            // Barely-there vignette so a flat sheet still has a centre.
            RadialGradient(
                colors: [.clear, Theme.shadow.opacity(0.055)],
                center: .center, startRadius: 240, endRadius: 660
            )
        }
    }
}
