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
    /// The drag angle (from the layer's center) where a rotate-handle drag
    /// began — everything after is measured relative to it.
    @State private var handleStartAngle: CGFloat? = nil

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
            .overlay(alignment: .top) { if selected { rotateHandle } }
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
            // When ransom or die cut is active, a mirror rides beneath the
            // field so the chips or contour read in real time while typing.
            // A stable ZStack keeps the TextField's view identity intact across
            // voice switches so the keyboard never closes.
            let fontSize = CanvasLayerContent.fontSize(
                scale: liveScale, canvasWidth: canvasSize.width)
            ZStack {
                if style.design == .ransom {
                    RansomText(text: string.isEmpty ? TextStyleValue.placeholder : string,
                               fontSize: fontSize,
                               ink: style.color.color)
                        .opacity(string.isEmpty ? 0.45 : 1)
                } else if layer.dieCut {
                    DieCutText(text: string.isEmpty ? TextStyleValue.placeholder : string,
                               fontSize: fontSize, ink: .clear, spread: 0.18,
                               font: style.font(size: fontSize))
                }

                textField(string: string, style: style, fontSize: fontSize)
                    .foregroundStyle(style.design == .ransom ? Color.clear : style.color.color)
                    .tint(style.design == .ransom ? Color.clear : Theme.postalRed)
                    .fixedSize()
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

    /// The keyboard's proxy.
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

    /// One-finger 360° rotate: a knob above the layer, on a purely visual
    /// stem. Dragging the knob anywhere around the layer's center rotates
    /// freely — the alternative to the two-finger rotate gesture, which
    /// needs a second finger free.
    ///
    /// Only the knob itself is hit-testable. The stem below it is a dead
    /// zone (`allowsHitTesting(false)`) — a real gap between "drag the
    /// layer" and "rotate it", so grabbing near the layer's top edge (the
    /// natural place to grab it) never gets mistaken for the handle.
    private var rotateHandle: some View {
        VStack(spacing: 0) {
            badgeIcon("arrow.triangle.2.circlepath")
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                // A plain .gesture() here would have to out-race the
                // layer's own manipulationGesture (also a DragGesture) for
                // the same touch — highPriorityGesture makes this one win
                // outright whenever the touch starts on the knob itself.
                .highPriorityGesture(rotateHandleGesture)
            Rectangle()
                .fill(Theme.shadow.opacity(0.35))
                .frame(width: 1.5, height: 22)
                .allowsHitTesting(false)
        }
        .offset(y: -62)
    }

    /// The layer's live center, in the stage's named coordinate space —
    /// matches the `.position(...)` this view places itself at.
    private var centerInStage: CGPoint {
        CGPoint(x: layer.transform.x * canvasSize.width + dragDelta.width,
                y: layer.transform.y * canvasSize.height + dragDelta.height)
    }

    private var rotateHandleGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvasStage"))
            .onChanged { value in
                beginIfNeeded()
                let center = centerInStage
                let angle = atan2(value.location.y - center.y, value.location.x - center.x)
                if handleStartAngle == nil { handleStartAngle = angle }
                rotateDelta = Angle(radians: angle - (handleStartAngle ?? angle))
            }
            .onEnded { _ in
                var t = currentTransform()
                t.rotation += rotateDelta.radians
                rotateDelta = .zero
                handleStartAngle = nil
                commit(t)
            }
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
