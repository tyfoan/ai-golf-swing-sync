//
//  SettingsView.swift
//  golf-sync-swing
//
//  App settings with subscription management, restore purchases,
//  and Customer Center for self-service subscription control.
//

import SwiftUI
import RevenueCat
import RevenueCatUI

struct SettingsView: View {

    @State private var showPaywall = false
    @State private var showCustomerCenter = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    private var purchaseService: PurchaseService { .shared }

    var body: some View {
        NavigationStack {
            List {
                subscriptionSection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) {
                PaywallView(displayCloseButton: true)
            }
            .sheet(isPresented: $showCustomerCenter) {
                CustomerCenterView()
            }
            .alert("Restore Purchases", isPresented: .constant(restoreMessage != nil)) {
                Button("OK") { restoreMessage = nil }
            } message: {
                Text(restoreMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var subscriptionSection: some View {
        Section {
            if purchaseService.isPremium {
                premiumBadge
                manageSubscriptionButton
            } else {
                upgradeButton
            }
            restoreButton
        } header: {
            Text("Subscription")
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Components

    private var premiumBadge: some View {
        HStack {
            Image(systemName: "crown.fill")
                .foregroundStyle(Color.sand)
            Text("Premium Active")
                .fontWeight(.semibold)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.fairwayGreen)
        }
    }

    private var upgradeButton: some View {
        Button {
            showPaywall = true
        } label: {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundStyle(Color.sand)
                Text("Upgrade to Premium")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var manageSubscriptionButton: some View {
        Button {
            showCustomerCenter = true
        } label: {
            HStack {
                Image(systemName: "gear")
                Text("Manage Subscription")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var restoreButton: some View {
        Button {
            Task { await restore() }
        } label: {
            HStack {
                Image(systemName: "arrow.clockwise")
                Text("Restore Purchases")
                Spacer()
                if isRestoring {
                    ProgressView()
                }
            }
        }
        .disabled(isRestoring)
    }

    // MARK: - Actions

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            let info = try await purchaseService.restorePurchases()
            let active = info.entitlements[PurchaseService.entitlementID]?.isActive == true
            restoreMessage = active
                ? "Premium access restored successfully."
                : "No previous purchases found."
        } catch {
            restoreMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
