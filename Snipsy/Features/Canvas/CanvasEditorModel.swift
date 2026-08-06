import SwiftUI
import Observation

/// The canvas editor's working state: the document, its decoded bitmaps,
/// selection, and a value-type undo history (pixels live in files, so a
/// snapshot is bytes).
@MainActor
@Observable
final class CanvasEditorModel {

    var doc: CanvasDocument
    var title: String
    var selectedLayerID: UUID? = nil
    /// Text layer currently in inline editing.
    ///
    /// Entering and leaving edit mode manage the seeded placeholder. A new
    /// layer arrives holding "Your words" so it is visible on the stage,
    /// but that is real content — meaning every caption started with a
    /// select-all-delete. It now clears on entry and comes back if you
    /// leave without typing, so an untouched layer looks exactly as before.
    var editingTextID: UUID? = nil {
        didSet {
            guard editingTextID != oldValue else { return }
            if let leaving = oldValue { restorePlaceholder(leaving) }
            if let entering = editingTextID { clearPlaceholder(entering) }
        }
    }
    /// Image layers with a Vision cutout in flight.
    var cutoutBusy: Set<UUID> = []
    /// Brief toast line ("No subject found").
    var toast: String? = nil

    private(set) var undoStack: [CanvasDocument] = []
    private(set) var redoStack: [CanvasDocument] = []

    /// nil = a new creation; set = re-editing this stamp in place.
    let stampID: UUID?
    private let store: StampStore
    /// Files written during THIS session — cancel deletes them all (the
    /// loaded document never references them).
    private var sessionFiles: Set<String> = []

    init(session: CanvasSession, store: StampStore) {
        self.doc = session.seed
        self.title = session.seedTitle
        self.stampID = session.stampID
        self.store = store

        // Decorate entry: the source artifact lands as the first layer —
        // its pixels copied to a session-owned file (cancel GC applies).
        // Stamps, polaroids and cards arrive WHOLE: the dressed collectible
        // (frame, perforations, caption baked in), not just its photo.
        if let artifact = session.seedArtifact,
           let image = store.image(for: artifact) {
            let pixels = Self.dressedRender(of: artifact, image: image) ?? image
            let file = store.saveLayerImage(pixels)
            sessionFiles.insert(file)
            doc.layers.append(CanvasLayer(
                content: .sticker(file: file),
                transform: LayerTransform(x: 0.5, y: 0.48, scale: 0.55)
            ))
        }
    }

    /// The complete artifact as transparent pixels — the same dressed
    /// render the share path exports. Stickers pass through (their stored
    /// file already IS the die cut).
    private static func dressedRender(of artifact: Stamp,
                                      image: UIImage) -> UIImage? {
        let aspect: CGFloat
        switch artifact.kind {
        case .stamp: aspect = 1.3125
        case .polaroid: aspect = PolaroidView.aspect
        case .card: aspect = CardView.aspect
        case .sticker, .canvas: return nil
        }
        let renderer = ImageRenderer(content:
            ArtifactView(stamp: artifact, image: image)
                .frame(width: 360, height: 360 * aspect))
        renderer.scale = 3
        renderer.isOpaque = false
        return renderer.uiImage
    }

    var selectedLayer: CanvasLayer? {
        selectedLayerID.flatMap { id in doc.layers.first { $0.id == id } }
    }

    func bitmap(for file: String) -> UIImage? {
        store.layerImage(named: file)
    }

    // MARK: Undo

    func push() {
        undoStack.append(doc)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
        scaleRun = nil
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(doc)
        doc = prev
        reconcileSelection()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(doc)
        doc = next
        reconcileSelection()
    }

    private func reconcileSelection() {
        if let sel = selectedLayerID, !doc.layers.contains(where: { $0.id == sel }) {
            selectedLayerID = nil
        }
        if let editing = editingTextID, !doc.layers.contains(where: { $0.id == editing }) {
            editingTextID = nil
        }
    }

    // MARK: Layers

    /// Cascade new layers a step down-right so a multi-pick doesn't stack
    /// into one invisible pile. `treatment` is the mode chosen for the batch;
    /// die-cut kicks off the subject lift in the background.
    func addImageLayer(_ image: UIImage, cascade: Int = 0,
                       treatment: ImageTreatment = .plain) {
        push()
        let file = store.saveLayerImage(image)
        sessionFiles.insert(file)
        let step = CGFloat(cascade % 5) * 0.04
        let layer = CanvasLayer(
            content: .image(file: file, cutoutFile: nil, treatment: treatment),
            transform: LayerTransform(x: 0.5 + step, y: 0.45 + step, scale: 0.55)
        )
        doc.layers.append(layer)
        selectedLayerID = layer.id
        if treatment == .dieCut {
            Task { await fillDieCut(id: layer.id) }
        }
    }

    func addTextLayer() {
        push()
        let layer = CanvasLayer(
            content: .text(string: TextStyleValue.placeholder, style: TextStyleValue()),
            transform: LayerTransform(x: 0.5, y: 0.5, scale: 0.28)
        )
        doc.layers.append(layer)
        selectedLayerID = layer.id
        editingTextID = layer.id
    }

    /// Copy any collected artifact into the composition — its own file, so
    /// the source can be deleted without breaking this creation.
    ///
    /// Stamps, polaroids and cards arrive WHOLE, exactly as they do on the
    /// decorate entry path: the stored file is only their source photo, so
    /// placing that directly would strip the perforations and caption that
    /// make them the thing the user collected. `dressedRender` returns nil
    /// for stickers and pages, whose stored pixels already are the artifact.
    func addStickerLayer(from stamp: Stamp) {
        guard let source = store.image(for: stamp) else { return }
        let image = Self.dressedRender(of: stamp, image: source) ?? source
        push()
        let file = store.saveLayerImage(image)
        sessionFiles.insert(file)
        let layer = CanvasLayer(
            content: .sticker(file: file),
            transform: LayerTransform(x: 0.5, y: 0.5, scale: 0.4)
        )
        doc.layers.append(layer)
        selectedLayerID = layer.id
    }

    func addDoodle(id: String) {
        push()
        let layer = CanvasLayer(
            content: .doodle(id: id),
            transform: LayerTransform(x: 0.5, y: 0.5, scale: 0.34)
        )
        doc.layers.append(layer)
        selectedLayerID = layer.id
    }

    func delete(_ id: UUID) {
        push()
        doc.layers.removeAll { $0.id == id }
        reconcileSelection()
    }

    func duplicate(_ id: UUID) {
        guard let layer = doc.layers.first(where: { $0.id == id }) else { return }
        push()
        var t = layer.transform
        t.x = min(0.95, t.x + 0.05)
        t.y = min(0.95, t.y + 0.05)
        let copy = CanvasLayer(content: layer.content, transform: t)
        doc.layers.append(copy)
        selectedLayerID = copy.id
    }

    /// Absolute, not stepwise — one tap must produce one visible result.
    /// Stepwise swaps trade places with whatever neighbors the array has,
    /// which may not even overlap the selected layer on screen.
    func bringToFront(_ id: UUID) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }),
              i < doc.layers.count - 1 else { return }
        push()
        let layer = doc.layers.remove(at: i)
        doc.layers.append(layer)
    }

    func sendToBack(_ id: UUID) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }), i > 0 else { return }
        push()
        let layer = doc.layers.remove(at: i)
        doc.layers.insert(layer, at: 0)
    }

    /// A run of zoom-button taps on one layer collapses into a single
    /// undo entry; any other edit's push() breaks the run.
    private var scaleRun: UUID? = nil

    /// Stepper zoom from the selection bar — the button alternative to
    /// pinching.
    func nudgeScale(_ id: UUID, factor: CGFloat) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }) else { return }
        if scaleRun != id {
            push()
            scaleRun = id
        }
        var t = doc.layers[i].transform
        t.scale = min(2.5, max(0.06, t.scale * factor))
        doc.layers[i].transform = t
    }

    /// Gesture-end commit — the manipulation's undo push already happened
    /// on its first change tick.
    func setTransform(_ transform: LayerTransform, for id: UUID) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }) else { return }
        doc.layers[i].transform = transform
    }

    /// Editing began: drop the seeded placeholder so typing starts on an
    /// empty field. The field shows the same words in grey, so nothing
    /// looks different — there is just nothing to delete first.
    private func clearPlaceholder(_ id: UUID) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }),
              case .text(let string, let style) = doc.layers[i].content,
              string == TextStyleValue.placeholder else { return }
        doc.layers[i].content = .text(string: "", style: style)
    }

    /// Editing ended with nothing typed: put the placeholder back, or the
    /// layer renders as nothing and becomes impossible to find or tap.
    private func restorePlaceholder(_ id: UUID) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }),
              case .text(let string, let style) = doc.layers[i].content,
              string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        doc.layers[i].content = .text(string: TextStyleValue.placeholder,
                                      style: style)
    }

    func setText(_ string: String, for id: UUID) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }),
              case .text(_, let style) = doc.layers[i].content else { return }
        doc.layers[i].content = .text(string: string, style: style)
    }

    func setTextStyle(_ style: TextStyleValue, for id: UUID) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }),
              case .text(let string, _) = doc.layers[i].content else { return }
        push()
        doc.layers[i].content = .text(string: string, style: style)
    }

    func setBackground(_ background: CanvasDocument.Background) {
        push()
        doc.background = background
        doc.aspect = CanvasDocument.aspect(for: background)
    }

    /// Set the stamp template's header date in one undo step. No-op (no
    /// history churn) when nothing actually changed.
    func setDate(_ date: Date) {
        guard doc.date != date else { return }
        push()
        doc.date = date
    }

    // MARK: Treatment

    /// The universal white contour — everything but photos, which choose a
    /// treatment (die-cut / polaroid / outline) instead.
    func toggleDieCut(_ id: UUID) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }) else { return }
        if case .image = doc.layers[i].content { return }
        push()
        doc.layers[i].dieCut.toggle()
    }

    /// Switch a photo layer's treatment. Die-cut lazily runs the subject lift
    /// the first time (caching it in cutoutFile); switching away and back
    /// never re-runs Vision.
    func setTreatment(_ treatment: ImageTreatment, for id: UUID) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }),
              case .image(let file, let cutoutFile, let old) = doc.layers[i].content,
              old != treatment else { return }
        push()
        doc.layers[i].content = .image(file: file, cutoutFile: cutoutFile,
                                       treatment: treatment)
        if treatment == .dieCut, cutoutFile == nil {
            Task { await fillDieCut(id: id) }
        }
    }

    /// Replace a photo layer's pixels with a crop of them.
    ///
    /// The treatment survives; its *derivation* cannot. `cutoutFile` was
    /// lifted from pixels that no longer exist, so a die-cut layer would go
    /// on showing a subject the new frame may not even contain — cropping to
    /// someone's face would leave the old full-body cut floating there.
    /// Dropping it and re-running the lift is what makes "crop, then cut"
    /// mean what it says. Polaroid and outline need nothing: both are drawn
    /// from `file` at render time, so they re-frame the moment it changes.
    ///
    /// The old file deliberately stays on disk. `duplicate` shares content
    /// between layers, and undo has to be able to bring these pixels back;
    /// `save()` sweeps whatever the final document stopped referencing.
    func setCroppedImage(_ image: UIImage, for id: UUID) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }),
              case .image(_, _, let treatment) = doc.layers[i].content
        else { return }
        push()
        let file = store.saveLayerImage(image)
        sessionFiles.insert(file)
        doc.layers[i].content = .image(file: file, cutoutFile: nil,
                                       treatment: treatment)
        if treatment == .dieCut {
            Task { await fillDieCut(id: id) }
        }
    }

    /// Run the subject lift for a die-cut layer that has no cached cutout yet,
    /// then store it. No `push()` — this is the async completion of the add /
    /// switch that already pushed. Falls back to plain when no subject is found.
    private func fillDieCut(id: UUID) async {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }),
              case .image(let file, nil, .dieCut) = doc.layers[i].content,
              !cutoutBusy.contains(id),
              let bitmap = store.layerImage(named: file)
        else { return }

        cutoutBusy.insert(id)
        let analysis = await VisionService.analyze(bitmap)
        cutoutBusy.remove(id)

        // The layer may have been deleted or undone away during the ~1s run.
        guard let j = doc.layers.firstIndex(where: { $0.id == id }),
              case .image(let f, _, .dieCut) = doc.layers[j].content else { return }
        guard let sticker = analysis.sticker else {
            // No liftable subject — fall back to the plain photo.
            doc.layers[j].content = .image(file: f, cutoutFile: nil, treatment: .plain)
            showToast(L("No subject found"))
            return
        }
        let newFile = store.saveLayerImage(sticker)
        sessionFiles.insert(newFile)
        doc.layers[j].content = .image(file: f, cutoutFile: newFile, treatment: .dieCut)
    }

    /// Takes an ALREADY-localized string. It cannot localize for you: the
    /// value lands in `toast`, which the editor renders with `Text(String)`
    /// — the non-localizing initialiser — so anything unwrapped here reaches
    /// the screen in English no matter what language the app is in.
    private func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            if toast == text { toast = nil }
        }
    }

    /// Public toast — flashes "Kept ✓" after a save.
    func flashToast(_ text: String) { showToast(text) }

    // MARK: Session end

    /// Keep: persist doc + preview; session files the final document
    /// dropped are orphans.
    func save(preview: UIImage) {
        let kept = Set(doc.layers.flatMap { layer -> [String] in
            switch layer.content {
            case .image(let f, let c, _): return [f] + (c.map { [$0] } ?? [])
            case .sticker(let f): return [f]
            case .text, .doodle: return []
            }
        })
        for file in sessionFiles.subtracting(kept) {
            store.deleteLayerImage(file)
        }
        if let stampID {
            store.updateCanvas(stampID, doc: doc, preview: preview)
        } else {
            store.addCanvas(doc, preview: preview, title: title)
        }
    }

    /// Cancel: every file this session wrote is an orphan — the loaded
    /// document predates them all.
    func cancel() {
        for file in sessionFiles {
            store.deleteLayerImage(file)
        }
    }
}
