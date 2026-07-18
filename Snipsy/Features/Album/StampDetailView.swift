import SwiftUI

/// Full-bleed stamp inspection: 3D tilt with a holographic shimmer that
/// follows your finger, inline rename, share, delete.
struct StampDetailView: View {
    let stamp: Stamp
    let model: AppModel
    var ns: Namespace.ID
    let screenSize: CGSize
    var onClose: () -> Void

    /// Live copy — renames elsewhere must reflect immediately.
    private var current: Stamp {
        model.store.stamps.first(where: { $0.id == stamp.id }) ?? stamp
    }

    @State private var tilt: CGSize = .zero
    @State private var editing = false
    @State private var localTitle = ""
    @FocusState private var titleFocused: Bool
    @State private var confirmDelete = false
    @State private var shareImage: Image? = nil
    @State private var shareUIImage: UIImage? = nil

    // Liquid poke — same gesture language as the reveal.
    @State private var rippleCenter: CGPoint = .zero
    @State private var rippleStart: Date? = nil

    var body: some View {
        ZStack {
            PaperBackdrop()
                .onTapGesture {
                    if editing { commitRename() } else { onClose() }
                }
                .transition(.opacity)

            VStack(spacing: 30) {
                Spacer(minLength: 0)

                stampCard

                VStack(spacing: 6) {
                    Text(metaLine)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                }
                .transition(.opacity)

                actions

                Spacer(minLength: 0)
            }
            .padding(.bottom, 16)
        }
        .onAppear { localTitle = current.title }
        .confirmationDialog(
            "Remove this from your collection?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                model.haptics.thunk()
                onClose()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.3))
                    withAnimation(Theme.spring) { model.store.remove(stamp) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Stamp

    private var stampCard: some View {
        let w = min(screenSize.width * 0.76, 350)
        let magnitude = min(1, Double(max(abs(tilt.width), abs(tilt.height))) / 56)

        return TimelineView(.animation(paused: rippleStart == nil)) { timeline in
            let rippleTime = rippleStart.map { timeline.date.timeIntervalSince($0) } ?? 10

            switch current.kind {
            case .polaroid:
                immersed(rippleTime: rippleTime, magnitude: magnitude) {
                    PolaroidView(
                        image: model.store.image(for: current),
                        title: editing ? localTitle : current.title,
                        date: current.date,
                        editableTitle: editing ? $localTitle : nil,
                        titleFocused: $titleFocused,
                        onSubmitTitle: commitRename
                    )
                }
            case .card:
                immersed(rippleTime: rippleTime, magnitude: magnitude) {
                    CardView(
                        image: model.store.image(for: current),
                        title: editing ? localTitle : current.title,
                        date: current.date,
                        editableTitle: editing ? $localTitle : nil,
                        titleFocused: $titleFocused,
                        onSubmitTitle: commitRename
                    )
                }
            case .canvas:
                immersed(rippleTime: rippleTime, magnitude: magnitude) {
                    FlattenedCanvas(image: model.store.image(for: current),
                                    aspect: current.canvas?.aspect ?? CardView.aspect)
                }
            case .stamp, .sticker:
                StampView(
                    image: model.store.image(for: current),
                    style: current.style,
                    tint: current.tint.color,
                    title: editing ? localTitle : current.displayTitle,
                    number: current.number,
                    date: current.date,
                    variant: current.variant,
                    labelAnchor: current.kind == .sticker ? current.labelAnchor : nil,
                    assembly: current.kind == .sticker
                        ? StampView.Assembly(paper: 0, caption: 0, content: .final)
                        : .dressed,
                    holoEnabled: true,
                    holoStrength: magnitude * 0.75,
                    holoSweep: 0.5 + Double(tilt.width) / 220,
                    holoDir: holoDirection,
                    liquidEnabled: true,
                    liquidCenter: rippleCenter,
                    liquidTime: rippleTime,
                    editableTitle: editing ? $localTitle : nil,
                    titleFocused: $titleFocused,
                    onSubmitTitle: commitRename
                )
            }
        }
        .frame(width: w)
        .matchedGeometryEffect(id: stamp.id, in: ns, isSource: true)
        .rotation3DEffect(.degrees(Double(-tilt.height) / 7), axis: (x: 1, y: 0, z: 0))
        .rotation3DEffect(.degrees(Double(tilt.width) / 8), axis: (x: 0, y: 1, z: 0))
        .shadow(color: Theme.shadow.opacity(0.22 + magnitude * 0.1),
                radius: 24 + magnitude * 10, y: 14)
        .gesture(
            SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                if editing {
                    commitRename()
                    return
                }
                rippleCenter = value.location
                let start = Date()
                rippleStart = start
                model.haptics.tick()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.6))
                    if rippleStart == start { rippleStart = nil }
                }
            }
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard !editing else { return }
                    tilt = CGSize(
                        width: max(-60, min(60, value.translation.width)),
                        height: max(-60, min(60, value.translation.height))
                    )
                }
                .onEnded { _ in
                    withAnimation(Theme.springBouncy) { tilt = .zero }
                }
        )
    }

    /// The shimmer + poke the stamp wears internally, worn externally by
    /// the flat artifact kinds. Off while renaming — a live TextField must
    /// never sit under a shader.
    private func immersed<V: View>(
        rippleTime: Double, magnitude: Double, @ViewBuilder _ view: () -> V
    ) -> some View {
        view()
            .modifier(HoloModifier(enabled: !editing,
                                   strength: magnitude * 0.6,
                                   sweep: 0.5 + Double(tilt.width) / 220,
                                   dir: holoDirection))
            .modifier(LiquidModifier(enabled: !editing,
                                     center: rippleCenter,
                                     time: rippleTime))
    }

    private var holoDirection: CGPoint {
        let m = max(1, hypot(tilt.width, tilt.height))
        guard m > 8 else { return CGPoint(x: 1, y: 0.35) }
        return CGPoint(x: tilt.width / m, y: tilt.height / m)
    }

    private var metaLine: String {
        let df = DateFormatter()
        df.dateFormat = "MMMM d, yyyy · h:mm a"
        return "Collected \(df.string(from: current.date))"
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 16) {
            if let artifact = shareArtifact {
                ShareLink(
                    item: artifact,
                    preview: SharePreview(artifact.title, image: artifact.preview)
                ) {
                    actionIcon("square.and.arrow.up")
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }

            if current.kind == .stamp || current.kind == .polaroid
                || current.kind == .card || current.labelAnchor != nil {
                Button {
                    model.haptics.tick()
                    if editing {
                        commitRename()
                    } else {
                        localTitle = current.title
                        editing = true
                        titleFocused = true
                    }
                } label: {
                    actionIcon(editing ? "checkmark" : "pencil")
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }

            Button {
                model.haptics.tick()
                openInCanvas()
            } label: {
                actionIcon("paintbrush")
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Button {
                confirmDelete = true
            } label: {
                actionIcon("trash")
                    .foregroundStyle(Theme.postalRed)
            }
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .task { await renderShareImage() }
    }

    /// Decorate: open this artifact on the canvas — compositions re-open
    /// their live layers, everything else seeds a fresh page.
    private func openInCanvas() {
        if current.kind == .canvas, let doc = current.canvas {
            model.canvasSession = CanvasSession(
                stampID: current.id, seed: doc, seedTitle: current.title)
        } else {
            var doc = CanvasDocument()
            switch current.kind {
            case .stamp: doc.background = .paper(current.variant)
            case .polaroid: doc.background = .polaroid
            default: doc.background = .card
            }
            doc.aspect = CanvasDocument.aspect(for: doc.background)
            model.canvasSession = CanvasSession(
                seed: doc, seedTitle: current.title, seedArtifact: current)
        }
        onClose()
    }

    private func actionIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 54, height: 54)
    }

    private func commitRename() {
        editing = false
        titleFocused = false
        let trimmed = localTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != current.title {
            model.store.rename(current, to: trimmed)
            model.haptics.success()
            // The share render bakes the name in — it must follow.
            Task { @MainActor in await renderShareImage() }
        }
    }

    /// The item in its own form: compositions share their stored flatten,
    /// everything else shares the dressed render (for stickers that is the
    /// die cut wearing its name tag — the stored file is the RAW cut).
    private var shareArtifact: PNGArtifact? {
        if current.kind == .canvas {
            guard let ui = model.store.image(for: current) else { return nil }
            return PNGArtifact(title: current.displayTitle, uiImage: ui)
        }
        guard let ui = shareUIImage else { return nil }
        return PNGArtifact(title: current.displayTitle, uiImage: ui)
    }

    @MainActor
    private func renderShareImage() async {
        // Stickers store the bare die cut; the name label only exists at
        // render time. Composite it here exactly like the drawer copy
        // does, or the export loses the name. Untitled ships bare.
        if current.kind == .sticker {
            guard let base = model.store.image(for: current) else { return }
            if let anchor = current.labelAnchor, !current.title.isEmpty {
                let renderer = ImageRenderer(content: StickerArtifact(
                    image: base, title: current.title, anchor: anchor))
                renderer.scale = 1
                renderer.isOpaque = false
                if let ui = renderer.uiImage {
                    shareUIImage = ui
                    shareImage = Image(uiImage: ui)
                    return
                }
            }
            shareUIImage = base
            shareImage = Image(uiImage: base)
            return
        }

        // Transparent export: the artifact's silhouette IS the edge.
        let aspect: CGFloat = switch current.kind {
        case .polaroid: PolaroidView.aspect
        case .card: CardView.aspect
        case .canvas: current.canvas?.aspect ?? CardView.aspect
        default: 1.3125
        }
        let view = ArtifactView(stamp: current, image: model.store.image(for: current))
            .frame(width: 360, height: 360 * aspect)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.isOpaque = false
        if let ui = renderer.uiImage {
            shareUIImage = ui
            shareImage = Image(uiImage: ui)
        }
    }
}

/// A shareable PNG file — the file representation keeps the alpha channel
/// through every share-sheet activity, including Save Image.
struct PNGArtifact: Transferable {
    let title: String
    let uiImage: UIImage

    var preview: Image { Image(uiImage: uiImage) }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { artifact in
            let name = artifact.title.isEmpty ? "Snipsy" : artifact.title
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(name).png")
            try artifact.uiImage.pngData()?.write(to: url)
            return SentTransferredFile(url)
        }
    }
}
