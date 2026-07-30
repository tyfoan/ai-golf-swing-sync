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
                CaptureSettingsSection()
                aboutSection
            }
            .navigationTitle("Settings")
            .fullScreenCover(isPresented: $showPaywall) {
                AppPaywallView(source: .settings, onDismiss: { showPaywall = false })
            }
            .sheet(isPresented: $showCustomerCenter) {
                CustomerCenterView()
            }
            .alert("Restore Purchases", isPresented: Binding(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } }
            )) {
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

        supportSection
        legalSection

        #if DEBUG
        DebugSettingsSection()
        #endif
    }

    private var supportSection: some View {
        Section {
            externalLinkRow(
                "Contact Support",
                url: "mailto:examply.app@gmail.com?subject=Golf%20Sync%20Swing%20Support"
            )
        } header: {
            Text("Support")
        }
    }

    private var legalSection: some View {
        Section {
            externalLinkRow("Terms of Use", url: "https://www.withcoach.app/terms")
            externalLinkRow("Privacy Policy", url: "https://www.withcoach.app/privacy")
        } header: {
            Text("Legal")
        }
    }

    private func externalLinkRow(_ title: LocalizedStringKey, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                Image(systemName: "chevron.forward")
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
                Image(systemName: "chevron.forward")
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
                ? String(localized: "Premium access restored successfully.", comment: "Confirmation after Restore Purchases finds an active premium entitlement")
                : String(localized: "No previous purchases found.", comment: "Result of Restore Purchases when no prior purchase is associated with the user's Apple ID")
        } catch {
            restoreMessage = String(localized: "Restore failed: \(error.localizedDescription)", comment: "Restore Purchases failure — placeholder is the system-provided error description")
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
