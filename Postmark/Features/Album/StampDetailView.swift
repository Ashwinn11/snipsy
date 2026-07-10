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

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    if editing { commitRename() } else { onClose() }
                }
                .transition(.opacity)

            VStack(spacing: 30) {
                Spacer(minLength: 0)

                stampCard

                VStack(spacing: 6) {
                    Text(metaLine)
                        .font(.system(size: 14, design: .serif))
                        .italic()
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
            "Remove this stamp from your collection?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Remove Stamp", role: .destructive) {
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

        return StampView(
            image: model.store.image(for: current),
            style: current.style,
            tint: current.tint.color,
            title: editing ? localTitle : current.displayTitle,
            number: current.number,
            year: current.year,
            date: current.date,
            variant: current.variant,
            showsPostmark: true,
            holoEnabled: true,
            holoStrength: magnitude * 0.75,
            holoSweep: 0.5 + Double(tilt.width) / 220,
            holoDir: holoDirection,
            editableTitle: editing ? $localTitle : nil,
            titleFocused: $titleFocused,
            onSubmitTitle: commitRename
        )
        .frame(width: w)
        .matchedGeometryEffect(id: stamp.id, in: ns, isSource: true)
        .rotation3DEffect(.degrees(Double(-tilt.height) / 7), axis: (x: 1, y: 0, z: 0))
        .rotation3DEffect(.degrees(Double(tilt.width) / 8), axis: (x: 0, y: 1, z: 0))
        .shadow(color: Theme.ink.opacity(0.10 + magnitude * 0.08),
                radius: 24 + magnitude * 10, y: 14)
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
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    preview: SharePreview(stamp.displayTitle, image: shareImage)
                ) {
                    actionIcon("square.and.arrow.up")
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }

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
        }
    }

    @MainActor
    private func renderShareImage() async {
        let view = StampView(stamp: current, image: model.store.image(for: current))
            .frame(width: 360, height: 472.5)
            .background(Theme.paper)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
        }
    }
}
