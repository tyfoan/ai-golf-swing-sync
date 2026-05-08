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
            savingsBadge: "ONE-TIME · FOREVER",
            equivalentString: nil,
            lineUnderPrice: "Pay once, yours forever",
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
            lineUnderPrice: trialEligible ? "Save 81% vs weekly" : "Billed yearly",
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
            lineUnderPrice: trialEligible ? "Most flexible" : "Billed weekly",
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
        let unit = unitLabel(for: intro.subscriptionPeriod.unit, count: count)
        return "\(count)-\(unit) free trial"
    }

    static func unitLabel(for unit: SubscriptionPeriod.Unit, count: Int) -> String {
        let plural = count != 1
        switch unit {
        case .day:   return plural ? "day"   : "day"   // "3-day" reads well singular
        case .week:  return plural ? "week"  : "week"
        case .month: return plural ? "month" : "month"
        case .year:  return plural ? "year"  : "year"
        }
    }

    static func savingsBadge(annual: Package, weekly: Package?) -> String? {
        guard
            let weekly,
            let percent = savingsPercent(annual: annual, weekly: weekly)
        else { return "BEST VALUE" }
        return "BEST VALUE · SAVE \(percent)%"
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = annual.storeProduct.priceFormatter?.locale ?? .current
        guard let formatted = formatter.string(from: NSDecimalNumber(decimal: perWeek)) else { return nil }
        return "≈ \(formatted)/wk"
    }
}
