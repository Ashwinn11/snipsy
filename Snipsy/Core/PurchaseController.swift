import Foundation
import RevenueCat
import Observation

/// Premium purchase controller handling auto-renewable subscriptions (weekly, yearly)
/// and lifetime unlock via RevenueCat.
@MainActor
@Observable
final class PurchaseController {

    private nonisolated static let apiKey = "appl_OxILRWppWRYZibPzGmTcxsECqoD"

    private(set) var unlocked = false
    private(set) var lifetime: Package?
    private(set) var weekly: Package?
    private(set) var yearly: Package?
    private(set) var purchasing = false
    
    /// Maps product identifier to its introductory offer eligibility status.
    private(set) var introEligibility: [String: IntroEligibilityStatus] = [:]

    /// Localized lifetime price, kept for compatibility.
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
        guard let offerings = try? await Purchases.shared.offerings(),
              let current = offerings.current
        else { return }
        
        lifetime = current.lifetime ?? current.availablePackages.first(where: { $0.packageType == .lifetime })
        weekly = current.weekly ?? current.availablePackages.first(where: { $0.packageType == .weekly })
        yearly = current.annual ?? current.availablePackages.first(where: { $0.packageType == .annual })
        
        await checkIntroEligibility()
    }

    /// Check introductory / free trial eligibility for the loaded packages.
    func checkIntroEligibility() async {
        var productIDs: [String] = []
        if let weeklyID = weekly?.storeProduct.productIdentifier {
            productIDs.append(weeklyID)
        }
        if let yearlyID = yearly?.storeProduct.productIdentifier {
            productIDs.append(yearlyID)
        }
        
        guard !productIDs.isEmpty else { return }
        
        let results = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: productIDs)
        var newEligibility: [String: IntroEligibilityStatus] = [:]
        for (productID, eligibility) in results {
            newEligibility[productID] = eligibility.status
        }
        self.introEligibility = newEligibility
    }

    /// Purchase a specific package.
    @discardableResult
    func purchase(package: Package) async -> Bool {
        guard !purchasing else { return unlocked }
        purchasing = true
        defer { purchasing = false }
        guard let result = try? await Purchases.shared.purchase(package: package),
              !result.userCancelled
        else { return false }
        unlocked = !result.customerInfo.entitlements.active.isEmpty
        return unlocked
    }

    /// Compatibility overload for purchase.
    @discardableResult
    func purchase() async -> Bool {
        guard let package = lifetime else { return unlocked }
        return await purchase(package: package)
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
