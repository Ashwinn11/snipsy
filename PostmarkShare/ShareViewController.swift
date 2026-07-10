import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// The share-sheet entry: any image, from any app, becomes a stamp. Vision
/// lifts the subject, the user picks a paper, Keep drops it straight into
/// the shared collection.
final class ShareViewController: UIViewController {

    private let state = ShareComposerState()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.957, green: 0.937, blue: 0.902, alpha: 1)

        let host = UIHostingController(rootView: ShareComposerView(
            state: state,
            onKeep: { [weak self] in self?.keepAndFinish() },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(
                    withError: NSError(domain: "com.ashwinn.postmark", code: 0))
            }
        ))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)

        loadSharedImage()
    }

    private func loadSharedImage() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) else {
            state.failed = true
            return
        }
        provider.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] item, _ in
            let image: UIImage?
            switch item {
            case let url as URL: image = UIImage(contentsOfFile: url.path)
            case let data as Data: image = UIImage(data: data)
            case let direct as UIImage: image = direct
            default: image = nil
            }
            Task { @MainActor in
                guard let self else { return }
                if let image {
                    await self.state.begin(with: image)
                } else {
                    self.state.failed = true
                }
            }
        }
    }

    private func keepAndFinish() {
        Task { @MainActor in
            state.keep()
            try? await Task.sleep(for: .seconds(0.7))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

/// Runs the same pipeline as an in-app capture: center 4:5 crop → Vision
/// subject lift → sticker with die-cut border → paper choice.
@MainActor
@Observable
final class ShareComposerState {
    var failed = false
    var analyzing = true
    var kept = false
    var variant: StampVariant = .tinted
    var kind: ArtifactKind = .stamp
    var canBeSticker: Bool { pending?.style == .cutout }

    private(set) var pending: PendingStamp? = nil
    private let store = StampStore()

    var nextNumber: Int { store.nextNumber }

    func begin(with raw: UIImage) async {
        // Keep the extension well under its memory ceiling.
        let image = ImageOptimizer.downscaled(
            ImageOptimizer.normalizedOrientation(raw), maxDimension: 2000)

        // Center 4:5 crop — the shape a viewfinder capture would have.
        let px = CGSize(width: image.size.width * image.scale,
                        height: image.size.height * image.scale)
        let target = min(px.width / 4, px.height / 5)
        let cropRect = CGRect(
            x: (px.width - target * 4) / 2,
            y: (px.height - target * 5) / 2,
            width: target * 4, height: target * 5
        )
        guard let crop = FrameGeometry.crop(image, to: cropRect) else {
            failed = true
            return
        }

        let analysis = await VisionService.analyze(
            crop, fallbackCutout: nil, fallbackLabel: nil)
        let hasSubject = analysis.cutout != nil && analysis.sticker != nil
        pending = PendingStamp(
            capture: Capture(
                screenImage: crop, cropImage: crop,
                viewfinderRect: .zero, fallbackCutout: nil, fallbackLabel: nil),
            style: hasSubject ? .cutout : .classic,
            cutout: analysis.cutout,
            sticker: analysis.sticker,
            stickerBox: analysis.stickerBox,
            suggestedTitle: analysis.label,
            tint: analysis.tint
        )
        analyzing = false
    }

    func keep() {
        guard let pending, !kept else { return }
        store.add(pending, title: pending.suggestedTitle ?? "",
                  variant: variant, kind: kind)
        kept = true
    }
}

struct ShareComposerView: View {
    @Bindable var state: ShareComposerState
    var onKeep: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            PaperBackdrop(showsGrid: false)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("POSTMARK")
                        .font(Theme.engraved(15))
                        .tracking(4)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 34, height: 34)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                Spacer(minLength: 0)

                if state.failed {
                    Text("Couldn't read that image.")
                        .font(.system(size: 15, design: .serif))
                        .italic()
                        .foregroundStyle(Theme.inkSoft)
                } else if state.analyzing {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(Theme.inkSoft)
                        Text("Lifting your subject…")
                            .font(.system(size: 14, design: .serif))
                            .italic()
                            .foregroundStyle(Theme.inkSoft)
                    }
                } else if let pending = state.pending {
                    VStack(spacing: 22) {
                        StampView(
                            image: pending.displayImage,
                            style: pending.style,
                            tint: pending.tint.color,
                            title: pending.suggestedTitle ?? "",
                            number: state.nextNumber,
                            year: String(Calendar.current.component(.year, from: Date())),
                            date: .now,
                            variant: state.variant,
                            stickerBox: pending.stickerBox,
                            assembly: state.kind == .sticker
                                ? bareAssembly
                                : .dressed
                        )
                        .frame(width: 210)
                        .shadow(color: Theme.ink.opacity(0.14), radius: 16, y: 9)

                        if state.canBeSticker {
                            HStack(spacing: 10) {
                                kindChip("Sticker", .sticker)
                                kindChip("Stamp", .stamp)
                            }
                        }

                        HStack(spacing: 12) {
                            ForEach(StampVariant.allCases) { v in
                                Button {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                        state.variant = v
                                    }
                                } label: {
                                    StampView(
                                        image: pending.displayImage,
                                        style: pending.style,
                                        tint: pending.tint.color,
                                        title: "",
                                        number: state.nextNumber,
                                        year: "",
                                        variant: v,
                                        stickerBox: pending.stickerBox,
                                        assembly: thumbAssembly
                                    )
                                    .frame(width: 44)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(Theme.postalRed, lineWidth: 1.4)
                                            .padding(-4)
                                            .opacity(state.variant == v ? 1 : 0)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .opacity(state.kind == .stamp ? 1 : 0)
                        .allowsHitTesting(state.kind == .stamp)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    onKeep()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: state.kept ? "checkmark" : "seal.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text(state.kept ? "Kept" : "Keep")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 40)
                    .frame(height: 52)
                    .background(Theme.postalRed, in: Capsule())
                    .opacity(state.pending == nil ? 0.4 : 1)
                }
                .disabled(state.pending == nil || state.kept)
                .padding(.bottom, 26)
            }
        }
    }

    private var thumbAssembly: StampView.Assembly {
        var a = StampView.Assembly()
        a.caption = 0
        return a
    }

    private var bareAssembly: StampView.Assembly {
        StampView.Assembly(paper: 0, caption: 0, content: .final)
    }

    private func kindChip(_ label: String, _ kind: ArtifactKind) -> some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                state.kind = kind
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(state.kind == kind ? .white : Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(state.kind == kind ? Theme.postalRed : Theme.ink.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}
