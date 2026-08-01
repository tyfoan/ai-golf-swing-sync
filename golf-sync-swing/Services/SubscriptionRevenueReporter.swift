//
//  SubscriptionRevenueReporter.swift
//  golf-sync-swing
//
//  Reports recognised revenue from the RevenueCat entitlement stream.
//
//  The paywall can only observe the tap that STARTS a subscription. Because every plan
//  offers a free trial, the paywall's paid branch was never taken and no revenue ever
//  reached Amplitude. Entitlement transitions are the real signal: they also cover
//  trial→paid conversions and renewals, neither of which the paywall ever sees.
//
//  Lives on the purchase side of the seam, not in Services/Analytics, so the analytics
//  layer keeps its promise of never importing the purchase SDK — this type is the
//  translator from EntitlementInfo to the SDK-free PurchaseRevenue.
//
//  Known limitation: pricing comes from a live product lookup, which returns the
//  CURRENT storefront price. Renewals for subscribers grandfathered on an old price
//  over-report after a price rise; only a server-side RevenueCat → Amplitude
//  integration can price receipts exactly.
//

import Foundation
import RevenueCat
import os

final class SubscriptionRevenueReporter {

    /// Looks up store products for the given identifiers. Injected so tests need no SDK.
    typealias ProductLookup = ([String]) async -> [StoreProduct]

    private static let lastReportedKey = "analytics.lastReportedPurchaseDate"

    private let analytics: AnalyticsTracking
    private let defaults: UserDefaults
    private let lookUpProducts: ProductLookup

    init(
        analytics: AnalyticsTracking = Analytics.shared,
        defaults: UserDefaults = .standard,
        lookUpProducts: ProductLookup? = nil
    ) {
        self.analytics = analytics
        self.defaults = defaults
        self.lookUpProducts = lookUpProducts ?? { await Purchases.shared.products($0) }
    }

    /// Emits revenue at most once per purchase or renewal.
    ///
    /// De-duplication keys on the entitlement's `latestPurchaseDate`, persisted across
    /// launches: a returning subscriber must not re-report revenue every time the app
    /// starts, while a genuine renewal — which advances that date — must report again.
    /// Storing a single date means several renewals missed between launches collapse
    /// into one report of the latest; full fidelity needs the server-side
    /// RevenueCat → Amplitude integration.
    func reportIfNeeded(entitlement: EntitlementInfo?) async {
        guard let entitlement, let purchaseDate = entitlement.latestPurchaseDate else { return }
        let previouslyReported = defaults.object(forKey: Self.lastReportedKey) as? Date
        guard Self.shouldReport(
            isActive: entitlement.isActive,
            isSandbox: entitlement.isSandbox,
            isStandardPeriod: entitlement.periodType == .normal,
            purchaseDate: purchaseDate,
            previouslyReported: previouslyReported,
            now: Date()
        ) else { return }
        await report(
            productId: entitlement.productIdentifier,
            purchaseDate: purchaseDate,
            originalPurchaseDate: entitlement.originalPurchaseDate
        )
    }

    /// The 48-hour window applies only to the first-ever report, where the empty dedup
    /// state cannot distinguish a fresh purchase from a reinstall or second device
    /// replaying an old renewal date. Once a report is persisted, a later
    /// `latestPurchaseDate` alone proves a new charge — renewals and trial→paid
    /// conversions happen server-side while the app is closed, so they are routinely
    /// first observed days later and must still report.
    static let reportingWindow: TimeInterval = 48 * 60 * 60

    /// The whole reporting decision, pure so it is testable without the RevenueCat SDK.
    ///
    /// Only standard periods report: trials recognise no money, and paid introductory
    /// offers would be priced wrongly by the live product lookup, which returns the
    /// current standard price rather than what the intro payer was charged. Skipping
    /// intros under-counts slightly; the first standard renewal reports correctly.
    static func shouldReport(
        isActive: Bool,
        isSandbox: Bool,
        isStandardPeriod: Bool,
        purchaseDate: Date?,
        previouslyReported: Date?,
        now: Date
    ) -> Bool {
        guard isActive, !isSandbox, isStandardPeriod else { return false }
        guard let purchaseDate else { return false }
        guard let previouslyReported else {
            return now.timeIntervalSince(purchaseDate) <= reportingWindow
        }
        return purchaseDate > previouslyReported
    }

    /// A charge is a renewal when it is not the entitlement's first transaction:
    /// `originalPurchaseDate` marks that first transaction, so any later charge —
    /// a billing-cycle renewal, or a trial→paid conversion, which StoreKit bills as
    /// a renewal of the trial — advances past it. Non-renewing products (lifetime)
    /// are never renewals, whatever the entitlement's earlier history says.
    static func isRenewal(
        purchaseDate: Date,
        originalPurchaseDate: Date?,
        isSubscription: Bool
    ) -> Bool {
        guard isSubscription, let originalPurchaseDate else { return false }
        return purchaseDate > originalPurchaseDate
    }

    private func report(productId: String, purchaseDate: Date, originalPurchaseDate: Date?) async {
        guard let product = await lookUpProducts([productId]).first else {
            AppLogger.general.error("SubscriptionRevenueReporter: no product for \(productId)")
            return
        }

        let revenue = PurchaseRevenue(
            productId: product.productIdentifier,
            price: NSDecimalNumber(decimal: product.price).doubleValue,
            currency: product.currencyCode ?? "USD"
        )

        analytics.record(revenue)
        analytics.track(.revenueRecognized(
            revenue: revenue,
            isRenewal: Self.isRenewal(
                purchaseDate: purchaseDate,
                originalPurchaseDate: originalPurchaseDate,
                isSubscription: product.subscriptionPeriod != nil
            )
        ))
        defaults.set(purchaseDate, forKey: Self.lastReportedKey)
        AppLogger.general.info("SubscriptionRevenueReporter: reported \(revenue.price) \(revenue.currency)")
    }
}
