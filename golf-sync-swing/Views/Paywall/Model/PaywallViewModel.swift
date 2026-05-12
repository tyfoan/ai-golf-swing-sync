//
//  PaywallViewModel.swift
//  golf-sync-swing
//
//  Owns the data + side-effects of the custom paywall: fetches the
//  RevenueCat offering, maps packages into PaywallPlan view models, runs
//  purchase + restore. The view stays dumb — it observes published state.
//

import Foundation
import Observation
import RevenueCat
import os

@Observable
final class PaywallViewModel {

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    enum PurchaseOutcome: Equatable {
        case succeeded
        case cancelled
        case failed(String)
    }

    enum RestoreOutcome: Equatable {
        case succeeded
        case noActiveEntitlement
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var plans: [PaywallPlan] = []
    var selectedPlanId: PaywallPlan.ID?

    let source: PaywallSource

    private let purchases: PurchasesType
    private let entitlementID: String

    init(
        source: PaywallSource,
        purchases: PurchasesType = LivePurchases(),
        entitlementID: String = PurchaseService.entitlementID
    ) {
        self.source = source
        self.purchases = purchases
        self.entitlementID = entitlementID
    }

    // MARK: - Load

    func loadOffering() async {
        state = .loading
        do {
            let offerings = try await purchases.offerings()
            guard let current = offerings.current else {
                state = .failed("No paywall offering configured.")
                return
            }
            let mapped = await mapPlans(from: current)
            plans = mapped
            selectedPlanId = mapped.first(where: { $0.kind == .annual })?.id ?? mapped.first?.id
            state = .ready
        } catch {
            AppLogger.general.error("Paywall: load offerings failed — \(error.localizedDescription)")
            state = .failed("Couldn't load plans. Tap to retry.")
        }
    }

    // MARK: - Purchase

    func purchaseSelected() async -> PurchaseOutcome {
        guard let plan = selectedPlan() else { return .failed("No plan selected.") }
        do {
            let result = try await purchases.purchase(package: plan.package)
            if result.userCancelled { return .cancelled }
            await PurchaseService.shared.refreshStatus()
            return .succeeded
        } catch {
            AppLogger.general.error("Paywall: purchase failed — \(error.localizedDescription)")
            return .failed("Couldn't complete purchase.")
        }
    }

    // MARK: - Restore

    func restore() async -> RestoreOutcome {
        do {
            let info = try await purchases.restorePurchases()
            let active = info.entitlements[entitlementID]?.isActive == true
            if active {
                await PurchaseService.shared.refreshStatus()
                return .succeeded
            }
            return .noActiveEntitlement
        } catch {
            AppLogger.general.error("Paywall: restore failed — \(error.localizedDescription)")
            return .failed("Restore failed. Check your connection.")
        }
    }

    // MARK: - Helpers

    func selectedPlan() -> PaywallPlan? {
        plans.first(where: { $0.id == selectedPlanId })
    }

    private func mapPlans(from offering: Offering) async -> [PaywallPlan] {
        let lifetime = offering.lifetime
        let annual = offering.annual
        let weekly = offering.weekly
        let eligibility = await trialEligibility(for: [annual, weekly].compactMap { $0 })

        var built: [PaywallPlan] = []
        if let lifetime {
            built.append(.lifetime(from: lifetime))
        }
        if let annual {
            let eligible = eligibility[annual.storeProduct.productIdentifier] ?? true
            built.append(.annual(from: annual, weekly: weekly, trialEligible: eligible))
        }
        if let weekly {
            let eligible = eligibility[weekly.storeProduct.productIdentifier] ?? true
            built.append(.weekly(from: weekly, trialEligible: eligible))
        }
        return built
    }

    private func trialEligibility(for packages: [Package]) async -> [String: Bool] {
        let ids = packages.map { $0.storeProduct.productIdentifier }
        guard !ids.isEmpty else { return [:] }
        let dict = await purchases.checkTrialOrIntroDiscountEligibility(productIdentifiers: ids)
        var out: [String: Bool] = [:]
        for id in ids {
            out[id] = dict[id]?.status == .eligible
        }
        return out
    }
}

// MARK: - Purchases protocol seam (testability)

protocol PurchasesType: Sendable {
    func offerings() async throws -> Offerings
    func purchase(package: Package) async throws -> PurchaseResultData
    func restorePurchases() async throws -> CustomerInfo
    func checkTrialOrIntroDiscountEligibility(
        productIdentifiers: [String]
    ) async -> [String: IntroEligibility]
}

struct LivePurchases: PurchasesType {

    func offerings() async throws -> Offerings {
        try await Purchases.shared.offerings()
    }

    func purchase(package: Package) async throws -> PurchaseResultData {
        try await Purchases.shared.purchase(package: package)
    }

    func restorePurchases() async throws -> CustomerInfo {
        try await Purchases.shared.restorePurchases()
    }

    func checkTrialOrIntroDiscountEligibility(
        productIdentifiers: [String]
    ) async -> [String: IntroEligibility] {
        await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: productIdentifiers)
    }
}
