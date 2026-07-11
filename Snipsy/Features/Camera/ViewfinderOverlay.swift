import SwiftUI

/// Corner brackets + a faint perforation-dot outline: the stamp metaphor,
/// foreshadowed. Breathes almost imperceptibly.
struct ViewfinderOverlay: View {
    let rect: CGRect
    @State private var breathing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    .white.opacity(0.30),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [0.1, 7.5])
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            CornerBrackets(cornerRadius: 12, arm: 22)
                .stroke(.white.opacity(0.95),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
        .scaleEffect(breathing ? 1.005 : 0.997)
        .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true),
                   value: breathing)
        .allowsHitTesting(false)
        .onAppear { breathing = true }
    }
}

/// Four L-shaped brackets with rounded outer corners.
struct CornerBrackets: Shape {
    var cornerRadius: CGFloat
    var arm: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = cornerRadius
        let a = arm

        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r + a))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r + a, y: rect.minY))

        // Top-right
        p.move(to: CGPoint(x: rect.maxX - r - a, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r + a))

        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - r - a))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX - r - a, y: rect.maxY))

        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + r + a, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r - a))

        return p
    }
}
