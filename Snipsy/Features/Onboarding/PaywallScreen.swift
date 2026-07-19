import SwiftUI
import RevenueCat

/// The gate between onboarding and the camera: three purchase options (weekly, yearly, lifetime).
/// Designs the price cards similarly to YumeShip, complete with free trial check and badges.
struct PaywallScreen: View {
    let purchases: PurchaseController
    let demo: OnboardingDemo
    let screenSize: CGSize
    let safeArea: EdgeInsets
    var onUnlocked: () -> Void
    var onClose: () -> Void

    @State private var closeVisible = false
    @State private var stage = 0
    @State private var doc: LegalDoc? = nil
    @State private var selectedPlan: PaywallPlan = .yearly

    enum PaywallPlan {
        case weekly
        case yearly
        case lifetime
    }

    var body: some View {
        ZStack {
            PaperBackdrop()
                .ignoresSafeArea()

            if purchases.weekly != nil || purchases.yearly != nil || purchases.lifetime != nil {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: 12) {
                        stickerFan
                            .padding(.bottom, 10)
                        RansomText(text: "KEEP EVERY MOMENT", fontSize: 16, ink: Theme.ink)
                    }
                    .entrance(shown: stage >= 1)

                    VStack(alignment: .leading, spacing: 14) {
                        outcome("square.stack", "Layer photos, stickers, & text on a canvas")
                        outcome("scissors", "Convert photos into die-cut stickers")
                        outcome("seal.fill", "Turn moments into dated postage stamps")
                    }
                    .padding(.horizontal, 58)
                    .entrance(shown: stage >= 2)

                    Spacer(minLength: 0)

                    plansView(weekly: purchases.weekly, yearly: purchases.yearly, lifetime: purchases.lifetime)
                        .padding(.top, 20)
                        .entrance(shown: stage >= 2)

                    Spacer(minLength: 0)

                    VStack(spacing: 14) {
                        Button {
                            Task {
                                let packageToPurchase: Package? = switch selectedPlan {
                                case .weekly: purchases.weekly
                                case .yearly: purchases.yearly
                                case .lifetime: purchases.lifetime
                                }
                                guard let packageToPurchase else { return }
                                
                                if await purchases.purchase(package: packageToPurchase) {
                                    onUnlocked()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if purchases.purchasing {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "seal.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                Text(ctaText)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .frame(height: 54)
                            .frame(maxWidth: .infinity)
                            .background(Theme.postalRed, in: Capsule())
                            .padding(.horizontal, 32)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .disabled(purchases.purchasing)

                        Text(subCTAText)
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundStyle(Theme.inkSoft)

                        HStack(spacing: 18) {
                            Button {
                                Task {
                                    if await purchases.restore() { onUnlocked() }
                                }
                            } label: {
                                Text("Restore Purchase").underline()
                            }
                            Button { doc = .terms } label: {
                                Text("Terms").underline()
                            }
                            Button { doc = .privacy } label: {
                                Text("Privacy").underline()
                            }
                        }
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.inkSoft.opacity(0.8))
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 30)
                    .entrance(shown: stage >= 3)
                }
            } else {
                VStack {
                    ProgressView()
                        .tint(Theme.ink)
                }
            }

            if closeVisible {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 38, height: 38)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .position(x: screenSize.width - 44,
                          y: max(safeArea.top, 20) + 18)
                .transition(.opacity)
            }
        }
        .sheet(item: $doc) { LegalDocView(doc: $0) }
        .task {
            await purchases.loadOffering()
            if purchases.yearly != nil {
                selectedPlan = .yearly
            } else if purchases.weekly != nil {
                selectedPlan = .weekly
            } else if purchases.lifetime != nil {
                selectedPlan = .lifetime
            }
        }
        .onAppear {
            Task { @MainActor in
                for s in 1...3 {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                        stage = s
                    }
                    try? await Task.sleep(for: .seconds(0.12))
                }
                try? await Task.sleep(for: .seconds(2.6))
                withAnimation(.easeIn(duration: 0.5)) { closeVisible = true }
            }
        }
    }

    /// The collection as one tossed pile: three fanned behind the hero.
    private var stickerFan: some View {
        ZStack {
            if demo.drawer.count >= 3 {
                fanned(demo.drawer[1], width: 78, degrees: -19, dx: -62, dy: 10)
                fanned(demo.drawer[2], width: 72, degrees: 16, dx: 62, dy: 12)
            }
            if let hero = demo.hero {
                fanned(hero.stickerRender, width: 96, degrees: -7, dx: 0, dy: 6)
            }
        }
        .frame(height: 128)
    }

    private func fanned(_ render: UIImage, width: CGFloat, degrees: Double,
                        dx: CGFloat, dy: CGFloat) -> some View {
        Image(uiImage: render)
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .rotationEffect(.degrees(degrees))
            .shadow(color: Theme.shadow.opacity(0.20), radius: 8, y: 5)
            .offset(x: dx, y: dy)
    }

    private func outcome(_ symbol: String, _ line: String) -> some View {
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.postalRed)
                .frame(width: 26)
            Text(line)
                .font(.system(size: 14.5, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Subviews & Subview Logic

    private func plansView(weekly: Package?, yearly: Package?, lifetime: Package?) -> some View {
        VStack(spacing: 12) {
            // Lifetime Card
            if let lifetime {
                planCardView(
                    plan: .lifetime,
                    title: "Lifetime",
                    subtitle: "Pay once. Yours forever.",
                    package: lifetime,
                    period: ""
                )
            }
            
            // Yearly Card
            if let yearly {
                planCardView(
                    plan: .yearly,
                    title: "Yearly",
                    subtitle: yearlyWeeklyEquivalentSubtitle(yearly),
                    package: yearly,
                    period: "year"
                )
            }
            
            // Weekly Card
            if let weekly {
                planCardView(
                    plan: .weekly,
                    title: "Weekly",
                    subtitle: "Billed weekly. Cancel anytime.",
                    package: weekly,
                    period: "week"
                )
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func planCardView(
        plan: PaywallPlan,
        title: String,
        subtitle: String,
        package: Package,
        period: String
    ) -> some View {
        let isSelected = selectedPlan == plan
        let priceString = package.storeProduct.localizedPriceString
        
        Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 12) {
                // Left Column
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? Theme.postalRed : Theme.ink)
                        
                        if plan == .lifetime {
                            Text("ONE-TIME")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.postalRed.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(Theme.postalRed)
                        }
                        
                        if plan == .yearly {
                            Text("BEST VALUE")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.postalRed.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(Theme.postalRed)
                                
                            if isYearlyEligibleForTrial, let trialLabel = trialPeriodLabel(for: package) {
                                Text("\(trialLabel.uppercased()) TRIAL")
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(Color.blue)
                            }
                        }
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                }
                
                Spacer()
                
                // Right Column
                VStack(alignment: .trailing, spacing: 2) {
                    if plan == .yearly, purchases.weekly != nil, let strikethrough = yearlyStrikethroughPrice {
                        Text(strikethrough)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.inkSoft)
                            .strikethrough()
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(priceString)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        
                        if !period.isEmpty {
                            Text("/ \(period)")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Theme.postalRed.opacity(0.04) : Color.white.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Theme.postalRed : Theme.inkSoft.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if plan == .yearly, purchases.weekly != nil, let savePercent = yearlySavePercent, savePercent > 0 {
                    Text("SAVE \(savePercent)%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.postalRed)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .offset(x: -12, y: -10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func periodLabel(for package: Package) -> String {
        guard let period = package.storeProduct.subscriptionPeriod else { return "" }
        switch period.unit {
        case .day:
            return period.value == 1 ? "day" : "\(period.value) days"
        case .week:
            return period.value == 1 ? "week" : "\(period.value) weeks"
        case .month:
            return period.value == 1 ? "month" : "\(period.value) months"
        case .year:
            return period.value == 1 ? "year" : "\(period.value) years"
        @unknown default:
            return ""
        }
    }

    private func trialPeriodLabel(for package: Package) -> String? {
        guard let intro = package.storeProduct.introductoryDiscount,
              intro.price == 0
        else { return nil }
        
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day:
            return period.value == 1 ? "1 day" : "\(period.value) days"
        case .week:
            return period.value == 1 ? "1 week" : "\(period.value) weeks"
        case .month:
            return period.value == 1 ? "1 month" : "\(period.value) months"
        case .year:
            return period.value == 1 ? "1 year" : "\(period.value) years"
        @unknown default:
            return nil
        }
    }



    // MARK: - Computed Properties for Plan Pricing & Details

    private var weeklyPriceValue: Double {
        if let weekly = purchases.weekly {
            return Double(truncating: weekly.storeProduct.price as NSDecimalNumber)
        }
        return 2.99
    }
    
    private var yearlyPriceValue: Double {
        if let yearly = purchases.yearly {
            return Double(truncating: yearly.storeProduct.price as NSDecimalNumber)
        }
        return 19.99
    }

    private func yearlyWeeklyEquivalentSubtitle(_ yearly: Package) -> String {
        let yearlyVal = Double(truncating: yearly.storeProduct.price as NSDecimalNumber)
        let weeklyVal = yearlyVal / 52.0
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = yearly.storeProduct.priceFormatter?.locale
        formatter.currencySymbol = yearly.storeProduct.priceFormatter?.currencySymbol ?? "$"
        return (formatter.string(from: NSNumber(value: weeklyVal)) ?? "") + "/week"
    }

    private var yearlyStrikethroughPrice: String? {
        let weeklyVal = weeklyPriceValue
        let strikethroughVal = weeklyVal * 54
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        if let weekly = purchases.weekly {
            formatter.locale = weekly.storeProduct.priceFormatter?.locale
            formatter.currencySymbol = weekly.storeProduct.priceFormatter?.currencySymbol ?? "$"
        } else {
            formatter.locale = Locale(identifier: "en_US")
            formatter.currencySymbol = "$"
        }
        return formatter.string(from: NSNumber(value: strikethroughVal))
    }

    private var yearlySavePercent: Int? {
        let weeklyVal = weeklyPriceValue
        let yearlyVal = yearlyPriceValue
        let strikethroughVal = weeklyVal * 54
        guard strikethroughVal > 0 else { return nil }
        let pct = ((strikethroughVal - yearlyVal) / strikethroughVal) * 100
        return max(0, Int(round(pct)))
    }

    private var isYearlyEligibleForTrial: Bool {
        guard let yearly = purchases.yearly else {
            return false
        }
        let productID = yearly.storeProduct.productIdentifier
        return purchases.introEligibility[productID] == .eligible
    }

    private var isWeeklyEligibleForTrial: Bool {
        guard let weekly = purchases.weekly else {
            return false
        }
        let productID = weekly.storeProduct.productIdentifier
        return purchases.introEligibility[productID] == .eligible
    }

    private var ctaText: String {
        switch selectedPlan {
        case .weekly:
            if let weekly = purchases.weekly {
                if isWeeklyEligibleForTrial, let trialLabel = trialPeriodLabel(for: weekly) {
                    return "Try \(trialLabel) free, then \(weekly.storeProduct.localizedPriceString)/week"
                } else {
                    return "Continue for \(weekly.storeProduct.localizedPriceString)/week"
                }
            }
        case .yearly:
            if let yearly = purchases.yearly {
                if isYearlyEligibleForTrial, let trialLabel = trialPeriodLabel(for: yearly) {
                    return "Try \(trialLabel) free, then \(yearly.storeProduct.localizedPriceString)/year"
                } else {
                    return "Continue for \(yearly.storeProduct.localizedPriceString)/year"
                }
            }
        case .lifetime:
            if let lifetime = purchases.lifetime {
                return "Unlock Lifetime for \(lifetime.storeProduct.localizedPriceString)"
            }
        }
        return ""
    }

    private var subCTAText: String {
        switch selectedPlan {
        case .lifetime:
            return "One-time purchase. No subscription"
        case .weekly:
            if isWeeklyEligibleForTrial {
                return "No payment due now. Cancel Anytime"
            } else {
                return "Cancel anytime. Secure checkout"
            }
        case .yearly:
            if isYearlyEligibleForTrial {
                return "No payment due now. Cancel Anytime"
            } else {
                return "Cancel anytime. Secure checkout"
            }
        }
    }
}

private extension View {
    func entrance(shown: Bool) -> some View {
        opacity(shown ? 1 : 0).offset(y: shown ? 0 : 16)
    }
}
