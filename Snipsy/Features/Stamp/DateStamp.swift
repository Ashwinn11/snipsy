import SwiftUI

/// The cancellation: a bare rubber-stamped date — no roundel, no branding.
/// Red ink, eroded by the inkBleed shader so it prints like a real hand
/// stamp.
struct DateStamp: View {
    var date: Date
    var fontSize: CGFloat
    var ink: Color = Theme.postalRed
    var seed: Double = 0.42

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    var body: some View {
        Text(Self.formatter.string(from: date).uppercased())
            .font(.system(size: fontSize, weight: .bold, design: .serif))
            .kerning(fontSize * 0.14)
            .foregroundStyle(ink)
            .padding(fontSize * 0.3)
            .colorEffect(ShaderLibrary.inkBleed(.float(seed)))
    }
}
