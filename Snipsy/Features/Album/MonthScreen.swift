import SwiftUI

/// Inside one folder: the month's stamps, grouped by day, on the same
/// dot-grid paper as the shelf. Nothing here but the month — the shelf is
/// the index, so this page carries no month chrome of its own beyond the
/// title and the folder's own stock colour as a spine down the left.
struct MonthScreen: View {
    let folder: MonthFolder
    let stock: FolderStock
    let model: AppModel
    let screenSize: CGSize
    let safeArea: EdgeInsets
    var onClose: () -> Void

    @Namespace private var ns
    @State private var selected: Stamp? = nil
    @State private var dragX: CGFloat = 0

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE d"; return f
    }()

    /// This month's stamps by calendar day, newest day first.
    private var dayGroups: [(day: Date, title: String, stamps: [Stamp])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: folder.stamps) {
            calendar.startOfDay(for: $0.date)
        }
        return groups.keys.sorted(by: >).map { day in
            (day, Self.dayFormatter.string(from: day),
             groups[day]!.sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        ZStack {
            PaperBackdrop(showsGrid: true)

            VStack(spacing: 0) {
                header
                grid
            }

            if let stamp = selected {
                StampDetailView(
                    stamp: stamp, model: model, ns: ns, screenSize: screenSize,
                    onClose: {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            selected = nil
                        }
                    }
                )
                .zIndex(5)
            }
        }
        .ignoresSafeArea()
        .offset(x: dragX)
        // Horizontal-dominant drags peel the page back; anything vertical
        // belongs to the scroll view.
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    guard selected == nil,
                          value.translation.width > abs(value.translation.height) * 1.6
                    else { return }
                    dragX = max(0, value.translation.width)
                }
                .onEnded { value in
                    if dragX > 90 || value.predictedEndTranslation.width > 220 {
                        close()
                    } else {
                        withAnimation(Theme.springTight) { dragX = 0 }
                    }
                }
        )
    }

    private func close() {
        model.haptics.tick()
        onClose()
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Button {
                close()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 42, height: 42)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 12 }

            // The folder's own stock, standing on end like a spine — the
            // page reads as the inside of the object you just opened.
            Capsule()
                .fill(LinearGradient(colors: [stock.hi, stock.deep],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 5, height: 19)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }

            Text(folder.name)
                .font(Theme.display(30))
                .foregroundStyle(Theme.ink)

            Text("\(folder.year)  ·  \(folder.memoriesLine)")
                .font(Theme.ui(13.5))
                .foregroundStyle(Theme.inkSoft)

            Spacer(minLength: 0)
        }
        // "September 2026 · 12 memories" is the worst case; let it shrink
        // rather than wrap back into the two lines this replaced.
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(.horizontal, 22)
        .padding(.top, max(safeArea.top, 18) + 14)
        .padding(.bottom, 20)
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 34) {
                ForEach(dayGroups, id: \.day) { row in
                    dayBlock(row)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 4)
            .padding(.bottom, safeArea.bottom + 40)
        }
    }

    private func dayBlock(
        _ row: (day: Date, title: String, stamps: [Stamp])
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(row.title)
                    .font(Theme.display(20))
                    .foregroundStyle(Theme.ink.opacity(0.82))
                Line()
                    .stroke(Theme.inkSoft.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, dash: [2.5, 4]))
                    .frame(height: 1)
                Text("\(row.stamps.count)")
                    .font(Theme.ui(12.5))
                    .foregroundStyle(Theme.inkSoft)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 24),
                          GridItem(.flexible(), spacing: 24)],
                spacing: 30
            ) {
                ForEach(Array(row.stamps.enumerated()), id: \.element.id) { i, stamp in
                    cell(stamp, index: i)
                }
            }
        }
    }

    private func cell(_ stamp: Stamp, index: Int) -> some View {
        Button {
            model.haptics.tick()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                selected = stamp
            }
        } label: {
            ArtifactView(stamp: stamp, image: model.store.image(for: stamp))
                .rotationEffect(.degrees(index.isMultiple(of: 2) ? -2.2 : 2.4))
        }
        .buttonStyle(PressableButtonStyle())
        .matchedGeometryEffect(id: stamp.id, in: ns, isSource: selected?.id != stamp.id)
        .opacity(selected?.id == stamp.id ? 0 : 1)
        .modifier(StaggeredAppear(index: index))
    }
}
