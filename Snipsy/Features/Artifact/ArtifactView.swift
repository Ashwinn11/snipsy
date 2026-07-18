import SwiftUI

/// The one static render for any collected artifact — album cells, the
/// detail card, share flattens, and Messages drawer copies all switch on
/// kind here instead of constructing StampView directly.
struct ArtifactView: View {
    let stamp: Stamp
    let image: UIImage?

    var body: some View {
        switch stamp.kind {
        case .stamp, .sticker:
            StampView(stamp: stamp, image: image)
        case .polaroid:
            PolaroidView(image: image, title: stamp.title, date: stamp.date)
        case .card:
            CardView(image: image, title: stamp.title, date: stamp.date)
        case .canvas:
            FlattenedCanvas(image: image,
                            aspect: stamp.canvas?.aspect ?? CardView.aspect)
        }
    }
}

/// A saved composition's preview — the flatten already baked in its
/// background stock, so this only frames the pixels.
struct FlattenedCanvas: View {
    let image: UIImage?
    var aspect: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .shadow(color: Theme.shadow.opacity(0.22), radius: 8, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.paperDeep)
            }
        }
        .aspectRatio(1 / aspect, contentMode: .fit)
    }
}
