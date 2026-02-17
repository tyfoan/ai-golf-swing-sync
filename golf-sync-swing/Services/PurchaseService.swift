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

    // TODO: Replace with production API key before App Store submission
    // Production keys start with "appl_" — test keys start with "test_"
    #if DEBUG
    static let apiKey = "test_MXPuGlggjlfQHxlnRQsOUthWyYo"
    #else
    static let apiKey = "test_MXPuGlggjlfQHxlnRQsOUthWyYo" // REPLACE with production key
    #endif

    private init() {}

    // MARK: - Configuration

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: Self.apiKey)
        AppLogger.general.info("PurchaseService: RevenueCat configured")

        Task { await observeCustomerInfo() }
    }

    // MARK: - Observation

    private func observeCustomerInfo() async {
        for await info in Purchases.shared.customerInfoStream {
            customerInfo = info
            isPremium = info.entitlements[Self.entitlementID]?.isActive == true
            AppLogger.general.info("PurchaseService: premium=\(self.isPremium)")
        }
    }

    // MARK: - Actions

    func restorePurchases() async throws -> CustomerInfo {
        let info = try await Purchases.shared.restorePurchases()
        customerInfo = info
        isPremium = info.entitlements[Self.entitlementID]?.isActive == true
        return info
    }

    func refreshStatus() async {
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        customerInfo = info
        isPremium = info.entitlements[Self.entitlementID]?.isActive == true
    }
}
