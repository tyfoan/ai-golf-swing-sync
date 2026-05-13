//
//  PaywallPlan.swift
//  golf-sync-swing
//
//  View-model value type for a single subscription/lifetime option in the
//  custom paywall. Decouples the SwiftUI section views from RevenueCat's
//  Package type so the views never import RevenueCat.
//

import Foundation
import RevenueCat

struct PaywallPlan: Identifiable, Equatable {

    enum Kind: Equatable {
        case lifetime
        case annual
        case weekly
    }

    let id: String                  // RC product identifier
    let kind: Kind
    let priceString: String         // e.g. "$49.99/yr"
    let trialString: String?        // e.g. "7-day free trial" — nil for lifetime
    let savingsBadge: String?       // e.g. "BEST VALUE · SAVE 81%" — annual only
    let equivalentString: String?   // e.g. "≈ $0.96/wk" — annual only
    let lineUnderPrice: String      // e.g. "Pay once, yours forever"
    let package: Package

    static func == (lhs: PaywallPlan, rhs: PaywallPlan) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Factory

extension PaywallPlan {

    static func lifetime(from package: Package) -> PaywallPlan {
        PaywallPlan(
            id: package.identifier,
            kind: .lifetime,
            priceString: package.storeProduct.localizedPriceString,
            trialString: nil,
            savingsBadge: String(localized: "ONE-TIME · FOREVER", comment: "Paywall badge above the lifetime plan card"),
            equivalentString: nil,
            lineUnderPrice: String(localized: "Pay once, yours forever", comment: "Paywall subline under the lifetime plan price"),
            package: package
        )
    }

    static func annual(from package: Package, weekly: Package?, trialEligible: Bool) -> PaywallPlan {
        PaywallPlan(
            id: package.identifier,
            kind: .annual,
            priceString: "\(package.storeProduct.localizedPriceString)/yr",
            trialString: trialEligible ? trial(for: package) : nil,
            savingsBadge: savingsBadge(annual: package, weekly: weekly),
            equivalentString: equivalentWeekly(for: package),
            lineUnderPrice: trialEligible
                ? String(localized: "Save 81% vs weekly", comment: "Paywall subline under the annual plan price when a trial is offered")
                : String(localized: "Billed yearly", comment: "Paywall subline under the annual plan price when no trial is offered"),
            package: package
        )
    }

    static func weekly(from package: Package, trialEligible: Bool) -> PaywallPlan {
        PaywallPlan(
            id: package.identifier,
            kind: .weekly,
            priceString: "\(package.storeProduct.localizedPriceString)/wk",
            trialString: trialEligible ? trial(for: package) : nil,
            savingsBadge: nil,
            equivalentString: nil,
            lineUnderPrice: trialEligible
                ? String(localized: "Most flexible", comment: "Paywall subline under the weekly plan price when a trial is offered")
                : String(localized: "Billed weekly", comment: "Paywall subline under the weekly plan price when no trial is offered"),
            package: package
        )
    }
}

// MARK: - Derived strings

private extension PaywallPlan {

    static func trial(for package: Package) -> String? {
        guard
            let intro = package.storeProduct.introductoryDiscount,
            intro.paymentMode == .freeTrial
        else { return nil }
        let count = intro.subscriptionPeriod.value
        switch intro.subscriptionPeriod.unit {
        case .day:
            return String(localized: "\(count)-day free trial", comment: "Paywall trial duration label (compound modifier, e.g. \"3-day free trial\")")
        case .week:
            return String(localized: "\(count)-week free trial", comment: "Paywall trial duration label (compound modifier, e.g. \"1-week free trial\")")
        case .month:
            return String(localized: "\(count)-month free trial", comment: "Paywall trial duration label (compound modifier)")
        case .year:
            return String(localized: "\(count)-year free trial", comment: "Paywall trial duration label (compound modifier)")
        }
    }

    static func savingsBadge(annual: Package, weekly: Package?) -> String? {
        guard
            let weekly,
            let percent = savingsPercent(annual: annual, weekly: weekly)
        else {
            return String(localized: "BEST VALUE", comment: "Paywall badge on the annual plan when actual savings can't be computed")
        }
        return String(localized: "BEST VALUE · SAVE \(percent)%", comment: "Paywall badge on the annual plan — placeholder is the saving percent vs weekly")
    }

    static func savingsPercent(annual: Package, weekly: Package) -> Int? {
        let annualPrice = annual.storeProduct.price
        let weeklyPrice = weekly.storeProduct.price
        guard weeklyPrice > 0 else { return nil }
        let weeklyYearTotal = weeklyPrice * 52
        guard weeklyYearTotal > annualPrice else { return nil }
        let saved = NSDecimalNumber(decimal: 1 - (annualPrice / weeklyYearTotal))
        return Int((saved.doubleValue * 100).rounded())
    }

    static func equivalentWeekly(for annual: Package) -> String? {
        let perWeek = annual.storeProduct.price / 52
        guard let formatter = annual.storeProduct.priceFormatter else { return nil }
        guard let formatted = formatter.string(from: NSDecimalNumber(decimal: perWeek)) else { return nil }
        return "≈ \(formatted)/wk"
    }
}
