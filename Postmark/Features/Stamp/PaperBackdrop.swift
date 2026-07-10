import SwiftUI

/// Paper that breathes (the 75her background, in Postmark's colors): a
/// near-imperceptible 3×3 mesh drifting between warm paper and a whisper of
/// postal red, finished with the paper-grain shader so the fill reads as
/// stock rather than a flat hex. Develop and reveal each mount their own
/// copy; the drift is a pure function of absolute time, so the two stay
/// pixel-identical through the phase handoff.
struct PaperBackdrop: View {
    var showsGrid = false
    var accent: Color = Theme.postalRed

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1 / 10, paused: reduceMotion)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate / 10
                let drift = Float(sin(t)) * 0.16
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.5 + drift * 0.5, 0.5 - drift * 0.4], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1],
                    ],
                    colors: meshColors(warmth: 0.05 + Double(drift) * 0.06)
                )
            }

            // Static grain pass multiplied over the drifting mesh — rendered
            // once and cached, so the mesh ticks never re-run the shader.
            Rectangle()
                .fill(.white)
                .colorEffect(ShaderLibrary.paperGrain(.float(0.31), .float(0.5)))
                .blendMode(.multiply)

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
        // Contain the grain's multiply blend within the backdrop.
        .compositingGroup()
    }

    private func meshColors(warmth: Double) -> [Color] {
        let breath = Theme.paper.mix(with: accent, by: warmth)
        let corner = Theme.paper.mix(with: accent, by: 0.035)
        return [
            corner, Theme.paper, Theme.paper,
            Theme.paper, breath, Theme.paper,
            Theme.paper, Theme.paper, corner,
        ]
    }
}
