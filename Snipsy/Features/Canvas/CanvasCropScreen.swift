import SwiftUI

/// A photo layer on its way to the cropper. `UIImage` is not `Identifiable`,
/// and identity here is per-presentation, not per-pixel — reopening the same
/// layer has to build a fresh screen.
struct CanvasCropTarget: Identifiable {
    let id = UUID()
    let layerID: UUID
    let image: UIImage
}

/// Free-form crop for a canvas photo layer.
///
/// Free means free: no aspect lock, no presets. The picture holds still and
/// the window moves over it — the opposite of `PhotoFramingScreen`, where a
/// fixed aperture is the whole point and the photo travels underneath it.
/// There is no aperture to satisfy here; the shape is what the user is
/// choosing.
struct CanvasCropScreen: View {
    let image: UIImage
    let screenSize: CGSize
    let safeArea: EdgeInsets
    var onCancel: () -> Void
    var onCrop: (UIImage) -> Void

    /// The window in normalized SOURCE coordinates (0…1 of the image).
    ///
    /// Normalized, not points: the stage is derived from the screen and the
    /// photo's aspect, so a rect in points would have to be re-derived on
    /// every relayout. This one converts to pixels with a single multiply at
    /// the very end, and until then never leaves the unit square.
    @State private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// The window as it stood when the current drag began.
    ///
    /// Every drag is measured from this against `translation`, never from
    /// the live value against a delta — accumulating deltas lets a clamped
    /// edge drift, so a corner pushed into the image's edge and back would
    /// not return to where it started.
    @State private var dragStart: CGRect? = nil

    /// Which edges a grip moves. Corners move two; the interior moves none.
    private struct Grip: OptionSet {
        let rawValue: Int
        static let left   = Grip(rawValue: 1 << 0)
        static let right  = Grip(rawValue: 1 << 1)
        static let top    = Grip(rawValue: 1 << 2)
        static let bottom = Grip(rawValue: 1 << 3)
    }

    // MARK: Geometry

    /// The area the photo may occupy — screen minus both chrome bars.
    private var stage: CGRect {
        let top = safeArea.top + 62
        let bottom = max(safeArea.bottom, 18) + 112
        return CGRect(x: 20, y: top,
                      width: max(80, screenSize.width - 40),
                      height: max(80, screenSize.height - top - bottom))
    }

    /// Where the photo sits on screen: aspect-fit, centred, never moving.
    private var fitted: CGRect {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return stage }
        let k = min(stage.width / s.width, stage.height / s.height)
        let w = s.width * k, h = s.height * k
        return CGRect(x: stage.midX - w / 2, y: stage.midY - h / 2,
                      width: w, height: h)
    }

    /// The crop window in view points.
    private var window: CGRect {
        let f = fitted
        return CGRect(x: f.minX + crop.minX * f.width,
                      y: f.minY + crop.minY * f.height,
                      width: crop.width * f.width,
                      height: crop.height * f.height)
    }

    /// Floor on the window, expressed in points and converted per axis. A
    /// flat normalized floor would be a different physical size on every
    /// photo aspect — thumbnail-thin on one, half the frame on another.
    private var minSize: CGSize {
        let f = fitted
        return CGSize(width: min(1, 54 / max(f.width, 1)),
                      height: min(1, 54 / max(f.height, 1)))
    }

    private var isFullFrame: Bool {
        crop.width > 0.999 && crop.height > 0.999
    }

    // MARK: Body

    var body: some View {
        let w = window

        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .frame(width: fitted.width, height: fitted.height)
                .position(x: fitted.midX, y: fitted.midY)

            // Everything outside the window recedes. Heavier than the
            // camera's 0.38 glass dim on purpose — there the dim is scene
            // setting, here it is the answer to "what am I keeping".
            HoleDim(hole: w)
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

            ThirdsGrid()
                .stroke(Color.white.opacity(0.28), lineWidth: 0.75)
                .frame(width: w.width, height: w.height)
                .position(x: w.midX, y: w.midY)
                .allowsHitTesting(false)

            Rectangle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                .frame(width: w.width, height: w.height)
                .position(x: w.midX, y: w.midY)
                .allowsHitTesting(false)

            CornerBrackets(arm: min(22, min(w.width, w.height) * 0.34))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3,
                                                        lineCap: .round))
                .frame(width: w.width, height: w.height)
                .position(x: w.midX, y: w.midY)
                .allowsHitTesting(false)

            // Drag the window whole. Under the grips in the stack, so a
            // corner always wins the touch it shares with the interior.
            Color.clear
                .frame(width: w.width, height: w.height)
                .contentShape(Rectangle())
                .gesture(drag { move(by: $0) })
                .position(x: w.midX, y: w.midY)

            grip(.left.union(.top), at: CGPoint(x: w.minX, y: w.minY))
            grip(.right.union(.top), at: CGPoint(x: w.maxX, y: w.minY))
            grip(.left.union(.bottom), at: CGPoint(x: w.minX, y: w.maxY))
            grip(.right.union(.bottom), at: CGPoint(x: w.maxX, y: w.maxY))
            grip(.top, at: CGPoint(x: w.midX, y: w.minY))
            grip(.bottom, at: CGPoint(x: w.midX, y: w.maxY))
            grip(.left, at: CGPoint(x: w.minX, y: w.midY))
            grip(.right, at: CGPoint(x: w.maxX, y: w.midY))

            chrome
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }

    // MARK: Gestures

    /// One drag shape for every grip: remember the window on the first tick,
    /// forget it on release.
    ///
    /// `.global` is not a detail — it is the whole reason this is steady.
    /// Every grip is `.position`ed off `crop`, so dragging one MOVES the
    /// view the gesture is attached to. In the default `.local` space that
    /// closes a feedback loop: `crop` shifts by Δ, the grip shifts with it,
    /// the next `translation` reads back short by Δ, `crop` corrects, and
    /// the frame buzzes — with the edge clamps re-exciting it every time a
    /// bound is hit. A stationary space breaks the loop; only the delta is
    /// used, so nothing else cares which space it came from.
    private func drag(_ apply: @escaping (CGSize) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if dragStart == nil { dragStart = crop }
                apply(value.translation)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func grip(_ g: Grip, at point: CGPoint) -> some View {
        // Invisible and finger-sized: the brackets are the affordance, and a
        // target drawn to their scale would be a 3-pt line to hit.
        Color.clear
            .frame(width: 46, height: 46)
            .contentShape(Rectangle())
            .gesture(drag { resize(g, by: $0) })
            .position(x: point.x, y: point.y)
    }

    private func move(by t: CGSize) {
        guard let start = dragStart else { return }
        let f = fitted
        let dx = t.width / max(f.width, 1)
        let dy = t.height / max(f.height, 1)
        crop = CGRect(x: min(max(0, start.minX + dx), 1 - start.width),
                      y: min(max(0, start.minY + dy), 1 - start.height),
                      width: start.width, height: start.height)
    }

    /// Move only the gripped edges. Each is clamped against the image's own
    /// bound on one side and the opposite edge (minus the floor) on the
    /// other, so a window can never invert or escape the photo.
    private func resize(_ g: Grip, by t: CGSize) {
        guard let start = dragStart else { return }
        let f = fitted
        let dx = t.width / max(f.width, 1)
        let dy = t.height / max(f.height, 1)
        let m = minSize
        var r = start

        if g.contains(.left) {
            let x = min(max(0, start.minX + dx), start.maxX - m.width)
            r.origin.x = x
            r.size.width = start.maxX - x
        }
        if g.contains(.right) {
            let maxX = max(min(1, start.maxX + dx), start.minX + m.width)
            r.size.width = maxX - r.minX
        }
        if g.contains(.top) {
            let y = min(max(0, start.minY + dy), start.maxY - m.height)
            r.origin.y = y
            r.size.height = start.maxY - y
        }
        if g.contains(.bottom) {
            let maxY = max(min(1, start.maxY + dy), start.minY + m.height)
            r.size.height = maxY - r.minY
        }
        crop = r
    }

    // MARK: Output

    /// The window, back-projected into the photo's own pixels.
    private func cropped() -> UIImage {
        let s = image.size
        let rect = CGRect(x: crop.minX * s.width, y: crop.minY * s.height,
                          width: crop.width * s.width,
                          height: crop.height * s.height)
            .intersection(CGRect(origin: .zero, size: s))
        guard rect.width > 8, rect.height > 8,
              let out = FrameGeometry.crop(image, to: rect)
        else { return image }
        return out
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack {
            HStack {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                }
                .background(.black.opacity(0.34), in: Capsule())

                Spacer(minLength: 12)

                Button {
                    withAnimation(Theme.springTight) {
                        crop = CGRect(x: 0, y: 0, width: 1, height: 1)
                    }
                } label: {
                    Text("Reset")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                }
                .background(.black.opacity(0.34), in: Capsule())
                .opacity(isFullFrame ? 0 : 1)
                .allowsHitTesting(!isFullFrame)
            }
            .padding(.horizontal, 20)
            .padding(.top, max(safeArea.top, 20))

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                Text("Drag the corners to crop.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))

                Button {
                    onCrop(cropped())
                } label: {
                    Text("Crop")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 34)
                        .frame(height: 52)
                        .background(Theme.postalRed, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.bottom, max(safeArea.bottom, 18) + 14)
        }
    }
}

/// Rule-of-thirds guides, drawn inside the window's own bounds.
private struct ThirdsGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 1...2 {
            let x = rect.minX + rect.width * CGFloat(i) / 3
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY))
            let y = rect.minY + rect.height * CGFloat(i) / 3
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return p
    }
}

/// The four corner brackets — the grab affordance. Drawn just inside the
/// window so they read as part of the frame rather than floating off it.
private struct CornerBrackets: Shape {
    var arm: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func bracket(at c: CGPoint, dx: CGFloat, dy: CGFloat) {
            p.move(to: CGPoint(x: c.x + dx * arm, y: c.y))
            p.addLine(to: c)
            p.addLine(to: CGPoint(x: c.x, y: c.y + dy * arm))
        }
        bracket(at: CGPoint(x: rect.minX, y: rect.minY), dx: 1, dy: 1)
        bracket(at: CGPoint(x: rect.maxX, y: rect.minY), dx: -1, dy: 1)
        bracket(at: CGPoint(x: rect.minX, y: rect.maxY), dx: 1, dy: -1)
        bracket(at: CGPoint(x: rect.maxX, y: rect.maxY), dx: -1, dy: -1)
        return p
    }
}
