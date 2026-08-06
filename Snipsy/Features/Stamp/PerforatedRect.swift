import SwiftUI

/// A postage-stamp outline: a rectangle with semicircular perforation notches
/// punched along every edge and a quarter notch at each corner. Fill it for
/// stamp paper; stroke it dashed for empty states.
struct PerforatedRect: Shape {
    /// The stock perforation. Named rather than inlined because the develop
    /// dissolve carves the same teeth in Metal (`insidePerforated`): the two
    /// have to be handed identical numbers or the silhouette the dust leaves
    /// won't be the one the reveal draws over it.
    static let defaultHoleRadiusFraction: CGFloat = 0.032
    static let defaultSpacingFactor: CGFloat = 2.9

    /// Perforation hole radius as a fraction of rect width.
    var holeRadiusFraction: CGFloat = defaultHoleRadiusFraction
    /// Target center-to-center spacing between holes, in hole radii.
    var spacingFactor: CGFloat = defaultSpacingFactor

    func path(in rect: CGRect) -> Path {
        let r = max(2, rect.width * holeRadiusFraction)
        var p = Path()

        func centers(_ length: CGFloat) -> [CGFloat] {
            let n = max(2, Int((length / (r * spacingFactor)).rounded()))
            let step = length / CGFloat(n)
            return (0...n).map { CGFloat($0) * step }
        }
        // Interior hole positions (corners handled separately).
        let xs = centers(rect.width).dropFirst().dropLast().map { rect.minX + $0 }
        let ys = centers(rect.height).dropFirst().dropLast().map { rect.minY + $0 }

        // Walk clockwise (screen sense) from just after the top-left corner.
        // All arcs sweep with decreasing angles (`clockwise: true`), which in
        // SwiftUI's y-down space bulges the notch into the rect.
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))

        for cx in xs {
            p.addLine(to: CGPoint(x: cx - r, y: rect.minY))
            p.addArc(center: CGPoint(x: cx, y: rect.minY), radius: r,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        }
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX, y: rect.minY), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)

        for cy in ys {
            p.addLine(to: CGPoint(x: rect.maxX, y: cy - r))
            p.addArc(center: CGPoint(x: rect.maxX, y: cy), radius: r,
                     startAngle: .degrees(270), endAngle: .degrees(90), clockwise: true)
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX, y: rect.maxY), radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(-180), clockwise: true)

        for cx in xs.reversed() {
            p.addLine(to: CGPoint(x: cx + r, y: rect.maxY))
            p.addArc(center: CGPoint(x: cx, y: rect.maxY), radius: r,
                     startAngle: .degrees(0), endAngle: .degrees(-180), clockwise: true)
        }
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX, y: rect.maxY), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)

        for cy in ys.reversed() {
            p.addLine(to: CGPoint(x: rect.minX, y: cy + r))
            p.addArc(center: CGPoint(x: rect.minX, y: cy), radius: r,
                     startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        }
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX, y: rect.minY), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)

        p.closeSubpath()
        return p
    }
}
