import SwiftUI

/// Simulator stand-in for the live camera: bundled scenes with a slow Ken
/// Burns drift (a pure function of time, so capture geometry is exact) and a
/// horizontal swipe to change scenes.
struct DemoFeedView: View {
    let feed: DemoFeed
    let size: CGSize

    var body: some View {
        TimelineView(.animation) { timeline in
            let drift = feed.drift(at: timeline.date)
            ZStack {
                if let sample = feed.current {
                    Image(uiImage: sample.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(drift.scale)
                        .offset(x: drift.offset.x, y: drift.offset.y)
                        .id(sample.id)
                        .transition(.opacity.combined(with: .scale(scale: 1.05)))
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > 50 else { return }
                    withAnimation(.easeInOut(duration: 0.45)) {
                        feed.advance(value.translation.width < 0 ? 1 : -1)
                    }
                }
        )
    }
}
