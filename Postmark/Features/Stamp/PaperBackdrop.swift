import SwiftUI

/// The album-world background: warm paper with tooth, a faint dot grid, and a
/// soft edge vignette. Used by develop, reveal, and album screens.
struct PaperBackdrop: View {
    var showsGrid = true

    var body: some View {
        ZStack {
            Theme.paper
                .colorEffect(ShaderLibrary.paperGrain(.float(0.31), .float(0.55)))

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
                                with: .color(Theme.ink.opacity(0.05))
                            )
                            x += spacing
                        }
                        y += spacing
                    }
                }
            }

            // Soft vignette keeps focus centered without reading as "effect".
            RadialGradient(
                colors: [.clear, Theme.ink.opacity(0.055)],
                center: .center, startRadius: 220, endRadius: 640
            )
        }
        .ignoresSafeArea()
    }
}
