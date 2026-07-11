import Foundation

/// In-app legal documents. Snipsy is fully offline, so both documents are
/// short, honest, and readable — no boilerplate about servers we don't have.
enum LegalDoc: String, Identifiable, CaseIterable {
    case terms = "Terms of Service"
    case privacy = "Privacy Policy"

    var id: String { rawValue }

    var body: String {
        switch self {
        case .terms: Self.termsText
        case .privacy: Self.privacyText
        }
    }

    static let effectiveDate = "July 10, 2026"
    static let contactEmail = "ashwinnanbazhagan@gmail.com"

    private static let termsText = """
    Effective \(effectiveDate)

    1. Agreement
    By downloading or using Snipsy ("the app"), you agree to these Terms of Service. If you do not agree, please do not use the app.

    2. What Snipsy Is
    Snipsy turns photos you take into collectible stamp artworks that live in an album on your device. The app works entirely offline; it has no accounts, no server, and no social features.

    3. License
    You are granted a personal, non-transferable, non-exclusive license to use the app on Apple devices you own or control, subject to Apple's standard App Store terms (the Licensed Application End User License Agreement).

    4. Your Content
    Photos you capture and the stamps made from them are yours. They are stored only on your device. You are solely responsible for the content you capture and for anything you choose to share out of the app using the system share sheet. Do not use the app to capture or share content that is unlawful or that infringes the rights of others.

    5. Our Content
    The app's design, artwork, typography treatments, animations, and code are the property of the developer and are protected by applicable intellectual-property laws. The stamps you create from your own photos are yours.

    6. Acceptable Use
    You agree not to reverse engineer, resell, or redistribute the app, and not to use it in violation of any applicable law.

    7. No Warranty
    The app is provided "as is" and "as available," without warranties of any kind, express or implied, including fitness for a particular purpose and non-infringement. Subject-detection quality depends on your device and the photo; results may vary.

    8. Limitation of Liability
    To the maximum extent permitted by law, the developer shall not be liable for any indirect, incidental, special, or consequential damages, or for loss of data — including deleted stamps — arising from your use of the app. Deleting the app or using Delete All Data permanently removes your collection; the developer cannot recover it.

    9. Changes
    These terms may be updated from time to time. Material changes will be reflected in the app with an updated effective date. Continued use after a change means you accept the updated terms.

    10. Contact
    Questions about these terms: \(contactEmail)
    """

    private static let privacyText = """
    Effective \(effectiveDate)

    The short version
    Everything stays on your iPhone. Snipsy has no accounts, no analytics, no ads, no tracking, and no server. We never see your photos — or anything else.

    1. Information We Collect
    None. The app does not collect, transmit, sell, or share any personal information. It makes no network requests.

    2. Camera
    Snipsy asks for camera access so you can take photos inside the app. Frames from the camera are processed and displayed on your device only.

    3. Photos and Processing
    When you capture a photo, Apple's on-device Vision framework finds the subject and the app renders your stamp. The photo, the cut-out subject, and the finished stamp are stored only in the app's private storage on your device. Nothing is uploaded anywhere.

    4. Sharing and Stickers
    Sharing a stamp or sticker uses the standard iOS share sheet; what happens after you share is controlled by you and the app you share to. Stickers you keep are also made available to Snipsy's Messages sticker extension, stored in the app's private shared container on this device only.

    5. Deleting Your Data
    Delete individual stamps from their detail view, or use Settings → Delete All Data to permanently erase every stamp and photo the app has stored. Deleting the app from your device removes everything as well. Deletion is immediate and irreversible.

    6. Children
    Snipsy does not collect data from anyone, including children.

    7. Changes
    If this policy ever changes — for example, if a future version adds an online feature — the updated policy will appear here with a new effective date before any such feature is enabled.

    8. Contact
    Privacy questions: \(contactEmail)
    """
}
