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
        view.backgroundColor = UIColor(red: 0.094, green: 0.082, blue: 0.059, alpha: 1)

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
        // Decode bounded, never full-res: extensions live under a ~120 MB
        // ceiling and a 12–48 MP decode is an instant jetsam (the app
        // "opens and closes"). The thumbnail decode also applies EXIF
        // orientation for free. 1400 px (not the app's 2000): the subject-
        // lift model alone eats most of the ceiling on device, and every
        // Vision/CoreImage buffer downstream scales with this bound —
        // stored output tops out at 1600 px anyway.
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) {
            [weak self] url, _ in
            let image = url.flatMap { ImageOptimizer.downsampled(url: $0, maxPixel: 1400) }
            if let image {
                Task { @MainActor in
                    guard let self else { return }
                    await self.state.begin(with: image)
                }
                return
            }
            // Some providers only vend data.
            self?.loadFromData(provider)
        }
    }

    private func loadFromData(_ provider: NSItemProvider) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
            [weak self] data, _ in
            let image = data.flatMap { ImageOptimizer.downsampled(data: $0, maxPixel: 1400) }
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
    enum Choice: Equatable {
        case sticker
        case paper(StampVariant)
    }

    var failed = false
    var analyzing = true
    var kept = false
    var choice: Choice? = nil
    /// The sticker can't be cut here (no memory budget for the model) —
    /// choosing it parks the photo for the app to finish.
    var stickerDeferred = false

    private(set) var pending: PendingStamp? = nil
    private let store = StampStore()

    var nextNumber: Int { store.nextNumber }

    /// Remaining jetsam budget in MB; 0 means "not limited" (main app).
    private static var availableMB: Int {
        Int(os_proc_available_memory() >> 20)
    }

    func begin(with image: UIImage) async {
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

        // Subject lifting loads Vision's segmentation net in-process —
        // it does NOT fit this extension's jetsam budget on A14-class
        // devices (measured: killed even on downscaled input). Where it
        // can't run, the sticker option stays available but hands the
        // photo to the app via ShareInbox instead of dying mid-sheet.
        let budget = Self.availableMB
        let lift = budget == 0 || budget >= 150
        stickerDeferred = !lift
        let analysis = await VisionService.analyze(
            crop, subjectLift: lift)
        let hasSubject = analysis.cutout != nil && analysis.sticker != nil
        pending = PendingStamp(
            capture: Capture(
                screenImage: crop, cropImage: crop,
                viewfinderRect: .zero),
            style: hasSubject ? .cutout : .classic,
            cutout: analysis.cutout,
            sticker: analysis.sticker,
            stickerBox: analysis.stickerBox,
            stickerLabelAnchor: analysis.labelAnchor,
            suggestedTitle: analysis.label,
            tint: analysis.tint
        )
        analyzing = false
    }

    func keep() {
        guard let pending, let choice, !kept else { return }
        switch choice {
        case .sticker where stickerDeferred:
            // The app cuts it on next launch — park the full crop.
            ShareInbox.deposit(pending.capture.cropImage)
        case .sticker:
            store.add(pending, title: pending.suggestedTitle ?? "",
                      variant: .tinted, kind: .sticker)
        case .paper(let v):
            store.add(pending, title: pending.suggestedTitle ?? "",
                      variant: v, kind: .stamp)
        }
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
                            variant: previewVariant,
                            stickerBox: pending.stickerBox,
                            rawCrop: pending.capture.cropImage,
                            maskImage: pending.cutout,
                            labelAnchor: pending.stickerLabelAnchor,
                            assembly: previewAssembly
                        )
                        .frame(width: 210)
                        .shadow(color: Theme.shadow.opacity(0.45), radius: 16, y: 9)

                        HStack(spacing: 11) {
                            if pending.style == .cutout, let sticker = pending.sticker {
                                optionButton(.sticker) {
                                    Image(uiImage: sticker)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 44, height: 56)
                                }
                            } else if state.stickerDeferred {
                                // No cutout to preview here — the scissors
                                // badge marks a sticker the app will cut.
                                optionButton(.sticker) {
                                    Image(uiImage: pending.capture.cropImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                        .overlay(alignment: .bottomTrailing) {
                                            Image(systemName: "scissors")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(4)
                                                .background(Theme.postalRed, in: Circle())
                                                .offset(x: 5, y: 5)
                                        }
                                }
                            }
                            ForEach(StampVariant.allCases) { v in
                                optionButton(.paper(v)) {
                                    StampView(
                                        image: pending.displayImage,
                                        style: pending.style,
                                        tint: pending.tint.color,
                                        title: "",
                                        number: state.nextNumber,
                                        year: "",
                                        variant: v,
                                        stickerBox: pending.stickerBox,
                                        rawCrop: pending.capture.cropImage,
                                        assembly: thumbAssembly
                                    )
                                    .frame(width: 44)
                                }
                            }
                        }

                        if state.stickerDeferred, state.choice == .sticker {
                            Text("The sticker finishes in Postmark — open the app to find it.")
                                .font(.system(size: 12, design: .serif))
                                .italic()
                                .foregroundStyle(Theme.inkSoft)
                        }
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
                    .opacity(state.pending == nil || state.choice == nil ? 0.4 : 1)
                }
                .disabled(state.pending == nil || state.choice == nil || state.kept)
                .padding(.bottom, 26)
            }
        }
    }

    private var thumbAssembly: StampView.Assembly {
        StampView.Assembly(paper: 1, caption: 0, settle: 1,
                           border: 0, waste: 1, content: .raw)
    }

    /// Raw crop until a choice is made, then the chosen form. Stamps frame
    /// the whole photo; only stickers are die-cut.
    private var previewAssembly: StampView.Assembly {
        switch state.choice {
        case nil:
            return StampView.Assembly(paper: 0, caption: 0, settle: 0,
                                      border: 0, waste: 1, content: .raw)
        case .sticker:
            // flight composes the cut piece at its frame; border alone no
            // longer moves the sheet (it only draws the outline).
            return StampView.Assembly(paper: 0, caption: 0, settle: 1,
                                      border: 1, flight: 1, waste: 0, content: .raw)
        case .paper:
            return StampView.Assembly(paper: 1, caption: 1, settle: 1,
                                      border: 0, waste: 1, content: .raw)
        }
    }

    private var previewVariant: StampVariant {
        if case .paper(let v) = state.choice { return v }
        return .tinted
    }

    private func optionButton<Preview: View>(
        _ choice: ShareComposerState.Choice,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                state.choice = choice
            }
        } label: {
            preview()
                .frame(width: 48, height: 58)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.postalRed, lineWidth: 1.4)
                        .padding(-4)
                        .opacity(state.choice == choice ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
    }
}
