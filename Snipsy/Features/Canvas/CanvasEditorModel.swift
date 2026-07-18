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
    var editingTextID: UUID? = nil
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
        if let artifact = session.seedArtifact,
           let image = store.image(for: artifact) {
            let file = store.saveLayerImage(image)
            sessionFiles.insert(file)
            let isSticker = artifact.kind == .sticker
            doc.layers.append(CanvasLayer(
                content: isSticker
                    ? .sticker(file: file)
                    : .image(file: file, cutoutFile: nil, showCutout: false),
                transform: LayerTransform(x: 0.5, y: isSticker ? 0.5 : 0.42,
                                          scale: isSticker ? 0.5 : 0.8)
            ))

            // The caption comes along as a real text layer — the stock's
            // caption band isn't part of the canvas background, and a
            // named memory must not lose its name in the decorate hop.
            // Untitled artifacts carry nothing.
            let caption = session.seedTitle
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !isSticker, !caption.isEmpty {
                var style = TextStyleValue()
                switch artifact.kind {
                case .polaroid:
                    style.design = .handwritten
                    style.weight = 7
                    doc.layers.append(CanvasLayer(
                        content: .text(string: caption, style: style),
                        transform: LayerTransform(x: 0.5, y: 0.89, scale: 0.15,
                                                  rotation: -2 * .pi / 180)))
                default:
                    // Card and stamp paper speak in the engraved voice.
                    style.design = .serif
                    style.weight = 6
                    doc.layers.append(CanvasLayer(
                        content: .text(string: caption.uppercased(), style: style),
                        transform: LayerTransform(
                            x: 0.5, y: artifact.kind == .card ? 0.915 : 0.88,
                            scale: 0.11)))
                }
            }
        }
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
    /// into one invisible pile.
    func addImageLayer(_ image: UIImage, cascade: Int = 0) {
        push()
        let file = store.saveLayerImage(image)
        sessionFiles.insert(file)
        let step = CGFloat(cascade % 5) * 0.04
        let layer = CanvasLayer(
            content: .image(file: file, cutoutFile: nil, showCutout: false),
            transform: LayerTransform(x: 0.5 + step, y: 0.45 + step, scale: 0.55)
        )
        doc.layers.append(layer)
        selectedLayerID = layer.id
    }

    func addTextLayer() {
        push()
        let layer = CanvasLayer(
            content: .text(string: "Your words", style: TextStyleValue()),
            transform: LayerTransform(x: 0.5, y: 0.5, scale: 0.28)
        )
        doc.layers.append(layer)
        selectedLayerID = layer.id
        editingTextID = layer.id
    }

    /// Copy a saved die-cut into the composition — its own file, so the
    /// source sticker can be deleted without breaking this creation.
    func addStickerLayer(from stamp: Stamp) {
        guard let image = store.image(for: stamp) else { return }
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

    func bringForward(_ id: UUID) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }),
              i < doc.layers.count - 1 else { return }
        push()
        doc.layers.swapAt(i, i + 1)
    }

    func sendBackward(_ id: UUID) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }), i > 0 else { return }
        push()
        doc.layers.swapAt(i, i - 1)
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

    // MARK: Cutout

    /// Toggle the die-cut treatment on an image layer. First enable runs
    /// Vision once; after that the flag just flips.
    func toggleCutout(for id: UUID) async {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }),
              case .image(let file, let cutoutFile, let showing) = doc.layers[i].content
        else { return }

        if let cutoutFile {
            push()
            doc.layers[i].content = .image(file: file, cutoutFile: cutoutFile,
                                           showCutout: !showing)
            return
        }
        guard !cutoutBusy.contains(id), let bitmap = store.layerImage(named: file)
        else { return }

        cutoutBusy.insert(id)
        let analysis = await VisionService.analyze(bitmap)
        cutoutBusy.remove(id)

        // The layer may have been deleted or undone away during the ~1s run.
        guard let j = doc.layers.firstIndex(where: { $0.id == id }),
              case .image(let f, _, _) = doc.layers[j].content else { return }
        guard let sticker = analysis.sticker else {
            showToast("No subject found")
            return
        }
        push()
        let newFile = store.saveLayerImage(sticker)
        sessionFiles.insert(newFile)
        doc.layers[j].content = .image(file: f, cutoutFile: newFile, showCutout: true)
    }

    private func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            if toast == text { toast = nil }
        }
    }

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
