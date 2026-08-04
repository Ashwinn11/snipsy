import SwiftUI

/// The collector's shelf: one folder per month, stacked down the page.
/// Tapping a folder opens its cover and slides the stamps out; tapping
/// twice goes inside — as does tapping any stamp once it is out.
struct AlbumScreen: View {
    let model: AppModel
    let safeArea: EdgeInsets

    /// The folder currently showing its contents — one at a time.
    @State private var openMonth: Date? = nil
    /// The month drilled into. Held as a date, not a snapshot, so the page
    /// stays live against the store (and dismisses if the month empties).
    @State private var pushedMonth: Date? = nil

    private var folders: [MonthFolder] {
        model.store.folders
    }

    /// The pushed month resolved against the current store.
    private var pushed: (folder: MonthFolder, index: Int)? {
        guard let month = pushedMonth,
              let i = folders.firstIndex(where: { $0.month == month })
        else { return nil }
        return (folders[i], i)
    }

    var body: some View {
        GeometryReader { geo in
            // The fan reaches 1.15 W right of the folder's centre, so the
            // row budget is 1.65 W plus margins.
            let folderWidth = min(164, geo.size.width * 0.42)

            ZStack {
                PaperBackdrop(showsGrid: true)
                    .contentShape(Rectangle())
                    .onTapGesture { closePreview() }

                VStack(spacing: 0) {
                    header(topInset: safeArea.top)
                    if model.store.stamps.isEmpty {
                        EmptyAlbumView()
                            .frame(maxHeight: .infinity)
                    } else {
                        shelf(bottomInset: safeArea.bottom,
                              folderWidth: folderWidth)
                    }
                }
                .scaleEffect(pushed == nil ? 1 : 0.96)

                if let pushed {
                    MonthScreen(
                        folder: pushed.folder,
                        stock: FolderStock.stock(at: pushed.index),
                        model: model,
                        screenSize: geo.size,
                        safeArea: safeArea,
                        onClose: {
                            withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) {
                                pushedMonth = nil
                            }
                        }
                    )
                    .transition(.move(edge: .trailing))
                    .zIndex(8)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { MemoryProbe.log("album open") }
        // Drilled into a month (or a stamp's detail beyond it): that view's
        // own back button handles the way out, so the tab bar steps aside.
        .toolbar(pushed == nil ? .visible : .hidden, for: .tabBar)
    }

    // MARK: Header

    private func header(topInset: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Collection")
                .font(Theme.display(26))
                .foregroundStyle(Theme.ink)

            Spacer()
        }
        .padding(.horizontal, 26)
        .padding(.top, max(topInset, 18) + 14)
        .padding(.bottom, 20)
    }

    // MARK: Shelf

    private func shelf(bottomInset: CGFloat, folderWidth: CGFloat) -> some View {
        let overhang = folderWidth * FolderGeometry.aspect
            * (FolderGeometry.openMagnification - 1) / 2
        return ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 34) {
                ForEach(Array(folders.enumerated()), id: \.element.id) { i, folder in
                    shelfRow(folder, index: i, folderWidth: folderWidth)
                }
            }
            .padding(.horizontal, 26)
            // The open cover magnifies to 1.30 H, overhanging its row by
            // 0.15 H at EACH end. Without this the scroll view clips the
            // top row's cover the moment it opens.
            .padding(.top, overhang + 8)
            .padding(.bottom, bottomInset + overhang + 44)
            // Anything landing between or below the rows is empty space.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { closePreview() }
            }
        }
    }

    private func shelfRow(_ folder: MonthFolder, index: Int,
                          folderWidth: CGFloat) -> some View {
        let isOpen = openMonth == folder.month
        return HStack(spacing: 0) {
            MonthFolderView(
                folder: folder,
                store: model.store,
                stock: FolderStock.stock(at: index),
                open: isOpen ? 1 : 0,
                width: folderWidth
            )
            // ONE gesture pair, on the folder, resolved by where you tapped.
            //
            // Exclusively, not two stacked .onTapGesture — that fires the
            // single tap immediately and the preview flickers under the push.
            // Spatial, because the single tap has to tell the cover apart
            // from the stamps beside it, and a gesture hung on each slip
            // loses the race against this pair.
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { _ in drill(folder) }
                    .exclusively(before: SpatialTapGesture(count: 1).onEnded { tap in
                        let coverEdge = folderWidth * FolderGeometry.openCoverExtent
                        if isOpen, tap.location.x > coverEdge {
                            // Past the open cover: the stamps. Go inside.
                            drill(folder)
                        } else {
                            preview(folder)
                        }
                    })
            )

            Spacer(minLength: 0)
        }
        .frame(height: folderWidth * FolderGeometry.aspect)
        // An open fan must draw over the rows below it.
        .zIndex(isOpen ? 1 : 0)
        // The rest of the row dismisses. The folder's own gestures are on a
        // child, so they take precedence over this.
        .contentShape(Rectangle())
        .onTapGesture { closePreview() }
        .modifier(StaggeredAppear(index: index))
    }

    /// Empty space dismisses. Silent when nothing is open, so a stray tap
    /// on the page does not fire a haptic for no visible reason.
    private func closePreview() {
        guard openMonth != nil else { return }
        model.haptics.tick()
        withAnimation(FolderGeometry.curve) { openMonth = nil }
    }

    private func preview(_ folder: MonthFolder) {
        model.haptics.tick()
        // The reference's own easing: 0.7s cubic-bezier(.23,1,.32,1). It
        // glides to a stop — a spring here reads as a different object.
        withAnimation(FolderGeometry.curve) {
            openMonth = (openMonth == folder.month) ? nil : folder.month
        }
    }

    private func drill(_ folder: MonthFolder) {
        model.haptics.thunk()
        // The cover swings as the page slides in — the folder you opened is
        // still open behind you when you come back.
        withAnimation(FolderGeometry.curve) {
            openMonth = folder.month
            pushedMonth = folder.month
        }
    }
}

/// Cells drift up and fade in, staggered by position.
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
                    .font(Theme.ui(14.5))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.bottom, 70)
    }
}
