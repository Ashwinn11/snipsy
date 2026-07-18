import SwiftUI

/// A plain scrapbook card: cream stock, even photo margin, engraved
/// caption. Aspect 1.30 (height/width).
///
/// Geometry (relative to width W; total height = 1.30 W):
///   photo: x 0.07W, y 0.07W, w 0.86W, h 1.04W
///   caption line: centered at y ≈ 1.205W
struct CardView: View {

    var image: UIImage?
    var title: String
    var date: Date = .now
    /// Caption presence (reveal choreography drives it in).
    var appear: Double = 1

    var editableTitle: Binding<String>? = nil
    var titleFocused: FocusState<Bool>.Binding? = nil
    var onSubmitTitle: () -> Void = {}
    var onTapCaption: (() -> Void)? = nil

    static let aspect: CGFloat = 1.30

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                CardStock()
                photo(w)
                caption(w)
            }
        }
        .aspectRatio(1 / Self.aspect, contentMode: .fit)
    }

    @ViewBuilder
    private func photo(_ w: CGFloat) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 0.86 * w, height: 1.04 * w)
                .clipShape(RoundedRectangle(cornerRadius: 0.012 * w))
                .overlay(
                    RoundedRectangle(cornerRadius: 0.012 * w)
                        .strokeBorder(Theme.shadow.opacity(0.12), lineWidth: 1)
                )
                .offset(x: 0.07 * w, y: 0.07 * w)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func caption(_ w: CGFloat) -> some View {
        let lineY = 1.19 * w
        Group {
            if let binding = editableTitle {
                TextField("NAME IT", text: binding)
                    .font(Theme.stampEngraved(0.052 * w))
                    .foregroundStyle(Theme.stampInk.opacity(0.82))
                    .tint(Theme.postalRed)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(onSubmitTitle)
                    .frame(width: 0.64 * w)
                    .modifier(FocusedIfAvailable(focus: titleFocused))
            } else {
                Text(title.isEmpty ? "UNTITLED" : title.uppercased())
                    .font(Theme.stampEngraved(0.052 * w))
                    .kerning(0.052 * w * 0.13)
                    .foregroundStyle(Theme.stampInk.opacity(
                        title.isEmpty ? 0.40 : 0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: 0.64 * w)
                    .overlay(alignment: .bottom) {
                        Line()
                            .stroke(Theme.stampInk.opacity(
                                onTapCaption == nil ? 0 : 0.38 * appear),
                                    style: StrokeStyle(lineWidth: 1, dash: [2.5, 3]))
                            .frame(height: 1)
                            .offset(y: 0.014 * w)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onTapCaption?() }
                    // No rename handler ⇒ fully transparent to taps — a
                    // no-op gesture must not swallow chooser-thumb hits.
                    .allowsHitTesting(onTapCaption != nil)
            }
        }
        .position(x: 0.5 * w, y: lineY)
        .opacity(appear)

        // Clear of the caption's rename underline (which bottoms out
        // around 1.24 W).
        Text(Self.struckDate.string(from: date).uppercased())
            .font(.system(size: 0.030 * w, weight: .medium, design: .serif))
            .foregroundStyle(Theme.stampInk.opacity(0.45))
            .position(x: 0.5 * w, y: 1.268 * w)
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

/// The bare card stock — also the canvas editor's card background.
struct CardStock: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            RoundedRectangle(cornerRadius: 0.018 * w)
                .fill(Color(hex: 0xFBF5E8))
                .colorEffect(ShaderLibrary.paperGrain(.float(0.47), .float(0.42)))
                .shadow(color: Theme.shadow.opacity(0.28), radius: 0.045 * w, y: 0.022 * w)
                .shadow(color: Theme.shadow.opacity(0.14), radius: 0.008 * w, y: 0.004 * w)
        }
        .aspectRatio(1 / CardView.aspect, contentMode: .fit)
    }
}
