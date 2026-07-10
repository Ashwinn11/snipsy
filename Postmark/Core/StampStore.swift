import UIKit
import Observation

/// Owns the collection: stamps.json + one PNG per stamp under Documents.
@MainActor
@Observable
final class StampStore {

    private(set) var stamps: [Stamp] = []   // newest first

    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()

    static let appGroup = "group.com.ashwinn.postmark"

    /// Shared with the Messages sticker extension. Falls back to Documents
    /// if the group container is unavailable.
    private let root: URL = {
        let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: StampStore.appGroup)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Postmark", isDirectory: true)
    }()
    private var imagesDir: URL { root.appendingPathComponent("images", isDirectory: true) }
    /// PNG die-cuts for the Messages drawer (MSSticker cannot read HEIC).
    private var stickersDir: URL { root.appendingPathComponent("stickers", isDirectory: true) }
    private var indexURL: URL { root.appendingPathComponent("stamps.json") }

    init() {
        migrateFromDocumentsIfNeeded()
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: stickersDir, withIntermediateDirectories: true)
        load()
    }

    /// One-time move of pre-app-group collections (Documents/Postmark).
    private func migrateFromDocumentsIfNeeded() {
        let old = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Postmark", isDirectory: true)
        guard old != root,
              FileManager.default.fileExists(atPath: old.path),
              !FileManager.default.fileExists(atPath: indexURL.path)
        else { return }
        try? FileManager.default.createDirectory(
            at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.moveItem(at: old, to: root)
    }

    var nextNumber: Int { (stamps.map(\.number).max() ?? 0) + 1 }

    @discardableResult
    func add(_ pending: PendingStamp, title: String, variant: StampVariant) -> Stamp {
        let id = UUID()
        let file = "\(id.uuidString).heic"
        let display = pending.displayImage
        // Optimize + write off-main: done here it stalls the fly-out fade.
        // The in-memory cache serves reads until the files land.
        let destination = imagesDir.appendingPathComponent(file)
        let stickerDestination = pending.style == .cutout
            ? stickersDir.appendingPathComponent("\(id.uuidString).png") : nil
        Task.detached(priority: .utility) {
            if let data = ImageOptimizer.optimized(display) {
                try? data.write(to: destination)
            }
            // A small PNG copy for the Messages drawer (Apple's sticker
            // limit is 618 px / 500 KB; MSSticker can't read HEIC).
            if let stickerDestination,
               let png = ImageOptimizer.downscaled(display, maxDimension: 618).pngData() {
                try? png.write(to: stickerDestination)
            }
        }
        let stamp = Stamp(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: Date(),
            number: nextNumber,
            style: pending.style,
            tint: pending.tint,
            imageFile: file,
            variant: variant
        )
        cache.setObject(display, forKey: file as NSString)
        stamps.insert(stamp, at: 0)
        save()
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
