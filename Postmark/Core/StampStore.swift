import UIKit
import Observation

/// Owns the collection: stamps.json + one PNG per stamp under Documents.
@MainActor
@Observable
final class StampStore {

    private(set) var stamps: [Stamp] = []   // newest first

    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()

    private var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Postmark", isDirectory: true)
    }
    private var imagesDir: URL { root.appendingPathComponent("images", isDirectory: true) }
    private var indexURL: URL { root.appendingPathComponent("stamps.json") }

    init() {
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    var nextNumber: Int { (stamps.map(\.number).max() ?? 0) + 1 }

    @discardableResult
    func add(_ pending: PendingStamp, title: String, variant: StampVariant) -> Stamp {
        let id = UUID()
        let file = "\(id.uuidString).png"
        let display = pending.displayImage
        // PNG encode + write off-main: done here it stalls the fly-out fade.
        // The in-memory cache serves reads until the file lands.
        let destination = imagesDir.appendingPathComponent(file)
        Task.detached(priority: .utility) {
            if let data = display.pngData() {
                try? data.write(to: destination)
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
        cache.removeObject(forKey: stamp.imageFile as NSString)
        save()
    }

    /// Debug/audit helper: clear everything.
    func wipe() {
        for stamp in stamps {
            try? FileManager.default.removeItem(
                at: imagesDir.appendingPathComponent(stamp.imageFile))
        }
        stamps.removeAll()
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
