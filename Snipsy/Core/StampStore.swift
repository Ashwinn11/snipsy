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

    private(set) var stamps: [Stamp] = []   // newest first

    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()

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
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: stickersDir, withIntermediateDirectories: true)
        load()
        if !Self.isExtension { backfillDrawer() }
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
        } else {
            let renderer = ImageRenderer(content:
                StampView(stamp: stamp, image: display)
                    .frame(width: 400, height: 525))
            renderer.scale = 1.5
            renderer.isOpaque = false
            data = renderer.uiImage.flatMap { ImageOptimizer.stickerPNG($0) }
        }
        guard let data else { return }
        Task.detached(priority: .utility) {
            try? data.write(to: destination)
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
        case .stamp:
            display = pending.capture.cropImage
            style = .classic
        }
        // Optimize + write off-main: done here it stalls the fly-out fade.
        // The in-memory cache serves reads until the files land.
        let destination = imagesDir.appendingPathComponent(file)
        Task.detached(priority: .utility) {
            if let data = ImageOptimizer.optimized(display) {
                try? data.write(to: destination)
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
        cache.setObject(display, forKey: file as NSString)
        stamps.insert(stamp, at: 0)
        save()
        writeDrawerCopy(for: stamp, display: display)
        return stamp
    }

    func remove(_ stamp: Stamp) {
        stamps.removeAll { $0.id == stamp.id }
        try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(stamp.imageFile))
        try? FileManager.default.removeItem(
            at: stickersDir.appendingPathComponent("\(stamp.id.uuidString).png"))
        cache.removeObject(forKey: stamp.imageFile as NSString)
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
            try? FileManager.default.removeItem(
                at: imagesDir.appendingPathComponent(stamp.imageFile))
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
        cache.setObject(image, forKey: stamp.imageFile as NSString)
        return image
    }

    /// Stamps grouped by calendar day, newest day first.
    var dayGroups: [(day: Date, title: String, stamps: [Stamp])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: stamps) { calendar.startOfDay(for: $0.date) }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
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
    }
}
