import SwiftUI
import PhotosUI

/// The editor's bottom tool rail: add photos, camera, text, stickers,
/// doodles, switch the background stock.
struct CanvasToolRail: View {
    let editor: CanvasEditorModel
    @Binding var pickedItems: [PhotosPickerItem]
    @Binding var showCamera: Bool
    @Binding var showStickers: Bool
    @Binding var showDoodles: Bool
    @Binding var showBackgrounds: Bool

    var body: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $pickedItems, maxSelectionCount: 10,
                         matching: .images) {
                railIcon("photo.on.rectangle.angled")
            }
            .glassEffect(.regular.interactive(), in: .circle)

            railButton("camera") { showCamera = true }
            railButton("textformat") { editor.addTextLayer() }
            railButton("seal") { showStickers = true }
            railButton("sparkles") { showDoodles = true }
            railButton("square.3.layers.3d.down.right") { showBackgrounds = true }
        }
    }

    private func railButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            railIcon(icon)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private func railIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 48, height: 48)
    }
}

/// Contextual strip above the rail for the selected layer: text voice
/// controls, or the image cutout toggle — plus z-order for everything.
struct CanvasSelectionBar: View {
    let editor: CanvasEditorModel

    private static let inkChoices: [RGBValue] = [
        RGBValue(r: 0.133, g: 0.122, b: 0.102),   // stamp ink
        RGBValue(r: 0.973, g: 0.953, b: 0.910),   // cream
        RGBValue(r: 0.839, g: 0.314, b: 0.227),   // postal red
        RGBValue(r: 0.153, g: 0.282, b: 0.588),   // airmail blue
        RGBValue(r: 0.180, g: 0.259, b: 0.173),   // botanical green
        RGBValue(r: 0.890, g: 0.604, b: 0.651),   // sweetheart rose
    ]

    var body: some View {
        if let layer = editor.selectedLayer {
            VStack(spacing: 8) {
                // Text voice / image treatment each get their own row — with
                // zoom in the common bar, one capsule can't hold both on a
                // small phone.
                if case .text(_, let style) = layer.content {
                    barCapsule { textControls(layer: layer, style: style) }
                }
                if case .image(_, _, let treatment) = layer.content {
                    barCapsule { treatmentControls(layer: layer, current: treatment) }
                }

                barCapsule {
                    // Stickers, doodles and text wear a single white contour;
                    // photos choose a treatment above instead.
                    if !isImage(layer) {
                        Button {
                            editor.toggleDieCut(layer.id)
                        } label: {
                            barIcon("scissors", tint: layer.dieCut
                                    ? Theme.postalRed : Theme.ink)
                        }
                        Divider().frame(height: 22)
                    }

                    Button { editor.nudgeScale(layer.id, factor: 1 / 1.15) } label: {
                        barIcon("minus.magnifyingglass")
                    }
                    Button { editor.nudgeScale(layer.id, factor: 1.15) } label: {
                        barIcon("plus.magnifyingglass")
                    }

                    Divider().frame(height: 22)

                    // Absolute z-order: behind everything / on top of
                    // everything. Dimmed when the layer is already there.
                    let isBack = editor.doc.layers.first?.id == layer.id
                    let isFront = editor.doc.layers.last?.id == layer.id
                    Button { editor.sendToBack(layer.id) } label: {
                        barIcon("square.2.layers.3d.bottom.filled")
                            .opacity(isBack ? 0.3 : 1)
                    }
                    .disabled(isBack)
                    Button { editor.bringToFront(layer.id) } label: {
                        barIcon("square.2.layers.3d.top.filled")
                            .opacity(isFront ? 0.3 : 1)
                    }
                    .disabled(isFront)
                }
            }
        }
    }

    private func isImage(_ layer: CanvasLayer) -> Bool {
        if case .image = layer.content { return true }
        return false
    }

    /// Photo treatment row: die-cut / polaroid / outline, applied to the
    /// selected image. Die-cut runs Vision the first time (spinner).
    @ViewBuilder
    private func treatmentControls(layer: CanvasLayer,
                                   current: ImageTreatment) -> some View {
        treatmentButton(.dieCut, "scissors", "Cut", layer: layer, current: current)
        treatmentButton(.polaroid, "photo", "Polaroid", layer: layer, current: current)
        treatmentButton(.outline, "square.dashed", "Outline", layer: layer, current: current)
    }

    private func treatmentButton(_ treatment: ImageTreatment, _ icon: String,
                                 _ label: String, layer: CanvasLayer,
                                 current: ImageTreatment) -> some View {
        Button {
            editor.setTreatment(treatment, for: layer.id)
        } label: {
            if treatment == .dieCut, editor.cutoutBusy.contains(layer.id) {
                ProgressView().controlSize(.small).frame(width: 52, height: 34)
            } else {
                VStack(spacing: 2) {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                    Text(label).font(.system(size: 8.5, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(current == treatment ? Theme.postalRed : Theme.ink)
                .frame(width: 52, height: 34)
            }
        }
        .disabled(editor.cutoutBusy.contains(layer.id))
    }

    /// One glass row. The whole capsule eats taps — a near-miss between
    /// buttons must not fall through to the backdrop and drop the
    /// selection out from under the user.
    private func barCapsule<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10, content: content)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .glassEffect(.regular, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture {}
    }

    @ViewBuilder
    private func textControls(layer: CanvasLayer, style: TextStyleValue) -> some View {
        // Voice: cycle through the designs.
        Button {
            var s = style
            let all = TextStyleValue.DesignValue.allCases
            let i = all.firstIndex(of: s.design) ?? 0
            s.design = all[(i + 1) % all.count]
            editor.setTextStyle(s, for: layer.id)
            // Ransom used to close the editor here, because the inline
            // field couldn't wear its chips. It no longer has to — the
            // field hands the drawing to a live RansomText mirror (see
            // CanvasLayerView.ransomField), so every voice stays editable.
        } label: {
            Text("Aa")
                .font(style.font(size: 17))
                .foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30)
        }

        ForEach(Array(Self.inkChoices.enumerated()), id: \.offset) { _, ink in
            Button {
                var s = style
                s.color = ink
                editor.setTextStyle(s, for: layer.id)
            } label: {
                Circle()
                    .fill(ink.color)
                    .overlay(Circle().strokeBorder(
                        Theme.shadow.opacity(ink.luminance > 0.8 ? 0.35 : 0.12),
                        lineWidth: 1))
                    .overlay {
                        if style.color == ink {
                            Circle().strokeBorder(Theme.postalRed, lineWidth: 2)
                                .padding(-3)
                        }
                    }
                    .frame(width: 20, height: 20)
                    // A 20-pt dot is a miss magnet — give the finger the
                    // full 28-pt cell.
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
    }


    private func barIcon(_ name: String, tint: Color = Theme.ink) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
    }
}

/// Sticker drawer sheet: the user's saved die-cuts, tap to place a copy.
struct CanvasStickerSheet: View {
    let editor: CanvasEditorModel
    let store: StampStore
    @Environment(\.dismiss) private var dismiss

    private var stickers: [Stamp] {
        store.stamps.filter { $0.kind == .sticker }
    }

    var body: some View {
        sheetShell(title: "Your Stickers") {
            if stickers.isEmpty {
                Text("Snip a sticker with the camera first — they'll all be here.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(30)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 14)],
                          spacing: 14) {
                    ForEach(stickers) { stamp in
                        Button {
                            editor.addStickerLayer(from: stamp)
                            dismiss()
                        } label: {
                            if let image = store.image(for: stamp) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 84)
                            }
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(20)
            }
        }
    }
}

/// Doodle pack sheet.
struct CanvasDoodleSheet: View {
    let editor: CanvasEditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        sheetShell(title: "Doodles") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 16)],
                      spacing: 16) {
                ForEach(DoodleCatalog.all, id: \.self) { id in
                    Button {
                        editor.addDoodle(id: id)
                        dismiss()
                    } label: {
                        DoodleCatalog.view(id: id, width: 68)
                            .frame(width: 76, height: 76)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(20)
        }
    }
}

/// Background stock switcher sheet.
struct CanvasBackgroundSheet: View {
    let editor: CanvasEditorModel
    @Environment(\.dismiss) private var dismiss

    /// The shared gallery — same stocks, same order as the entry-point
    /// chooser (`CanvasDocument.Background.offered`).
    private var choices: [CanvasDocument.Background] { CanvasDocument.Background.offered }

    /// A fixed date so the stamp/polaroid thumbnails read as dated without churning.
    private static let sampleDate = Date(timeIntervalSince1970: 1_752_460_800)

    var body: some View {
        sheetShell(title: "Templates") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 16)],
                      spacing: 18) {
                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                    Button {
                        editor.setBackground(choice)
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            CanvasBackgroundView(background: choice, date: Self.sampleDate)
                                .frame(width: 78)
                                .overlay {
                                    if editor.doc.background == choice {
                                        RoundedRectangle(cornerRadius: 5)
                                            .strokeBorder(Theme.postalRed, lineWidth: 1.6)
                                            .padding(-4)
                                    }
                                }
                            Text(choice.label)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(20)
        }
    }
}

/// Shared sheet chrome: paper backdrop, a title, scrolling content.
@ViewBuilder
private func sheetShell<Content: View>(
    title: String, @ViewBuilder content: () -> Content
) -> some View {
    ZStack {
        Theme.paper.ignoresSafeArea()
        VStack(spacing: 0) {
            Text(title)
                .font(Theme.display(17))
                .foregroundStyle(Theme.ink)
                .padding(.top, 18)
            ScrollView {
                content()
            }
        }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
}
