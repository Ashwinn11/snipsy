import UIKit
import Messages

/// The Messages drawer: every die-cut sticker the user has kept in Postmark,
/// newest first, straight from the shared container.
final class MessagesViewController: MSMessagesAppViewController {

    private let browser = StickerBrowserViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.957, green: 0.937, blue: 0.902, alpha: 1)

        addChild(browser)
        browser.view.frame = view.bounds
        browser.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(browser.view)
        browser.didMove(toParent: self)
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        browser.reload()
    }
}

final class StickerBrowserViewController: MSStickerBrowserViewController {

    private var stickers: [MSSticker] = []
    private let emptyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        stickerBrowserView.backgroundColor = UIColor(
            red: 0.957, green: 0.937, blue: 0.902, alpha: 1)

        emptyLabel.text = "Keep a stamp in Postmark\nand its sticker appears here."
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = UIFont(descriptor: UIFont.systemFont(
            ofSize: 15).fontDescriptor.withDesign(.serif)
            ?? UIFont.systemFont(ofSize: 15).fontDescriptor, size: 15)
        emptyLabel.textColor = UIColor(red: 0.51, green: 0.49, blue: 0.43, alpha: 1)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])
        reload()
    }

    func reload() {
        stickers = Self.loadStickers()
        emptyLabel.isHidden = !stickers.isEmpty
        stickerBrowserView.reloadData()
    }

    /// Newest first, from the app group's stickers directory.
    private static func loadStickers() -> [MSSticker] {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.ashwinn.postmark")
        else { return [] }
        let dir = container
            .appendingPathComponent("Postmark", isDirectory: true)
            .appendingPathComponent("stickers", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let sorted = files
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da > db
            }
        return sorted.compactMap {
            try? MSSticker(contentsOfFileURL: $0, localizedDescription: "Postmark sticker")
        }
    }

    // MARK: MSStickerBrowserViewDataSource

    override func numberOfStickers(in stickerBrowserView: MSStickerBrowserView) -> Int {
        stickers.count
    }

    override func stickerBrowserView(
        _ stickerBrowserView: MSStickerBrowserView, stickerAt index: Int
    ) -> MSSticker {
        stickers[index]
    }
}
