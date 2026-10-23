//
//  CustomPaywallView.swift
//  golf-sync-swing
//
//  Hand-built SwiftUI paywall replacing the RevenueCatUI dashboard view.
//  Composes hero / feature list over a dark mesh-gradient background, with
//  the purchase panel pinned at the bottom. Owns PaywallViewModel and a
//  close button that's always visible (per Seraleev — no remote-config
//  bait-switch).
//

import SwiftUI

struct CustomPaywallView: View {

    let source: PaywallSource
    let onDismiss: () -> Void

    @State private var viewModel: PaywallViewModel
    @State private var isWorking = false
    @State private var toast: ToastMessage?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(source: PaywallSource, onDismiss: @escaping () -> Void) {
        self.source = source
        self.onDismiss = onDismiss
        _viewModel = State(initialValue: PaywallViewModel(source: source))
    }

    var body: some View {
        ZStack {
            PaywallBackground()
            PaywallDimpleLayer().ignoresSafeArea()
            content
            PaywallCloseButton(isWorking: isWorking, onClose: close)
            PaywallToast(toast: toast)
        }
        .task {
            Analytics.shared.track(.paywallShown(source: source))
            await viewModel.loadOffering()
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            page
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pinnedPanel
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 22) {
            PaywallHero(source: source)
            PaywallFeatureList()
            if !pinsPurchasePanel {
                purchasePanel
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 56)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var pinnedPanel: some View {
        if pinsPurchasePanel {
            purchasePanel
                .padding(.horizontal, 24)
                .paywallPinnedBackdrop()
        }
    }

    private var purchasePanel: some View {
        PaywallPurchasePanel(
            viewModel: viewModel,
            isWorking: isWorking,
            onPurchase: handlePurchase,
            onRestore: handleRestore
        )
    }

    /// At accessibility text sizes the panel alone outgrows the screen, so it
    /// scrolls with the rest of the paywall instead of covering it.
    private var pinsPurchasePanel: Bool {
        !dynamicTypeSize.isAccessibilitySize
    }

    // MARK: - Actions

    private func close() {
        Analytics.shared.track(.paywallDismissed(source: source))
        onDismiss()
    }

    private func handlePurchase() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            let outcome = await viewModel.purchaseSelected()
            await MainActor.run {
                isWorking = false
                handlePurchaseOutcome(outcome)
            }
        }
    }

    private func handlePurchaseOutcome(_ outcome: PaywallViewModel.PurchaseOutcome) {
        switch outcome {
        case .succeeded(let record):
            Analytics.shared.track(.paywallPurchased(source: source))
            trackConversion(record)
            onDismiss()
        case .cancelled:
            break
        case .failed(let message):
            showToast(message)
        }
    }

    private func trackConversion(_ record: PurchaseRecord) {
        if record.isTrial {
            Analytics.shared.track(.trialStarted(plan: record.plan, productId: record.productId, source: source))
        } else {
            // Marks the conversion only. Revenue itself reaches Amplitude from RevenueCat's
            // server-side integration, so nothing here records money.
            let revenue = PurchaseRevenue(productId: record.productId, price: record.price, currency: record.currency)
            Analytics.shared.track(.purchaseCompleted(revenue: revenue, plan: record.plan, source: source))
        }
    }

    private func handleRestore() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            let outcome = await viewModel.restore()
            await MainActor.run {
                isWorking = false
                handleRestoreOutcome(outcome)
            }
        }
    }

    private func handleRestoreOutcome(_ outcome: PaywallViewModel.RestoreOutcome) {
        switch outcome {
        case .succeeded:
            Analytics.shared.track(.purchaseRestored(source: source))
            onDismiss()
        case .noActiveEntitlement:
            showToast(String(
                localized: "No previous purchases found.",
                comment: "Result of Restore Purchases when no prior purchase is associated with the user's Apple ID"
            ))
        case .failed(let message):
            showToast(message)
        }
    }

    private func showToast(_ text: String) {
        let message = ToastMessage(text: text)
        withAnimation(.easeInOut(duration: 0.25)) { toast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                guard toast?.id == message.id else { return }
                withAnimation(.easeInOut(duration: 0.25)) { toast = nil }
            }
        }
    }
}
