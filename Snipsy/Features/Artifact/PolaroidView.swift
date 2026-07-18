import SwiftUI

/// An instant photo: warm-white frame, near-square window, the thick
/// bottom band carrying a handwritten caption. Aspect 1.22 (height/width).
///
/// Geometry (relative to width W; total height = 1.22 W):
///   window: x 0.06W, y 0.06W, w 0.88W, h 0.89W
///   band:   y 0.95W → 1.22W (the caption strip)
///
/// The grain shader rides the frame shape only — the caption (a live
/// TextField while renaming) never sits under a shader modifier.
struct PolaroidView: View {

    var image: UIImage?
    var title: String
    var date: Date = .now
    /// One-shot develop beat: photo prints at 65% and rises to full.
    var develop: Double = 1
    /// Caption presence (reveal choreography drives it in).
    var appear: Double = 1

    var editableTitle: Binding<String>? = nil
    var titleFocused: FocusState<Bool>.Binding? = nil
    var onSubmitTitle: () -> Void = {}
    var onTapCaption: (() -> Void)? = nil

    static let aspect: CGFloat = 1.22

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                PolaroidStock(showsRecess: image == nil)
                photo(w)
                caption(w)
            }
        }
        .aspectRatio(1 / Self.aspect, contentMode: .fit)
    }

    private func windowRect(_ w: CGFloat) -> CGRect {
        CGRect(x: 0.06 * w, y: 0.06 * w, width: 0.88 * w, height: 0.89 * w)
    }

    @ViewBuilder
    private func photo(_ w: CGFloat) -> some View {
        let window = windowRect(w)
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: window.width, height: window.height)
                .clipped()
                .opacity(0.65 + 0.35 * min(1, max(0, develop)))
                .overlay(
                    // Top inner shade — the print sitting behind the frame.
                    LinearGradient(
                        colors: [Theme.shadow.opacity(0.14), .clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.06))
                )
                .overlay(
                    Rectangle()
                        .strokeBorder(Theme.shadow.opacity(0.10), lineWidth: 1)
                )
                .offset(x: window.minX, y: window.minY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func caption(_ w: CGFloat) -> some View {
        let bandMidY = 1.085 * w
        Group {
            if let binding = editableTitle {
                TextField("name it", text: binding)
                    .font(Theme.handwritten(0.075 * w))
                    .foregroundStyle(Theme.stampInk.opacity(0.78))
                    .tint(Theme.postalRed)
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(onSubmitTitle)
                    .frame(width: 0.74 * w)
                    .modifier(FocusedIfAvailable(focus: titleFocused))
            } else {
                Text(title.isEmpty ? "name it" : title)
                    .font(Theme.handwritten(0.075 * w))
                    .foregroundStyle(Theme.stampInk.opacity(
                        title.isEmpty ? 0.35 : 0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: 0.74 * w)
                    .overlay(alignment: .bottom) {
                        Line()
                            .stroke(Theme.stampInk.opacity(
                                onTapCaption == nil ? 0 : 0.30 * appear),
                                    style: StrokeStyle(lineWidth: 1, dash: [2.5, 3]))
                            .frame(height: 1)
                            .offset(y: 0.02 * w)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onTapCaption?() }
                    // No rename handler ⇒ fully transparent to taps — a
                    // no-op gesture must not swallow chooser-thumb hits.
                    .allowsHitTesting(onTapCaption != nil)
            }
        }
        .rotationEffect(.degrees(-2))
        .position(x: 0.5 * w, y: bandMidY)
        .opacity(appear)

        Text(Self.struckDate.string(from: date))
            .font(Theme.handwritten(0.034 * w))
            .foregroundStyle(Theme.stampInk.opacity(0.40))
            .rotationEffect(.degrees(-2))
            .position(x: 0.82 * w, y: 1.175 * w)
            .opacity(appear)
            .allowsHitTesting(false)
    }

    private static let struckDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        return f
    }()
}

/// The bare polaroid frame — also the canvas editor's polaroid background
/// stock (layers render over an empty window recess).
struct PolaroidStock: View {
    var showsRecess: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 0.008 * w)
                    .fill(Color(hex: 0xFDFBF4))
                    .colorEffect(ShaderLibrary.paperGrain(.float(0.31), .float(0.34)))
                    .shadow(color: Theme.shadow.opacity(0.28), radius: 0.045 * w, y: 0.022 * w)
                    .shadow(color: Theme.shadow.opacity(0.14), radius: 0.008 * w, y: 0.004 * w)

                // Empty window reads as the unexposed print.
                if showsRecess {
                    Rectangle()
                        .fill(Color(hex: 0xE9E4D8))
                        .overlay(
                            Rectangle()
                                .strokeBorder(Theme.shadow.opacity(0.10), lineWidth: 1)
                        )
                        .frame(width: 0.88 * w, height: 0.89 * w)
                        .offset(x: 0.06 * w, y: 0.06 * w)
                }
            }
        }
        .aspectRatio(1 / PolaroidView.aspect, contentMode: .fit)
    }
}
