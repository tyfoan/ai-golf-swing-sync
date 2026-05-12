//
//  CustomPaywallView.swift
//  golf-sync-swing
//
//  Hand-built SwiftUI paywall replacing the RevenueCatUI dashboard view.
//  Composes hero / feature list / plan picker / CTA / footer over a dark
//  mesh-gradient background. Owns PaywallViewModel and a close button
//  that's always visible (per Seraleev — no remote-config bait-switch).
//

import SwiftUI

struct CustomPaywallView: View {

    let source: PaywallSource
    let onDismiss: () -> Void

    @State private var viewModel: PaywallViewModel
    @State private var isWorking = false
    @State private var toast: ToastMessage?

    init(source: PaywallSource, onDismiss: @escaping () -> Void) {
        self.source = source
        self.onDismiss = onDismiss
        _viewModel = State(initialValue: PaywallViewModel(source: source))
    }

    var body: some View {
        ZStack {
            background
            PaywallDimpleLayer().ignoresSafeArea()
            content
            closeButton
            toastOverlay
        }
        .task { await viewModel.loadOffering() }
    }

    // MARK: - Background

    private var background: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                .onboardingDark,      .onboardingDeepGreen, .onboardingDark,
                .onboardingDeepGreen, .onboardingMidGreen,  .onboardingDeepGreen,
                .onboardingDark,      .onboardingDeepGreen, .onboardingDark
            ]
        )
        .ignoresSafeArea()
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                PaywallHero(source: source)
                PaywallFeatureList()
                PaywallFooter(onRestore: handleRestore)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            stickyBottomBlock
        }
    }

    private var stickyBottomBlock: some View {
        VStack(spacing: 12) {
            errorBanner
            PaywallPlanPicker(plans: viewModel.plans, selectedId: Binding(
                get: { viewModel.selectedPlanId },
                set: { viewModel.selectedPlanId = $0 }
            ))
            PaywallCTA(plan: viewModel.selectedPlan(), isWorking: isWorking, onTap: handlePurchase)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(alignment: .top) {
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

    @ViewBuilder
    private var errorBanner: some View {
        if case .failed(let message) = viewModel.state {
            Button(action: retryLoad) {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.flagRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.flagRed.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Close

    private var closeButton: some View {
        VStack {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(Color.white.opacity(0.08))
                        )
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast {
            VStack {
                Spacer()
                Text(toast.text)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(Color.charcoal.opacity(0.92))
                    )
                    .padding(.bottom, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .id(toast.id)
        }
    }

    // MARK: - Actions

    private func retryLoad() {
        Task { await viewModel.loadOffering() }
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
        case .succeeded:
            onDismiss()
        case .cancelled:
            break
        case .failed(let message):
            showToast(message)
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
            onDismiss()
        case .noActiveEntitlement:
            showToast("No previous purchase found.")
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

private struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
}
