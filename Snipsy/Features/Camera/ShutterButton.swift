import SwiftUI

/// White ring, postal-red disc, and a slowly revolving perforation ring —
/// pressing it feels like inking a rubber stamp.
struct ShutterButton: View {
    var action: () -> Void

    @State private var pressed = false
    @State private var revolve = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.95), lineWidth: 4)
                .frame(width: 78, height: 78)

            Circle()
                .fill(Theme.postalRed)
                .frame(width: 62, height: 62)
                .overlay {
                    Circle()
                        .strokeBorder(
                            .white.opacity(0.75),
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [0.1, 6.4])
                        )
                        .frame(width: 46, height: 46)
                        .rotationEffect(.degrees(revolve ? 360 : 0))
                        .animation(.linear(duration: 46).repeatForever(autoreverses: false),
                                   value: revolve)
                }
                .scaleEffect(pressed ? 0.84 : 1)
                .animation(Theme.springTight, value: pressed)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in
                    pressed = false
                    action()
                }
        )
        .onAppear { revolve = true }
    }
}

