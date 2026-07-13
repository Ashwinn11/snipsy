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

/// Bottom-left collection entry: last stamp as a mini thumb + live count.
struct CollectionPill: View {
    let model: AppModel
    @State private var bounce = false

    var body: some View {
        Button {
            model.haptics.tick()
            withAnimation(Theme.spring) { model.showAlbum = true }
        } label: {
            HStack(spacing: 9) {
                if let last = model.store.stamps.first,
                   let image = model.store.image(for: last) {
                    MiniStampThumb(image: image, tint: last.tint.color)
                } else {
                    Image(systemName: "seal")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Text("\(model.store.stamps.count)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 15)
            .frame(height: 48)
        }
        // Fixed scrim, not glass — see CameraScreen: glass refracts the
        // live feed, so the pill would flicker with every exposure change.
        .background(.black.opacity(0.32), in: Capsule())
        .scaleEffect(bounce ? 1.14 : 1)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            model.pillFrame = frame
        }
        .onChange(of: model.pillBump) {
            withAnimation(Theme.springTight) { bounce = true }
            withAnimation(Theme.springBouncy.delay(0.14)) { bounce = false }
            withAnimation(Theme.spring) {
                // count text transition rides the numericText content transition
            }
        }
    }
}

/// A tiny perforated stamp used inside the pill.
struct MiniStampThumb: View {
    let image: UIImage
    let tint: Color

    var body: some View {
        ZStack {
            PerforatedRect(holeRadiusFraction: 0.09, spacingFactor: 2.6)
                .fill(tint)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(3.5)
        }
        .frame(width: 25, height: 31)
    }
}
