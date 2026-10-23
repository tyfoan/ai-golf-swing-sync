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

    /// What the plan's card shows.
    struct Card {
        let priceString: String         // e.g. "$29.99/yr"
        let trialString: String?        // e.g. "1-week free trial" — nil for lifetime
        let savingsBadge: String?       // e.g. "BEST VALUE · SAVE 88%" — computed from live prices
        let equivalentString: String?   // e.g. "≈ $0.58/wk" — annual only
        let lineUnderPrice: String      // e.g. "Pay once, yours forever"
    }

    let kind: Kind
    let card: Card
    let disclosure: String              // what the buy button commits to, shown under it
    let package: Package

    /// RC product identifier.
    var id: String { package.identifier }

    static func == (lhs: PaywallPlan, rhs: PaywallPlan) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Factory

extension PaywallPlan {

    static func lifetime(from package: Package) -> PaywallPlan {
        let price = package.storeProduct.localizedPriceString
        let card = Card(
            priceString: price,
            trialString: nil,
            savingsBadge: String(localized: "ONE-TIME · FOREVER", comment: "Paywall badge above the lifetime plan card"),
            equivalentString: nil,
            lineUnderPrice: String(localized: "Pay once, yours forever", comment: "Paywall subline under the lifetime plan price")
        )
        let disclosure = String(localized: "One-time payment of \(price). No subscription.", comment: "Line under the paywall buy button for the lifetime plan — placeholder is the price, e.g. \"$79.99\"")
        return PaywallPlan(kind: .lifetime, card: card, disclosure: disclosure, package: package)
    }

    static func annual(from package: Package, weekly: Package?, trialEligible: Bool) -> PaywallPlan {
        let price = String(localized: "\(package.storeProduct.localizedPriceString)/yr", comment: "Annual plan price with its billing period, e.g. \"$29.99/yr\"")
        let trial = trialEligible ? trial(for: package) : nil
        let card = Card(
            priceString: price,
            trialString: trial,
            savingsBadge: savingsBadge(annual: package, weekly: weekly),
            equivalentString: equivalentWeekly(for: package),
            lineUnderPrice: annualLine(for: package, trialEligible: trialEligible)
        )
        return PaywallPlan(kind: .annual, card: card, disclosure: renewalDisclosure(price: price, trial: trial), package: package)
    }

    static func weekly(from package: Package, trialEligible: Bool) -> PaywallPlan {
        let price = String(localized: "\(package.storeProduct.localizedPriceString)/wk", comment: "Weekly plan price with its billing period, e.g. \"$4.99/wk\"")
        let trial = trialEligible ? trial(for: package) : nil
        let card = Card(
            priceString: price,
            trialString: trial,
            savingsBadge: nil,
            equivalentString: nil,
            lineUnderPrice: weeklyLine(trialEligible: trialEligible)
        )
        return PaywallPlan(kind: .weekly, card: card, disclosure: renewalDisclosure(price: price, trial: trial), package: package)
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
        guard let perWeek = weeklyShare(of: annual) else { return nil }
        return String(localized: "≈ \(perWeek)/wk", comment: "Annual price divided into weeks, shown under the annual plan price, e.g. \"≈ $0.58/wk\"")
    }

    /// With a trial the gold trial label takes the equivalent's place, so the
    /// weekly share moves into this line instead of a hard-coded saving. Kept
    /// short: it shares its row with the trial label on a 4.7-inch screen.
    static func annualLine(for annual: Package, trialEligible: Bool) -> String {
        guard trialEligible, let perWeek = weeklyShare(of: annual) else {
            return String(localized: "Billed yearly", comment: "Paywall subline under the annual plan price when no trial is offered")
        }
        return String(localized: "\(perWeek) a week", comment: "Paywall subline under the annual plan price when a trial is offered — placeholder is the annual price divided by 52, e.g. \"$0.58 a week\". Keep it short")
    }

    static func weeklyLine(trialEligible: Bool) -> String {
        trialEligible
            ? String(localized: "Most flexible", comment: "Paywall subline under the weekly plan price when a trial is offered")
            : String(localized: "Billed weekly", comment: "Paywall subline under the weekly plan price when no trial is offered")
    }

    static func weeklyShare(of annual: Package) -> String? {
        let perWeek = annual.storeProduct.price / 52
        guard let formatter = annual.storeProduct.priceFormatter else { return nil }
        return formatter.string(from: NSDecimalNumber(decimal: perWeek))
    }

    /// The terms App Review wants next to the button: what is charged, when, and
    /// that it renews.
    static func renewalDisclosure(price: String, trial: String?) -> String {
        guard let trial else {
            return String(localized: "\(price). Renews automatically until cancelled.", comment: "Line under the paywall buy button for a subscription without a trial — placeholder is the price with its period, e.g. \"$29.99/yr\"")
        }
        return String(localized: "\(trial), then \(price). Renews automatically until cancelled.", comment: "Line under the paywall buy button for a subscription with a free trial — first placeholder is the trial, e.g. \"1-week free trial\"; second is the price with its period, e.g. \"$29.99/yr\"")
    }
}
