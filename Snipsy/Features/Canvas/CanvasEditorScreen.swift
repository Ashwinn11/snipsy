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
    /// `.session` = a modal editor opened from the album (X cancels, Keep
    /// returns to the collection). `.home` = the always-present memory
    /// maker (leading Collection button, Keep saves and resets to a fresh
    /// template so the next memory starts clean).
    var mode: Mode = .session

    enum Mode { case session, home }

    @State private var editor: CanvasEditorModel? = nil

    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showStickers = false
    @State private var showDoodles = false
    @State private var showBackgrounds = false
    @State private var showDateEditor = false
    /// Photos picked/imported, held until the batch treatment is chosen.
    /// Driven through `.sheet(item:)` — an `isPresented` sheet builds its
    /// content from the view value captured when the modifier was made, so
    /// a batch set in the same update reads back empty.
    @State private var pendingBatch: PendingBatch? = nil
    /// A camera shot waiting for its cover to close before it can ask.
    @State private var cameraCapture: UIImage? = nil
    @State private var saving = false

    /// One pick's worth of photos, awaiting a treatment.
    struct PendingBatch: Identifiable {
        let id = UUID()
        let images: [UIImage]
    }

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

            // Bottom-anchored so the selection bar replaces the tool rail
            // when a layer is selected — preventing 3 rows from covering the template.
            VStack(spacing: 10) {
                CanvasSelectionBar(editor: editor)
                if editor.selectedLayerID == nil {
                    CanvasToolRail(editor: editor,
                                   pickedItems: $pickedItems,
                                   showCamera: $showCamera,
                                   showStickers: $showStickers,
                                   showDoodles: $showDoodles,
                                   showBackgrounds: $showBackgrounds)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: editor.selectedLayerID != nil)
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
        .sheet(isPresented: $showDateEditor) {
            TemplateDateSheet(editor: editor)
        }
        .sheet(item: $pendingBatch) { batch in
            ImageModeChooserSheet(count: batch.images.count) { treatment in
                place(batch.images, as: treatment, into: editor)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CanvasCameraSheet(model: model) { image in
                cameraCapture = image
            }
        }
        // The chooser waits for the camera cover to actually leave — a sheet
        // raised in the same frame as a fullScreenCover dismissal gets eaten.
        .onChange(of: showCamera) { _, shown in
            guard !shown, let image = cameraCapture else { return }
            cameraCapture = nil
            pendingBatch = PendingBatch(images: [image])
        }
    }

    // MARK: Stage

    private func stage(_ editor: CanvasEditorModel, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            CanvasBackgroundView(background: editor.doc.background,
                                 date: editor.doc.date)
                .frame(width: size.width, height: size.height)
                .onTapGesture { deselect(editor) }

            // The printed date is part of the background, so it can't carry
            // its own tap — this invisible patch sits over wherever the
            // stock prints it. Below the layers, so a photo dragged over it
            // still wins the touch.
            let slot = editor.doc.background.dateSlot
            Color.clear
                .frame(width: slot.width * size.width,
                       height: slot.height * size.height)
                .contentShape(Rectangle())
                .offset(x: slot.minX * size.width, y: slot.minY * size.height)
                .onTapGesture {
                    model.haptics.tick()
                    deselect(editor)
                    showDateEditor = true
                }

            // Explicit zIndex from array position — the document's order
            // IS the stacking, live, even while a layer is selected.
            ForEach(Array(editor.doc.layers.enumerated()), id: \.element.id) { index, layer in
                CanvasLayerView(layer: layer, canvasSize: size, editor: editor)
                    .zIndex(Double(index))
            }
        }
        .coordinateSpace(name: "canvasStage")
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
            leadingButton(editor)

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

            Spacer(minLength: 8)

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

    /// Left of the top bar: dismiss (session) or open the collection (home).
    @ViewBuilder
    private func leadingButton(_ editor: CanvasEditorModel) -> some View {
        switch mode {
        case .session:
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
        case .home:
            Button {
                model.haptics.tick()
                withAnimation(Theme.spring) { model.showAlbum = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(model.store.stamps.count)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 44)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    // MARK: Ingest

    /// Decode the pick, then ask for one treatment for the whole batch —
    /// nothing lands on the canvas until the mode is chosen.
    private func ingest(_ items: [PhotosPickerItem], into editor: CanvasEditorModel) {
        guard !items.isEmpty else { return }
        Task { @MainActor in
            var batch: [UIImage] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = ImageOptimizer.downsampled(data: data, maxPixel: 1200)
                else { continue }
                batch.append(image)
            }
            pickedItems = []
            guard !batch.isEmpty else { return }
            pendingBatch = PendingBatch(images: batch)
        }
    }

    /// Drop the chosen batch onto the stage, cascaded so nothing hides
    /// behind the photo before it.
    private func place(_ images: [UIImage], as treatment: ImageTreatment,
                       into editor: CanvasEditorModel) {
        for (index, image) in images.enumerated() {
            editor.addImageLayer(image, cascade: index, treatment: treatment)
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
            model.pillBump += 1
            model.reviews.stampKept(count: model.store.stamps.count)
            switch mode {
            case .session:
                model.canvasSession = nil
                model.showAlbum = true
            case .home:
                // Stay on the home; wipe to a fresh template for the next
                // memory and confirm the keep.
                editor.resetForNewMemory()
                editor.flashToast("Kept ✓")
                saving = false
            }
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

/// Sets the memory's date — the header the template prints
/// ("JUL 14 / TUESDAY"). Opened by tapping the date on the canvas.
struct TemplateDateSheet: View {
    let editor: CanvasEditorModel
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Date")
                    .font(Theme.display(17))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 18)

                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.postalRed)
                    .padding(.horizontal, 12)

                Spacer(minLength: 0)

                Button {
                    editor.setDate(date)
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.postalRed, in: Capsule())
                        .padding(.horizontal, 24)
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.bottom, 24)
            }
        }
        .onAppear { date = editor.doc.date }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// Asked once per pick: how should these photos land? One mode for the
/// whole batch — a placed photo can still be switched from the selection
/// bar afterwards.
struct ImageModeChooserSheet: View {
    let count: Int
    let onChoose: (ImageTreatment) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 6) {
                Text(count == 1 ? "How should it land?"
                                : "How should these \(count) land?")
                    .font(Theme.display(19))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 22)

                Text("One look for the batch — you can change any of them later.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    option(.dieCut, title: "Die cut",
                           caption: "Lifts the subject") { w in
                        Image(systemName: "person.and.background.dotted")
                            .font(.system(size: 0.34 * w, weight: .light))
                            .foregroundStyle(Theme.ink)
                    }
                    option(.polaroid, title: "Polaroid",
                           caption: "In a white frame") { w in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: 0xFDFBF4))
                            .frame(width: 0.52 * w, height: 0.63 * w)
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(Theme.inkSoft.opacity(0.35))
                                    .frame(width: 0.46 * w, height: 0.46 * w)
                                    .padding(.top, 0.03 * w)
                            }
                            .shadow(color: Theme.shadow.opacity(0.2), radius: 3, y: 1)
                    }
                    option(.outline, title: "Outline",
                           caption: "Whole photo, white edge") { w in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.inkSoft.opacity(0.35))
                            .frame(width: 0.5 * w, height: 0.58 * w)
                            .padding(0.05 * w)
                            .background(RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white)
                                .shadow(color: Theme.shadow.opacity(0.2), radius: 3, y: 1))
                    }
                }
                .padding(.horizontal, 18)

                Spacer(minLength: 8)

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(height: 44)
                }
                .padding(.bottom, 14)
            }
        }
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
    }

    private func option<Art: View>(
        _ treatment: ImageTreatment, title: String, caption: String,
        @ViewBuilder art: @escaping (CGFloat) -> Art
    ) -> some View {
        Button {
            onChoose(treatment)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack { art(geo.size.width) }
                        .frame(width: geo.size.width, height: geo.size.width)
                }
                .aspectRatio(1, contentMode: .fit)

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(caption)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.shadow.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
    }
}
