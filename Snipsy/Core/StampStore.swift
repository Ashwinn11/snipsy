import SwiftUI
import UIKit
import Observation

/// Hand-off lane from the share extension to the app. Devices whose
/// extension memory budget cannot hold Vision's subject-lift model
/// (measured: A14-class cannot, even on downscaled input) park the
/// shared photo here; the app finishes the sticker on its next launch,
/// where the model has room.
enum ShareInbox {
    private static var dir: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: StampStore.appGroup)?
            .appendingPathComponent("Snipsy/inbox", isDirectory: true)
    }

    /// Park a crop for the app to finish as a sticker. A name typed in the
    /// share sheet rides along as a sidecar so the finished sticker keeps it.
    static func deposit(_ image: UIImage, title: String? = nil) {
        guard let dir else { return }
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        guard let data = ImageOptimizer.optimized(image) else { return }
        let id = UUID().uuidString
        try? data.write(
            to: dir.appendingPathComponent("\(id).heic"),
            options: .atomic)
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty {
            try? name.data(using: .utf8)?.write(
                to: dir.appendingPathComponent("\(id).title"),
                options: .atomic)
        }
    }

    /// Every parked crop (and its typed name, if any), consuming the files.
    static func drain() -> [(image: UIImage, title: String?)] {
        guard let dir,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "heic" }.compactMap { url in
            let titleURL = url.deletingPathExtension().appendingPathExtension("title")
            defer {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: titleURL)
            }
            guard let data = try? Data(contentsOf: url),
                  let image = ImageOptimizer.downsampled(data: data)
            else { return nil }
            return (image, try? String(contentsOf: titleURL, encoding: .utf8))
        }
    }
}

/// Owns the collection: stamps.json + one PNG per stamp under Documents.
@MainActor
@Observable
final class StampStore {

    private(set) var stamps: [Stamp] = [] {  // newest first
        didSet { rebuildFolders() }
    }
    private(set) var folders: [MonthFolder] = []

    private func rebuildFolders() {
        folders = MonthFolder.shelf(from: stamps)
    }

    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()

    /// Layer bitmaps whose bytes have not reached disk yet. `cache` cannot
    /// hold them on its own: NSCache purges under memory pressure by
    /// design, and these are created during canvas editing — the app's
    /// memory peak. A strong reference here keeps the pixels reachable
    /// until the write confirms.
    @ObservationIgnored private var pendingLayerWrites: [String: UIImage] = [:]

    nonisolated static let appGroup = "group.com.ashwinn.postmark"

    /// Shared with the Messages sticker extension. Falls back to Documents
    /// if the group container is unavailable.
    private let root: URL = {
        let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: StampStore.appGroup)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Snipsy", isDirectory: true)
    }()
    private var imagesDir: URL { root.appendingPathComponent("images", isDirectory: true) }
    /// PNG die-cuts for the Messages drawer (MSSticker cannot read HEIC).
    private var stickersDir: URL { root.appendingPathComponent("stickers", isDirectory: true) }
    private var indexURL: URL { root.appendingPathComponent("stamps.json") }

    private static var isExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    init() {
        // A budget the cache can plan against. Without one NSCache only ever
        // evicts *reactively*, after iOS has already fired a memory warning —
        // and that purge is what used to strand half-written layer bitmaps.
        // An eighth of physical RAM sits inside the 10–20%-of-available
        // guidance on every device this ships to; the clamp keeps a 3 GB
        // iPhone from over-committing against its ~900 MB jetsam budget and a
        // 16 GB iPad from hoarding.
        cache.totalCostLimit = min(max(Int(ProcessInfo.processInfo.physicalMemory) / 8,
                                       64 << 20), 256 << 20)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: stickersDir, withIntermediateDirectories: true)
        load()
        if !Self.isExtension { backfillDrawer() }
    }

    // MARK: Cache

    /// The single funnel for every cache insert. Costed by the real decoded
    /// size — a bare `setObject` tells NSCache nothing about how much a
    /// multi-megabyte bitmap actually weighs, so it evicts on guesswork.
    private func cacheImage(_ image: UIImage, for key: String) {
        let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    /// Grid-cell resolution. Covers an 84 pt sheet cell and a ~110 pt album
    /// cell at 3×; one fixed size means one thumb key per file, which is what
    /// makes invalidation tractable (NSCache cannot enumerate its keys).
    static let thumbnailPixels: CGFloat = 400

    private func thumbKey(_ file: String) -> String { "t:" + file }

    /// Drop both tiers for a file. Every site that deletes or replaces an
    /// image must call this, or a stale thumbnail outlives its source.
    private func evict(_ file: String) {
        cache.removeObject(forKey: file as NSString)
        cache.removeObject(forKey: thumbKey(file) as NSString)
    }

    /// Cell-sized copy for grids. Decodes straight to size via ImageIO, so
    /// the full bitmap is never materialized just to be shrunk — roughly 840 KB
    /// resident against the ~7.8 MB a full-size read costs.
    func thumbnail(for stamp: Stamp) -> UIImage? {
        let file = stamp.imageFile
        let key = thumbKey(file)
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let url = imagesDir.appendingPathComponent(file)
        guard let small = ImageOptimizer.downsampled(url: url,
                                                     maxPixel: Self.thumbnailPixels)
        else {
            // Freshly added stamps are served from the full-size cache until
            // their detached write lands; there is no file to downsample yet.
            return image(for: stamp)
        }
        cacheImage(small, for: key)
        return small
    }

    /// Drawer copy for one item: sticker items ship the bare die-cut; stamp
    /// items ship the dressed collectible rendered with a transparent
    /// perforated silhouette. Rendering happens on the main actor; the write
    /// goes off-main.
    private func writeDrawerCopy(for stamp: Stamp, display: UIImage) {
        let destination = stickersDir.appendingPathComponent("\(stamp.id.uuidString).png")
        let data: Data?
        if stamp.kind == .sticker {
            // Live label composite when we know the contour; legacy items
            // already have it baked in.
            if let anchor = stamp.labelAnchor {
                let renderer = ImageRenderer(content: StickerArtifact(
                    image: display, title: stamp.title, anchor: anchor))
                renderer.scale = 1
                renderer.isOpaque = false
                data = renderer.uiImage.flatMap { ImageOptimizer.stickerPNG($0) }
            } else {
                data = ImageOptimizer.stickerPNG(display)
            }
        } else if stamp.kind == .canvas {
            // The flatten already happened at save — don't re-render.
            data = ImageOptimizer.stickerPNG(display)
        } else {
            let aspect: CGFloat = switch stamp.kind {
            case .polaroid: PolaroidView.aspect
            case .card: CardView.aspect
            default: 1.3125
            }
            let renderer = ImageRenderer(content:
                ArtifactView(stamp: stamp, image: display)
                    .frame(width: 400, height: 400 * aspect))
            renderer.scale = 1.5
            renderer.isOpaque = false
            data = renderer.uiImage.flatMap { ImageOptimizer.stickerPNG($0) }
        }
        guard let data else { return }
        Task.detached(priority: .utility) {
            try? data.write(to: destination, options: .atomic)
        }
    }

    /// Regenerate drawer copies: once after the format change (v2 wipes the
    /// old bare-cutout copies), then only for items missing a copy.
    private func backfillDrawer() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "snipsy.drawerV2") {
            try? FileManager.default.removeItem(at: stickersDir)
            try? FileManager.default.createDirectory(
                at: stickersDir, withIntermediateDirectories: true)
            defaults.set(true, forKey: "snipsy.drawerV2")
        }
        let missing = stamps.filter {
            !FileManager.default.fileExists(
                atPath: stickersDir.appendingPathComponent("\($0.id.uuidString).png").path)
        }
        guard !missing.isEmpty else { return }
        Task { @MainActor in
            for stamp in missing {
                guard let display = image(for: stamp) else { continue }
                writeDrawerCopy(for: stamp, display: display)
                await Task.yield()
            }
        }
    }

    var nextNumber: Int { (stamps.map(\.number).max() ?? 0) + 1 }

    @discardableResult
    func add(_ pending: PendingStamp, title: String, variant: StampVariant,
             kind: ArtifactKind = .stamp) -> Stamp {
        let id = UUID()
        let file = "\(id.uuidString).heic"
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Stickers store the RAW die cut — the name label is composited at
        // render time (fixable, renamable). Stamps store the framed photo.
        let display: UIImage
        let style: Stamp.Style
        switch kind {
        case .sticker:
            display = pending.displayImage
            style = .cutout
        case .stamp, .polaroid, .card, .canvas:
            // Instant-photo idiom: the full crop fills the frame. (.canvas
            // never arrives here — compositions come through addCanvas.)
            display = pending.capture.cropImage
            style = .classic
        }
        // Optimize + write off-main: done here it stalls the fly-out fade.
        // The in-memory cache serves reads until the files land.
        let destination = imagesDir.appendingPathComponent(file)
        Task.detached(priority: .utility) {
            if let data = ImageOptimizer.optimized(display) {
                try? data.write(to: destination, options: .atomic)
            }
        }
        let stamp = Stamp(
            id: id,
            title: trimmed,
            date: Date(),
            number: nextNumber,
            style: style,
            tint: pending.tint,
            imageFile: file,
            variant: variant,
            kind: kind,
            labelAnchor: kind == .sticker ? (pending.stickerLabelAnchor ?? 0.945) : nil
        )
        cacheImage(display, for: file)
        stamps.insert(stamp, at: 0)
        save()
        writeDrawerCopy(for: stamp, display: display)
        return stamp
    }

    /// Keep a finished composition: the flattened preview is the stamp's
    /// image, the layer document rides the index for re-editing.
    @discardableResult
    func addCanvas(_ doc: CanvasDocument, preview: UIImage, title: String) -> Stamp {
        let id = UUID()
        let file = "\(id.uuidString).heic"
        let destination = imagesDir.appendingPathComponent(file)
        Task.detached(priority: .utility) {
            if let data = ImageOptimizer.optimized(preview) {
                try? data.write(to: destination, options: .atomic)
            }
        }
        let stamp = Stamp(
            id: id,
            // The date the user set in the editor, NOT the moment they hit
            // save. It is already printed on the stamp's header, so filing
            // the memory under today instead made the picker cosmetic —
            // a backdated memory landed in the wrong month.
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: doc.date,
            number: nextNumber,
            style: .classic,
            tint: .paper,
            imageFile: file,
            variant: .tinted,
            kind: .canvas,
            labelAnchor: nil,
            canvas: doc
        )
        cacheImage(preview, for: file)
        insertNewestFirst(stamp)
        save()
        writeDrawerCopy(for: stamp, display: preview)
        return stamp
    }

    /// `stamps` is documented newest-first and the album leans on that, so
    /// a backdated memory cannot simply go at index 0.
    private func insertNewestFirst(_ stamp: Stamp) {
        let i = stamps.firstIndex { $0.date <= stamp.date } ?? stamps.count
        stamps.insert(stamp, at: i)
    }

    /// Re-save an edited composition in place — id and number survive.
    /// The date follows the document: it is user-editable, so changing it
    /// has to re-file the memory, not just reprint its header.
    func updateCanvas(_ id: UUID, doc: CanvasDocument, preview: UIImage) {
        guard let i = stamps.firstIndex(where: { $0.id == id }) else { return }
        let oldFiles = Set(stamps[i].allImageFiles)
        stamps[i].canvas = doc
        stamps[i].date = doc.date
        let kept = Set(stamps[i].allImageFiles)
        for file in oldFiles.subtracting(kept) {
            try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(file))
            evict(file)
        }
        let destination = imagesDir.appendingPathComponent(stamps[i].imageFile)
        Task.detached(priority: .utility) {
            if let data = ImageOptimizer.optimized(preview) {
                try? data.write(to: destination, options: .atomic)
            }
        }
        // Same file name, new pixels — the old thumbnail is now a lie, so
        // drop it before seeding the full-size tier with the fresh preview.
        evict(stamps[i].imageFile)
        cacheImage(preview, for: stamps[i].imageFile)
        // Re-filing invalidates `i`, so take the value before sorting.
        let updated = stamps[i]
        stamps.sort { $0.date > $1.date }
        save()
        writeDrawerCopy(for: updated, display: preview)
    }

    /// Park a canvas layer bitmap under images/; returns its file name.
    /// Pinned in `pendingLayerWrites` until the bytes land, so a cache
    /// purge mid-edit can never leave the layer pointing at nothing.
    func saveLayerImage(_ image: UIImage) -> String {
        let file = "\(UUID().uuidString).heic"
        let destination = imagesDir.appendingPathComponent(file)
        pendingLayerWrites[file] = image
        cacheImage(image, for: file)
        Task.detached(priority: .userInitiated) {
            // PNG fallback: a bitmap HEIC can't encode still has to reach
            // disk, or the document keeps a reference to pixels that no
            // longer exist anywhere and the layer is gone for good.
            guard let data = ImageOptimizer.optimized(image) ?? image.pngData()
            else { return }
            // Atomic: a reader arriving mid-write decodes a truncated file
            // and gets nil — the same blank layer by a different route.
            guard (try? data.write(to: destination, options: .atomic)) != nil
            else { return }
            await self.finishLayerWrite(file)
        }
        return file
    }

    /// The bytes are on disk — reads can fall back to the file now.
    private func finishLayerWrite(_ file: String) {
        pendingLayerWrites[file] = nil
    }

    /// Remove an orphaned layer file (editor cancel / undo GC).
    func deleteLayerImage(_ file: String) {
        pendingLayerWrites[file] = nil
        try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(file))
        evict(file)
    }

    /// Any image under images/ by file name (canvas layers).
    func layerImage(named file: String) -> UIImage? {
        if let pinned = pendingLayerWrites[file] { return pinned }
        if let cached = cache.object(forKey: file as NSString) { return cached }
        let url = imagesDir.appendingPathComponent(file)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cacheImage(image, for: file)
        return image
    }

    func remove(_ stamp: Stamp) {
        stamps.removeAll { $0.id == stamp.id }
        for file in stamp.allImageFiles {
            try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(file))
            evict(file)
        }
        try? FileManager.default.removeItem(
            at: stickersDir.appendingPathComponent("\(stamp.id.uuidString).png"))
        save()
    }

    /// Re-read the index — the share extension may have added stamps while
    /// the app was backgrounded.
    func reload() {
        load()
    }

    /// Settings → Delete All Data: every stamp, photo, sticker, the index.
    func deleteAll() {
        for stamp in stamps {
            for file in stamp.allImageFiles {
                try? FileManager.default.removeItem(
                    at: imagesDir.appendingPathComponent(file))
            }
            try? FileManager.default.removeItem(
                at: stickersDir.appendingPathComponent("\(stamp.id.uuidString).png"))
        }
        stamps.removeAll()
        cache.removeAllObjects()
        save()
    }

    func rename(_ stamp: Stamp, to title: String) {
        guard let i = stamps.firstIndex(where: { $0.id == stamp.id }) else { return }
        stamps[i].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
        // A sticker's name is part of its artifact — refresh the drawer copy.
        if stamps[i].kind == .sticker, stamps[i].labelAnchor != nil,
           let display = image(for: stamps[i]) {
            writeDrawerCopy(for: stamps[i], display: display)
        }
    }

    func image(for stamp: Stamp) -> UIImage? {
        if let cached = cache.object(forKey: stamp.imageFile as NSString) { return cached }
        let url = imagesDir.appendingPathComponent(stamp.imageFile)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cacheImage(image, for: stamp.imageFile)
        return image
    }

    /// Stamps grouped by calendar day, newest day first.
    var dayGroups: [(day: Date, title: String, stamps: [Stamp])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: stamps) { calendar.startOfDay(for: $0.date) }
        let formatter = DateFormatter.app(template: "MMMd")
        return groups.keys.sorted(by: >).map { day in
            (day, formatter.string(from: day), groups[day]!.sorted { $0.date > $1.date })
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(stamps) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        stamps = (try? decoder.decode([Stamp].self, from: data)) ?? []
        prewarmCache()
        MemoryProbe.log("launch (\(stamps.count) stamps)")
    }

    /// One screenful of album cells, decoded ahead of the first scroll.
    ///
    /// This used to walk the *entire* collection calling
    /// `preparingForDisplay()` — the deliberately non-lazy path — which put
    /// every stamp's full 1600 px bitmap resident at launch: ~390 MB at 50
    /// stamps, ~780 MB at 100, against a jetsam budget near 900 MB on a 3 GB
    /// device. It bought instant album scroll by spending memory the app
    /// could not afford, and the resulting pressure is what made NSCache
    /// purge mid-edit. A capped thumbnail warm keeps the scroll and costs a
    /// flat ~10 MB no matter how large the collection grows.
    ///
    /// Serial by design: one task walking the list, not one task per stamp.
    private func prewarmCache() {
        let items = Array(stamps.prefix(Self.prewarmCount))
        let dir = imagesDir
        let pixels = Self.thumbnailPixels
        Task.detached(priority: .utility) { [weak self] in
            for stamp in items {
                let url = dir.appendingPathComponent(stamp.imageFile)
                guard let small = ImageOptimizer.downsampled(url: url, maxPixel: pixels)
                else { continue }
                await self?.seedThumbnail(small, for: stamp.imageFile)
            }
        }
    }

    private static let prewarmCount = 12

    private func seedThumbnail(_ image: UIImage, for file: String) {
        let key = thumbKey(file)
        guard cache.object(forKey: key as NSString) == nil else { return }
        cacheImage(image, for: key)
    }
}
