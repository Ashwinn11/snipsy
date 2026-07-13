import SwiftUI

/// The collector's book: serif day headers, a two-column grid of slightly
/// tilted stamps on dot-grid paper, matched-geometry morph into detail.
struct AlbumScreen: View {
    let model: AppModel
    let safeArea: EdgeInsets

    @Namespace private var ns
    @State private var selected: Stamp? = nil
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PaperBackdrop(showsGrid: true)

                VStack(spacing: 0) {
                    header(topInset: safeArea.top)
                    if model.store.stamps.isEmpty {
                        EmptyAlbumView()
                            .frame(maxHeight: .infinity)
                    } else {
                        grid(bottomInset: safeArea.bottom)
                    }
                }

                if let stamp = selected {
                    StampDetailView(
                        stamp: stamp,
                        model: model,
                        ns: ns,
                        screenSize: geo.size,
                        onClose: {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                selected = nil
                            }
                        }
                    )
                    .zIndex(5)
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showSettings) {
            SettingsSheet(model: model) {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.35))
                    withAnimation(.easeInOut(duration: 0.5)) {
                        model.deleteAllData()
                    }
                }
            }
        }
    }

    // MARK: Header

    private func header(topInset: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Collection")
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.ink)
                Text(countLine)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Button {
                model.haptics.tick()
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 42, height: 42)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Button {
                model.haptics.tick()
                withAnimation(Theme.spring) { model.showAlbum = false }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 42, height: 42)
            }
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .padding(.horizontal, 26)
        .padding(.top, max(topInset, 18) + 14)
        .padding(.bottom, 20)
    }

    private var countLine: String {
        let n = model.store.stamps.count
        return n == 1 ? "1 stamp" : "\(n) stamps"
    }

    // MARK: Timeline

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f
    }()
    private static let monthNameFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM"; return f
    }()

    /// The timeline grouped month-first: each section owns its day groups,
    /// and its header is the pinnable month divider.
    private var monthSections:
        [(month: Date, title: String, days: [(day: Date, title: String, stamps: [Stamp])])] {
        let calendar = Calendar.current
        var out: [(month: Date, title: String,
                   days: [(day: Date, title: String, stamps: [Stamp])])] = []
        for group in model.store.dayGroups {
            let month = calendar.dateInterval(of: .month, for: group.day)?.start ?? group.day
            let day = (day: group.day, title: group.title, stamps: group.stamps)
            if out.last?.month == month {
                out[out.count - 1].days.append(day)
            } else {
                out.append((month, Self.monthTitleFormatter.string(from: month), [day]))
            }
        }
        return out
    }

    /// Every month in the collection, newest first — the jump menu's entries.
    private var months: [(month: Date, label: String)] {
        let calendar = Calendar.current
        var seen = Set<Date>()
        var out: [(Date, String)] = []
        for group in model.store.dayGroups {
            let month = calendar.dateInterval(of: .month, for: group.day)?.start ?? group.day
            guard seen.insert(month).inserted else { continue }
            out.append((month, Self.monthNameFormatter.string(from: month)))
        }
        return out
    }

    /// Months grouped by year, newest first — the jump menu shows year
    /// sections only when the collection actually spans years.
    private var jumpYears: [(year: Int, months: [(month: Date, label: String)])] {
        let calendar = Calendar.current
        var out: [(year: Int, months: [(month: Date, label: String)])] = []
        for m in months {
            let year = calendar.component(.year, from: m.month)
            if out.last?.year == year {
                out[out.count - 1].months.append(m)
            } else {
                out.append((year, [m]))
            }
        }
        return out
    }

    /// The month divider IS the navigation: it pins to the top while its
    /// month scrolls past (you always know where you are), and tapping it
    /// opens the jump menu. No chip rows, no extra chrome.
    @ViewBuilder
    private func monthHeader(month: Date, title: String,
                             proxy: ScrollViewProxy) -> some View {
        if months.count > 1 {
            Menu {
                if jumpYears.count > 1 {
                    ForEach(jumpYears, id: \.year) { group in
                        Section(String(group.year)) {
                            monthButtons(group.months, current: month, proxy: proxy)
                        }
                    }
                } else {
                    monthButtons(months, current: month, proxy: proxy)
                }
            } label: {
                headerLine(title, chevron: true)
            }
            .buttonStyle(.plain)
            .background(Theme.paper.padding(.horizontal, -26))
        } else {
            headerLine(title, chevron: false)
                .background(Theme.paper.padding(.horizontal, -26))
        }
    }

    private func monthButtons(_ items: [(month: Date, label: String)],
                              current: Date, proxy: ScrollViewProxy) -> some View {
        ForEach(items, id: \.month) { m in
            Button {
                model.haptics.tick()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    proxy.scrollTo(m.month, anchor: .top)
                }
            } label: {
                if m.month == current {
                    Label(m.label, systemImage: "checkmark")
                } else {
                    Text(m.label)
                }
            }
        }
    }

    private func headerLine(_ title: String, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.ink)
                if chevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            Line()
                .stroke(Theme.inkSoft.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1, dash: [2.5, 4]))
                .frame(height: 1)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    // MARK: Grid

    private func grid(bottomInset: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 34,
                           pinnedViews: [.sectionHeaders]) {
                    ForEach(monthSections, id: \.month) { section in
                        Section {
                            ForEach(section.days, id: \.day) { row in
                                dayBlock(row)
                            }
                        } header: {
                            monthHeader(month: section.month, title: section.title,
                                        proxy: proxy)
                                .id(section.month)
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 4)
                .padding(.bottom, bottomInset + 36)
            }
        }
    }

    private func dayBlock(
        _ row: (day: Date, title: String, stamps: [Stamp])
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.title)
                    .font(Theme.display(21))
                    .foregroundStyle(Theme.ink.opacity(0.8))
                Text(row.stamps.count == 1 ? "1 stamp" : "\(row.stamps.count) stamps")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 24),
                    GridItem(.flexible(), spacing: 24),
                ],
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
            StampView(stamp: stamp, image: model.store.image(for: stamp))
                .rotationEffect(.degrees(index.isMultiple(of: 2) ? -2.2 : 2.4))
        }
        .buttonStyle(PressableButtonStyle())
        .matchedGeometryEffect(id: stamp.id, in: ns, isSource: selected?.id != stamp.id)
        .opacity(selected?.id == stamp.id ? 0 : 1)
        .modifier(StaggeredAppear(index: index))
    }
}

/// Cells drift up and fade in, staggered by grid position.
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .onAppear {
                withAnimation(Theme.springBouncy.delay(Double(index % 8) * 0.05)) {
                    shown = true
                }
            }
    }
}

/// A dotted stamp outline inviting the first capture.
struct EmptyAlbumView: View {
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 22) {
            PerforatedRect()
                .stroke(Theme.inkSoft.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.4, dash: [4, 5]))
                .frame(width: 132, height: 173)
                .overlay {
                    Image(systemName: "camera")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.inkSoft.opacity(0.8))
                }
                .scaleEffect(breathe ? 1.03 : 0.99)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                           value: breathe)
                .onAppear { breathe = true }

            VStack(spacing: 7) {
                Text("Your first stamp awaits")
                    .font(Theme.display(21))
                    .foregroundStyle(Theme.ink)
                Text("Frame something you love and press the shutter.")
                    .font(.system(size: 14.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.bottom, 70)
    }
}
