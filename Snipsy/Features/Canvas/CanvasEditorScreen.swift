import SwiftUI
import PhotosUI

/// The memories canvas: a free-form layer editor over a paper stock.
/// Entered from the album (blank) or a saved artifact (decorate/re-edit);
/// Done flattens the stage and keeps it as a `.canvas` creation.
struct CanvasEditorScreen: View {
    let model: AppModel
    let session: CanvasSession
    let screenSize: CGSize
    let safeArea: EdgeInsets

    @State private var editor: CanvasEditorModel? = nil

    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showStickers = false
    @State private var showDoodles = false
    @State private var showBackgrounds = false
    @State private var saving = false

    var body: some View {
        ZStack {
            PaperBackdrop(showsGrid: true)

            if let editor {
                content(editor)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .onAppear {
            if editor == nil {
                editor = CanvasEditorModel(session: session, store: model.store)
            }
        }
    }

    @ViewBuilder
    private func content(_ editor: CanvasEditorModel) -> some View {
        let topH = safeArea.top + 64
        let railH = max(safeArea.bottom, 16) + 118
        let stageAvail = CGSize(width: screenSize.width - 32,
                                height: screenSize.height - topH - railH)
        let stageW = min(stageAvail.width, stageAvail.height / editor.doc.aspect)
        let stageSize = CGSize(width: stageW, height: stageW * editor.doc.aspect)

        ZStack {
            // Tap the page around the stage to drop selection / end editing.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { deselect(editor) }

            stage(editor, size: stageSize)
                .position(x: screenSize.width / 2,
                          y: topH + stageAvail.height / 2)

            topBar(editor)
                .position(x: screenSize.width / 2, y: safeArea.top + 32)

            // Bottom-anchored so the selection bar (one row or two) grows
            // upward over the stage — the rail never sinks.
            VStack(spacing: 10) {
                CanvasSelectionBar(editor: editor)
                CanvasToolRail(editor: editor,
                               pickedItems: $pickedItems,
                               showCamera: $showCamera,
                               showStickers: $showStickers,
                               showDoodles: $showDoodles,
                               showBackgrounds: $showBackgrounds)
            }
            .padding(.bottom, max(safeArea.bottom, 16) + 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            if let toast = editor.toast {
                Text(toast)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
                    .position(x: screenSize.width / 2, y: topH + 30)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: editor.toast)
        .onChange(of: pickedItems) { _, items in
            ingest(items, into: editor)
        }
        .sheet(isPresented: $showStickers) {
            CanvasStickerSheet(editor: editor, store: model.store)
        }
        .sheet(isPresented: $showDoodles) {
            CanvasDoodleSheet(editor: editor)
        }
        .sheet(isPresented: $showBackgrounds) {
            CanvasBackgroundSheet(editor: editor)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CanvasCameraSheet(model: model) { image in
                editor.addImageLayer(image)
            }
        }
    }

    // MARK: Stage

    private func stage(_ editor: CanvasEditorModel, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            CanvasBackgroundView(background: editor.doc.background)
                .frame(width: size.width, height: size.height)
                .onTapGesture { deselect(editor) }

            // Explicit zIndex from array position — the document's order
            // IS the stacking, live, even while a layer is selected.
            ForEach(Array(editor.doc.layers.enumerated()), id: \.element.id) { index, layer in
                CanvasLayerView(layer: layer, canvasSize: size, editor: editor)
                    .zIndex(Double(index))
            }
        }
        .frame(width: size.width, height: size.height)
        // Layers may be dragged past the stock's edge; they clip only in
        // the flatten (the artifact's silhouette is the paper).
    }

    private func deselect(_ editor: CanvasEditorModel) {
        editor.editingTextID = nil
        editor.selectedLayerID = nil
    }

    // MARK: Top bar

    private func topBar(_ editor: CanvasEditorModel) -> some View {
        HStack(spacing: 12) {
            Button {
                model.haptics.tick()
                editor.cancel()
                model.canvasSession = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Button {
                editor.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(editor.undoStack.isEmpty
                                     ? Theme.inkSoft.opacity(0.4) : Theme.ink)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(editor.undoStack.isEmpty)

            Button {
                editor.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(editor.redoStack.isEmpty
                                     ? Theme.inkSoft.opacity(0.4) : Theme.ink)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(editor.redoStack.isEmpty)

            Spacer()

            Button {
                save(editor)
            } label: {
                HStack(spacing: 7) {
                    if saving {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "seal.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text("Keep")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 44)
                .background(Theme.postalRed, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(saving)
        }
        .padding(.horizontal, 16)
        .frame(width: screenSize.width)
    }

    // MARK: Ingest

    private func ingest(_ items: [PhotosPickerItem], into editor: CanvasEditorModel) {
        guard !items.isEmpty else { return }
        Task { @MainActor in
            var index = 0
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = ImageOptimizer.downsampled(data: data, maxPixel: 1200)
                else { continue }
                editor.addImageLayer(image, cascade: index)
                index += 1
            }
            pickedItems = []
        }
    }

    // MARK: Save

    private func save(_ editor: CanvasEditorModel) {
        guard !saving else { return }
        saving = true
        deselect(editor)
        model.haptics.thunk()
        Task { @MainActor in
            // One commit so the deselected stage (no chrome) is what
            // renders.
            await afterNextCommit()
            let doc = editor.doc
            let content = CanvasStageView(doc: doc, resolver: { editor.bitmap(for: $0) })
                .frame(width: 400, height: 400 * doc.aspect)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            renderer.isOpaque = false
            guard let preview = renderer.uiImage else {
                saving = false
                return
            }
            editor.save(preview: preview)
            model.haptics.success()
            model.canvasSession = nil
            model.showAlbum = true
        }
    }
}

/// In-canvas capture: the running camera session with a bare shutter —
/// no develop, no reveal, the photo drops straight onto the canvas.
struct CanvasCameraSheet: View {
    let model: AppModel
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var capturing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(session: model.camera.session) { _, devicePoint in
                model.camera.focus(atDevicePoint: devicePoint)
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                Button {
                    guard !capturing else { return }
                    capturing = true
                    model.haptics.thunk()
                    Task { @MainActor in
                        defer { capturing = false }
                        guard let raw = try? await model.camera.capture() else { return }
                        let image = ImageOptimizer.downscaled(
                            ImageOptimizer.normalizedOrientation(raw), maxDimension: 1200)
                        onCapture(image)
                        dismiss()
                    }
                } label: {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 74, height: 74)
                        .overlay(Circle().fill(.white).padding(7))
                        .opacity(capturing ? 0.5 : 1)
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear { model.camera.start() }
    }
}
