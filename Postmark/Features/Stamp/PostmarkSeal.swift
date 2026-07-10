import SwiftUI

/// The circular cancellation mark: double ring, arc text, date, wavy killer
/// bars. Drawn in Canvas; ink is eroded by the inkBleed shader so it prints
/// like real cancellation ink. Canvas aspect is 2:1 — circle on the left,
/// bars sweeping right.
struct PostmarkSeal: View {
    var date: Date
    var seed: Double = 0.37

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()
    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let d = size.height
            let center = CGPoint(x: d / 2, y: d / 2)
            let ink = Theme.ink

            // Rings
            let outer = CGRect(x: d * 0.012, y: d * 0.012,
                               width: d * 0.976, height: d * 0.976)
            ctx.stroke(Path(ellipseIn: outer), with: .color(ink), lineWidth: d * 0.024)
            ctx.stroke(Path(ellipseIn: outer.insetBy(dx: d * 0.062, dy: d * 0.062)),
                       with: .color(ink), lineWidth: d * 0.012)

            // Arc text
            arcText(ctx, "POSTMARK", center: center, radius: d * 0.365,
                    centerAngle: -.pi / 2, spread: 1.9, fontSize: d * 0.102, flipped: false)
            arcText(ctx, "COLLECTED", center: center, radius: d * 0.365,
                    centerAngle: .pi / 2, spread: 1.9, fontSize: d * 0.102, flipped: true)

            // Side stars
            for sx: CGFloat in [-1, 1] {
                ctx.draw(
                    Text("✦").font(.system(size: d * 0.09)).foregroundColor(ink),
                    at: CGPoint(x: center.x + sx * d * 0.375, y: center.y)
                )
            }

            // Center date
            ctx.draw(
                Text(Self.dayFormatter.string(from: date).uppercased())
                    .font(.system(size: d * 0.148, weight: .bold, design: .serif))
                    .foregroundColor(ink),
                at: CGPoint(x: center.x, y: center.y - d * 0.075)
            )
            ctx.draw(
                Text(Self.yearFormatter.string(from: date))
                    .font(.system(size: d * 0.125, weight: .semibold, design: .serif))
                    .foregroundColor(ink),
                at: CGPoint(x: center.x, y: center.y + d * 0.095)
            )

            // Killer bars
            let barStart = d * 1.03
            let barEnd = size.width - d * 0.03
            for (i, dy) in [-0.195, -0.065, 0.065, 0.195].enumerated() {
                var bar = Path()
                let y0 = center.y + CGFloat(dy) * d
                let amp = d * 0.028
                let wavelength = d * 0.38
                let phase = CGFloat(i) * 1.4
                bar.move(to: CGPoint(x: barStart, y: y0 + amp * sin(phase)))
                var x = barStart
                while x < barEnd {
                    x += 3
                    bar.addLine(to: CGPoint(
                        x: x, y: y0 + amp * sin((x - barStart) / wavelength * 2 * .pi + phase)
                    ))
                }
                ctx.stroke(bar, with: .color(ink),
                           style: StrokeStyle(lineWidth: d * 0.035, lineCap: .round))
            }
        }
        .colorEffect(ShaderLibrary.inkBleed(.float(seed)))
        .aspectRatio(2, contentMode: .fit)
    }

    private func arcText(
        _ ctx: GraphicsContext, _ string: String, center: CGPoint, radius: CGFloat,
        centerAngle: CGFloat, spread: CGFloat, fontSize: CGFloat, flipped: Bool
    ) {
        let chars = Array(string)
        guard chars.count > 1 else { return }
        let step = spread / CGFloat(chars.count - 1)
        for (i, ch) in chars.enumerated() {
            let t = CGFloat(i) - CGFloat(chars.count - 1) / 2
            let angle = flipped ? centerAngle - t * step : centerAngle + t * step
            let pos = CGPoint(x: center.x + radius * cos(angle),
                              y: center.y + radius * sin(angle))
            ctx.drawLayer { layer in
                layer.translateBy(x: pos.x, y: pos.y)
                layer.rotate(by: Angle(radians: flipped ? angle - .pi / 2 : angle + .pi / 2))
                layer.draw(
                    Text(String(ch))
                        .font(.system(size: fontSize, weight: .bold, design: .serif))
                        .foregroundColor(Theme.ink),
                    at: .zero
                )
            }
        }
    }
}
