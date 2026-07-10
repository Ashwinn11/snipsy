import SwiftUI

/// The collector's book: serif day headers, a two-column grid of slightly
/// tilted stamps on dot-grid paper, matched-geometry morph into detail.
struct AlbumScreen: View {
    let model: AppModel

    @Namespace private var ns
    @State private var selected: Stamp? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PaperBackdrop()

                VStack(spacing: 0) {
                    header(topInset: geo.safeAreaInsets.top)
                    if model.store.stamps.isEmpty {
                        EmptyAlbumView()
                            .frame(maxHeight: .infinity)
                    } else {
                        grid(bottomInset: geo.safeAreaInsets.bottom)
                    }
                }

                if let stamp = selected {
                    StampDetailView(
                        stamp: stamp,
                        model: model,
                        ns: ns,
                        screenSize: geo.size,
                        onClose: {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                selected = nil
                            }
                        }
                    )
                    .zIndex(5)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    private func header(topInset: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Collection")
                    .font(Theme.serifDisplay(34))
                    .foregroundStyle(Theme.ink)
                Text(countLine)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Button {
                model.haptics.tick()
                withAnimation(Theme.spring) { model.showAlbum = false }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 42, height: 42)
            }
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .padding(.horizontal, 26)
        .padding(.top, max(topInset, 18) + 14)
        .padding(.bottom, 20)
    }

    private var countLine: String {
        let n = model.store.stamps.count
        return n == 1 ? "1 stamp" : "\(n) stamps"
    }

    // MARK: Grid

    private func grid(bottomInset: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 34) {
                ForEach(model.store.dayGroups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(group.title)
                                .font(Theme.engraved(21))
                                .foregroundStyle(Theme.ink.opacity(0.8))
                            Text(group.stamps.count == 1 ? "1 stamp" : "\(group.stamps.count) stamps")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.inkSoft)
                        }

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 24),
                                GridItem(.flexible(), spacing: 24),
                            ],
                            spacing: 30
                        ) {
                            ForEach(Array(group.stamps.enumerated()), id: \.element.id) { i, stamp in
                                cell(stamp, index: i)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 4)
            .padding(.bottom, bottomInset + 36)
        }
    }

    private func cell(_ stamp: Stamp, index: Int) -> some View {
        Button {
            model.haptics.tick()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                selected = stamp
            }
        } label: {
            StampView(stamp: stamp, image: model.store.image(for: stamp))
                .rotationEffect(.degrees(index.isMultiple(of: 2) ? -1.3 : 1.4))
        }
        .buttonStyle(PressableButtonStyle())
        .matchedGeometryEffect(id: stamp.id, in: ns, isSource: selected?.id != stamp.id)
        .opacity(selected?.id == stamp.id ? 0 : 1)
        .modifier(StaggeredAppear(index: index))
    }
}

/// Cells drift up and fade in, staggered by grid position.
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .onAppear {
                withAnimation(Theme.spring.delay(Double(index % 8) * 0.05)) {
                    shown = true
                }
            }
    }
}

/// A dotted stamp outline inviting the first capture.
struct EmptyAlbumView: View {
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 22) {
            PerforatedRect()
                .stroke(Theme.inkSoft.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.4, dash: [4, 5]))
                .frame(width: 132, height: 173)
                .overlay {
                    Image(systemName: "camera")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.inkSoft.opacity(0.8))
                }
                .scaleEffect(breathe ? 1.03 : 0.99)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                           value: breathe)
                .onAppear { breathe = true }

            VStack(spacing: 7) {
                Text("Your first stamp awaits")
                    .font(Theme.serifDisplay(21))
                    .foregroundStyle(Theme.ink)
                Text("Frame something you love and press the shutter.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.bottom, 70)
    }
}
