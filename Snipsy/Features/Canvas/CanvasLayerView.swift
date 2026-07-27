import SwiftUI

/// One interactive layer on the editor stage: the shared content renderer
/// wearing live gesture deltas over its committed transform, plus the
/// selection chrome (dashed box, delete/duplicate badges).
///
/// Gesture contract: drag/pinch/rotate run simultaneously; live deltas
/// stay view-local and compose over the committed transform, committed
/// into the document on each gesture's end. The manipulation's undo push
/// happens once, on its first change tick.
struct CanvasLayerView: View {
    let layer: CanvasLayer
    let canvasSize: CGSize
    let editor: CanvasEditorModel

    @State private var dragDelta: CGSize = .zero
    @State private var magnifyDelta: CGFloat = 1
    @State private var rotateDelta: Angle = .zero
    /// One undo push per manipulation, on the first change tick.
    @State private var manipulating = false

    @FocusState private var textFocused: Bool

    private var selected: Bool { editor.selectedLayerID == layer.id }
    private var editingText: Bool { editor.editingTextID == layer.id }

    var body: some View {
        let t = layer.transform
        let liveScale = clampedScale(t.scale * magnifyDelta)

        content(liveScale: liveScale)
            .overlay { if selected { selectionBox } }
            .overlay(alignment: .topLeading) { if selected { deleteBadge } }
            .overlay(alignment: .topTrailing) { if selected { duplicateBadge } }
            .rotationEffect(.radians(t.rotation) + rotateDelta)
            .position(x: t.x * canvasSize.width + dragDelta.width,
                      y: t.y * canvasSize.height + dragDelta.height)
            .gesture(tapGesture)
            .gesture(manipulationGesture)
    }

    // MARK: Content

    @ViewBuilder
    private func content(liveScale: CGFloat) -> some View {
        if editingText, case .text(let string, let style) = layer.content {
            // Inline editing: a bare field in the layer's own voice. Safe
            // anywhere on the stage — no shader wraps the layer stack.
            // When the cut is on, a contour mirror rides beneath the field
            // (same idiom as the reveal's sticker tag) so the scissors
            // read in real time while typing.
            let fontSize = CanvasLayerContent.fontSize(
                scale: liveScale, canvasWidth: canvasSize.width)
            Group {
                if style.design == .ransom {
                    ransomField(string: string, style: style, fontSize: fontSize)
                } else {
                    ZStack {
                        if layer.dieCut {
                            DieCutText(text: string.isEmpty ? TextStyleValue.placeholder : string,
                                       fontSize: fontSize, ink: .clear, spread: 0.18,
                                       font: style.font(size: fontSize))
                        }
                        textField(string: string, style: style, fontSize: fontSize)
                            .foregroundStyle(style.color.color)
                            .tint(Theme.postalRed)
                            .fixedSize()
                    }
                }
            }
            .onAppear { textFocused = true }
            .onChange(of: editingText) { _, editing in
                if !editing { textFocused = false }
            }
        } else {
            CanvasLayerContent(content: layer.content,
                               canvasWidth: canvasSize.width,
                               scale: liveScale,
                               dieCut: layer.dieCut,
                               resolver: { editor.bitmap(for: $0) })
                .contentShape(Rectangle())
        }
    }

    /// The keyboard's proxy. Styling is left to the caller so it can either
    /// draw the glyphs itself or hand that job to a mirror.
    private func textField(string: String, style: TextStyleValue,
                           fontSize: CGFloat) -> some View {
        TextField(TextStyleValue.placeholder, text: Binding(
            get: { string },
            set: { editor.setText($0, for: layer.id) }
        ))
        .font(style.font(size: fontSize))
        .multilineTextAlignment(.center)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .onSubmit { editor.editingTextID = nil }
        .focused($textFocused)
    }

    /// Ransom is not a Font — it is `RansomText`, a run of paper chips each
    /// with its own face, tilt and stock, so no TextField can wear it. The
    /// editor used to give up and close itself the moment you picked it,
    /// which left the one voice in the set uneditable.
    ///
    /// Instead the real render does the drawing and an invisible field sits
    /// on top of it purely to hold the keyboard — the same mirror idiom the
    /// die cut already uses, with the roles reversed. The caret is hidden
    /// because chip metrics and plain-text metrics do not line up; the
    /// chips appearing as you type are the feedback.
    private func ransomField(string: String, style: TextStyleValue,
                             fontSize: CGFloat) -> some View {
        RansomText(text: string.isEmpty ? TextStyleValue.placeholder : string,
                   fontSize: fontSize,
                   ink: style.color.color)
            .opacity(string.isEmpty ? 0.45 : 1)
            .overlay {
                textField(string: string, style: style, fontSize: fontSize)
                    .foregroundStyle(.clear)
                    .tint(.clear)
            }
    }

    // MARK: Gestures

    private var tapGesture: some Gesture {
        TapGesture().onEnded {
            if selected, case .text = layer.content, !editingText {
                // Second tap on a selected text layer opens inline editing.
                editor.editingTextID = layer.id
            } else if !selected {
                editor.selectedLayerID = layer.id
                editor.editingTextID = nil
            }
        }
    }

    private var manipulationGesture: some Gesture {
        let drag = DragGesture(minimumDistance: 1)
            .onChanged { value in
                beginIfNeeded()
                dragDelta = value.translation
            }
            .onEnded { value in
                var t = currentTransform()
                t.x += value.translation.width / canvasSize.width
                t.y += value.translation.height / canvasSize.height
                dragDelta = .zero
                commit(t)
            }
        let magnify = MagnifyGesture()
            .onChanged { value in
                beginIfNeeded()
                magnifyDelta = value.magnification
            }
            .onEnded { value in
                var t = currentTransform()
                t.scale = clampedScale(t.scale * value.magnification)
                magnifyDelta = 1
                commit(t)
            }
        let rotate = RotateGesture()
            .onChanged { value in
                beginIfNeeded()
                rotateDelta = value.rotation
            }
            .onEnded { value in
                var t = currentTransform()
                t.rotation += value.rotation.radians
                rotateDelta = .zero
                commit(t)
            }
        return drag.simultaneously(with: magnify).simultaneously(with: rotate)
    }

    private func beginIfNeeded() {
        if !manipulating {
            manipulating = true
            editor.push()
            if !selected {
                editor.selectedLayerID = layer.id
                editor.editingTextID = nil
            }
        }
    }

    private func currentTransform() -> LayerTransform {
        editor.doc.layers.first(where: { $0.id == layer.id })?.transform
            ?? layer.transform
    }

    private func commit(_ t: LayerTransform) {
        editor.setTransform(t, for: layer.id)
        if dragDelta == .zero, magnifyDelta == 1, rotateDelta == .zero {
            manipulating = false
        }
    }

    private func clampedScale(_ s: CGFloat) -> CGFloat {
        min(2.5, max(0.06, s))
    }

    // MARK: Selection chrome

    private var selectionBox: some View {
        RoundedRectangle(cornerRadius: 3)
            .stroke(Theme.postalRed.opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .padding(-6)
            .allowsHitTesting(false)
    }

    private var deleteBadge: some View {
        Button {
            editor.delete(layer.id)
        } label: {
            badgeIcon("xmark")
        }
        .offset(x: -16, y: -16)
    }

    private var duplicateBadge: some View {
        Button {
            editor.duplicate(layer.id)
        } label: {
            badgeIcon("plus.square.on.square")
        }
        .offset(x: 16, y: -16)
    }

    private func badgeIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(width: 26, height: 26)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Theme.shadow.opacity(0.2), lineWidth: 0.5))
    }
}
