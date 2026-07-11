import Foundation
import RevenueCat
import Observation

/// Lifetime unlock via RevenueCat: one non-consumable, no subscription.
/// Any active entitlement unlocks the app, so the entitlement identifier
/// never needs to be hardcoded here.
@MainActor
@Observable
final class PurchaseController {

    private static let apiKey = "appl_OxILRWppWRYZibPzGmTcxsECqoD"

    private(set) var unlocked = false
    private(set) var lifetime: Package?
    private(set) var purchasing = false

    /// Localized one-time price ("₹499", "$4.99"), once the offering loads.
    var priceText: String? { lifetime?.storeProduct.localizedPriceString }

    /// Call once, before any instance exists (app entry point).
    nonisolated static func configure() {
        Purchases.configure(withAPIKey: apiKey)
    }

    /// Pick up an existing unlock (fresh install with prior purchase,
    /// family sharing, re-launch).
    func refresh() async {
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        unlocked = !info.entitlements.active.isEmpty
    }

    func loadOffering() async {
        guard lifetime == nil,
              let offerings = try? await Purchases.shared.offerings(),
              let current = offerings.current
        else { return }
        lifetime = current.lifetime ?? current.availablePackages.first
    }

    /// True when the purchase (or a prior one) unlocks the app.
    @discardableResult
    func purchase() async -> Bool {
        guard let package = lifetime, !purchasing else { return unlocked }
        purchasing = true
        defer { purchasing = false }
        guard let result = try? await Purchases.shared.purchase(package: package),
              !result.userCancelled
        else { return false }
        unlocked = !result.customerInfo.entitlements.active.isEmpty
        return unlocked
    }

    @discardableResult
    func restore() async -> Bool {
        guard !purchasing else { return unlocked }
        purchasing = true
        defer { purchasing = false }
        guard let info = try? await Purchases.shared.restorePurchases() else {
            return false
        }
        unlocked = !info.entitlements.active.isEmpty
        return unlocked
    }
}
