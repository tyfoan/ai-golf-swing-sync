//
//  PurchaseService.swift
//  golf-sync-swing
//
//  Manages RevenueCat subscription state and entitlement checking.
//  Single source of truth for premium access across the app.
//

import Foundation
import Observation
import RevenueCat
import os

@Observable
final class PurchaseService {

    static let shared = PurchaseService()

    private(set) var isPremium = false
    private(set) var customerInfo: CustomerInfo?
    private(set) var isConfigured = false

    static let entitlementID = "Golf Swing Sync Premium"

    #if DEBUG
    // Swap to "test_MXPuGlggjlfQHxlnRQsOUthWyYo" to point at the RC Test Store project.
    static let apiKey = "appl_SrTcnIuqMXaqoRYvaecigbeOOoW"
    #else
    static let apiKey = "appl_SrTcnIuqMXaqoRYvaecigbeOOoW"
    #endif

    private let revenueReporter: SubscriptionRevenueReporter

    private init(revenueReporter: SubscriptionRevenueReporter = SubscriptionRevenueReporter()) {
        self.revenueReporter = revenueReporter
    }

    // MARK: - Configuration

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: Self.apiKey)
        AppLogger.general.info("PurchaseService: RevenueCat configured")

        // This unstructured Task lives as long as the singleton. Since PurchaseService.shared
        // is never deallocated, the Task runs for the entire app lifetime, continuously receiving
        // customerInfoStream updates from RevenueCat. No cancellation handle is needed.
        Task { await observeCustomerInfo() }
    }

    // MARK: - Observation

    private func observeCustomerInfo() async {
        for await info in Purchases.shared.customerInfoStream {
            let premium = info.entitlements[Self.entitlementID]?.isActive == true
            // @Observable state is read by SwiftUI on the main thread; publish it there.
            await MainActor.run {
                self.customerInfo = info
                self.isPremium = premium
                Analytics.shared.identify(userId: Purchases.shared.appUserID)
                Analytics.shared.setPremium(premium)
            }
            AppLogger.general.info("PurchaseService: premium=\(premium)")
            await revenueReporter.reportIfNeeded(entitlement: info.entitlements[Self.entitlementID])
        }
    }

    // MARK: - Actions

    @MainActor
    func restorePurchases() async throws -> CustomerInfo {
        let info = try await Purchases.shared.restorePurchases()
        customerInfo = info
        isPremium = info.entitlements[Self.entitlementID]?.isActive == true
        return info
    }

    @MainActor
    func refreshStatus() async {
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        customerInfo = info
        isPremium = info.entitlements[Self.entitlementID]?.isActive == true
    }
}
