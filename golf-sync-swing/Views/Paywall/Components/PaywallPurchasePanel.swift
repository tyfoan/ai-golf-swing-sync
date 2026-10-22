//
//  PaywallPurchasePanel.swift
//  golf-sync-swing
//
//  The buying half of the paywall: the plan cards, the buy button with its
//  disclosure, and the Restore · Terms · Privacy row. App Review needs the
//  disclosure and those links next to the button, so they always travel
//  together. The paywall pins this panel to the bottom, except at
//  accessibility text sizes, where it scrolls with the rest of the content.
//

import SwiftUI

struct PaywallPurchasePanel: View {

    @Bindable var viewModel: PaywallViewModel
    let isWorking: Bool
    let onPurchase: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            PaywallErrorBanner(state: viewModel.state, onRetry: retryLoad)
            PaywallPlanPicker(plans: viewModel.plans, selectedId: $viewModel.selectedPlanId)
            PaywallCTA(plan: viewModel.selectedPlan(), isWorking: isWorking, onTap: onPurchase)
            PaywallFooter(onRestore: onRestore)
        }
        .padding(.top, 12)
    }

    private func retryLoad() {
        Task { await viewModel.loadOffering() }
    }
}

extension View {

    /// The dark backdrop, with a short fade above it, that separates the pinned
    /// panel from the content scrolling underneath.
    func paywallPinnedBackdrop() -> some View {
        background(alignment: .top) {
            ZStack(alignment: .top) {
                Color.onboardingDark
                LinearGradient(
                    colors: [Color.onboardingDark.opacity(0), Color.onboardingDark],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
                .offset(y: -28)
            }
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }
}
