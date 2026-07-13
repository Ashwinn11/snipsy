import StoreKit
import UIKit

/// Spends Apple's review-prompt budget deliberately. The system shows at
/// most ~3 prompts per 365 days and never reports whether one appeared,
/// so every request we make is ledgered locally: milestones are one-shot,
/// kept days apart, and stop asking once the year's budget is spent.
/// Settings' "Rate Snipsy" reads the same ledger — budget left → system
/// prompt in-app; spent → the App Store review page, which always works.
@MainActor
final class ReviewPrompter {

    /// App Store ID for the write-review deep link. Empty until the app
    /// is live — the manual path falls back to the system prompt then.
    static let appStoreID = ""

    /// Moments worth a prompt. Counts are thresholds, not exact hits:
    /// a milestone blocked by the day gap simply fires on the first
    /// qualifying keep after the gap elapses — that is what spreads the
    /// three prompts across days instead of one sitting.
    enum Milestone: String {
        /// The first snap's output screen — the app's wow moment.
        case firstReveal
        case tenKeeps
        case thirtyKeeps
    }

    private let defaults = UserDefaults.standard
    private let requestsKey = "snipsy.review.requests"

    /// Minimum days between any two prompts we initiate.
    private let minGapDays: Double = 5
    /// Apple grants ~3 per rolling year; requesting past that is a no-op
    /// that would silently burn a milestone, so we stop ourselves first.
    private let yearlyBudget = 3

    private var requestDates: [Date] {
        get {
            let raw = defaults.array(forKey: requestsKey) as? [Double] ?? []
            return raw.map(Date.init(timeIntervalSinceReferenceDate:))
        }
        set {
            defaults.set(newValue.map(\.timeIntervalSinceReferenceDate),
                         forKey: requestsKey)
        }
    }

    private var usedThisYear: Int {
        let cutoff = Date().addingTimeInterval(-365 * 86_400)
        return requestDates.filter { $0 > cutoff }.count
    }

    private var gapSatisfied: Bool {
        guard let last = requestDates.max() else { return true }
        return Date().timeIntervalSince(last) > minGapDays * 86_400
    }

    /// A stamp landed in the collection — check the count milestones.
    func stampKept(count: Int) {
        if count >= 30 {
            fire(.thirtyKeeps)
        } else if count >= 10 {
            fire(.tenKeeps)
        }
    }

    /// Request a milestone prompt if its slot is open and the budget and
    /// day gap allow. Consumed only when actually requested, so a blocked
    /// milestone retries at the next opportunity instead of vanishing.
    func fire(_ milestone: Milestone) {
        let key = "snipsy.review.milestone.\(milestone.rawValue)"
        guard !defaults.bool(forKey: key),
              usedThisYear < yearlyBudget,
              gapSatisfied
        else { return }
        defaults.set(true, forKey: key)
        requestSystemPrompt()
    }

    /// Settings → Rate Snipsy. With budget left, the in-app system prompt
    /// (the user asked — spend the slot, though the system may still
    /// decline to show it); with the year spent, the store's review page.
    func rateManually() {
        if usedThisYear < yearlyBudget || Self.appStoreID.isEmpty {
            requestSystemPrompt()
        } else if let url = URL(
            string: "https://apps.apple.com/app/id\(Self.appStoreID)?action=write-review"
        ) {
            UIApplication.shared.open(url)
        }
    }

    private func requestSystemPrompt() {
        requestDates.append(Date())
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        else { return }
        AppStore.requestReview(in: scene)
    }
}
