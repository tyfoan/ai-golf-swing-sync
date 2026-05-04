//
//  AppPaywallView.swift
//  golf-sync-swing
//
//  Custom full-screen paywall following Adam Lyttle's conversion pattern:
//  Hero animation → Feature list → Subscription options → CTA
//
//  Uses RevenueCat SDK for fetching offerings and processing purchases.
//

import SwiftUI
import RevenueCat
import os

struct AppPaywallView: View {

    let source: PaywallSource
    let onDismiss: () -> Void

    @State private var packages: [Package] = []
    @State private var selectedPackage: Package?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var offeringsError: String?
    @State private var heroScale: CGFloat = 0.8
    @State private var heroOpacity: Double = 0

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            background
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    closeButton
                    heroSection
                    socialProof
                    featureList
                    subscriptionOptions
                    purchaseButton
                    transparencyText
                    restoreLink
                    legalLinks
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .task { await loadOfferings() }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
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
                .onboardingDark,      .onboardingMidGreen,  .onboardingDark,
                .onboardingDeepGreen, .onboardingRichGreen,  .onboardingDeepGreen,
                .onboardingDark,      .onboardingDeepGreen, .onboardingDark
            ]
        )
        .ignoresSafeArea()
    }

    // MARK: - Close Button

    private var closeButton: some View {
        HStack {
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            animatedHeroIcon
            Text("Unlock AI Analysis")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text("AI-powered tools for the serious golfer")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .onAppear { animateHero() }
    }

    private var animatedHeroIcon: some View {
        ZStack {
            Circle()
                .stroke(Color.onboardingGold.opacity(0.2), lineWidth: 2)
                .frame(width: 140, height: 140)
                .scaleEffect(heroScale * 1.2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.onboardingGold.opacity(0.12), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)

            Image(systemName: "brain")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.onboardingGold, Color.onboardingGoldLight, Color.onboardingGold],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(heroScale)
                .opacity(heroOpacity)
        }
    }

    // MARK: - Social Proof

    private var socialProof: some View {
        Text("Join golfers improving their swing")
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.5))
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(spacing: 12) {
            PaywallFeatureRow(
                icon: "arrow.triangle.2.circlepath",
                title: "AI-Synchronized Playback",
                subtitle: "Automatic alignment at the moment of impact"
            )
            PaywallFeatureRow(
                icon: "square.on.square",
                title: "Onion Skin & Overlay",
                subtitle: "Layer swings for detailed visual comparison"
            )
            PaywallFeatureRow(
                icon: "cpu",
                title: "AI Phase Detection",
                subtitle: "Identifies backswing, downswing, and follow-through"
            )
            PaywallFeatureRow(
                icon: "square.and.arrow.up",
                title: "HD Export",
                subtitle: "Export comparisons without watermark"
            )
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Subscription Options

    @ViewBuilder
    private var subscriptionOptions: some View {
        if let offeringsError {
            VStack(spacing: 12) {
                Text(offeringsError)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                Button("Tap to Retry") { Task { await loadOfferings() } }
                    .font(.footnote).fontWeight(.medium)
                    .foregroundStyle(Color.onboardingGold)
            }
            .padding()
        } else if packages.isEmpty {
            ProgressView("Loading plans...")
                .tint(.white)
                .padding()
        } else {
            VStack(spacing: 10) {
                ForEach(packages, id: \.identifier) { package in
                    SubscriptionOptionView(
                        package: package,
                        isSelected: selectedPackage?.identifier == package.identifier,
                        savingsBadge: savingsBadge(for: package),
                        action: { selectedPackage = package }
                    )
                }
            }
        }
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(purchaseButtonTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.onboardingRichGreen, Color.fairwayGreen],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .shadow(color: Color.fairwayGreen.opacity(0.4), radius: 12, y: 4)
        }
        .disabled(selectedPackage == nil || isPurchasing)
        .opacity(selectedPackage == nil ? 0.6 : 1.0)
    }

    private var purchaseButtonTitle: String {
        guard let package = selectedPackage else { return "Select a Plan" }
        let intro = package.storeProduct.introductoryDiscount
        let hasFreeTrial = intro != nil && intro?.paymentMode == .freeTrial
        return hasFreeTrial ? "Start Free Trial" : "Subscribe Now"
    }

    // MARK: - Transparency

    private var transparencyText: some View {
        Text(transparencyString)
            .font(.caption2)
            .foregroundStyle(Color.white.opacity(0.35))
            .multilineTextAlignment(.center)
    }

    private var transparencyString: String {
        guard let package = selectedPackage else { return "" }
        let price = package.storeProduct.localizedPriceString
        let period = periodName(for: package)
        let trialText = trialPeriodText(for: package)
        return trialText.map { "\($0), then \(price)/\(period). Cancel anytime." }
            ?? "\(price)/\(period). Cancel anytime."
    }

    private func trialPeriodText(for package: Package) -> String? {
        guard let intro = package.storeProduct.introductoryDiscount,
              intro.paymentMode == .freeTrial else { return nil }
        let count = intro.subscriptionPeriod.value
        let unit = intro.subscriptionPeriod.unit
        let unitName: String = switch unit {
        case .day:   count == 1 ? "day" : "days"
        case .week:  count == 1 ? "week" : "weeks"
        case .month: count == 1 ? "month" : "months"
        case .year:  count == 1 ? "year" : "years"
        @unknown default: "period"
        }
        return "\(count)-\(unitName) free trial"
    }

    private func periodName(for package: Package) -> String {
        switch package.packageType {
        case .weekly:  return "week"
        case .monthly: return "month"
        case .annual:  return "year"
        default:       return "period"
        }
    }

    // MARK: - Restore

    private var restoreLink: some View {
        Button("Restore Purchases") {
            Task { await restore() }
        }
        .font(.footnote)
        .foregroundStyle(Color.white.opacity(0.4))
    }

    // MARK: - Legal

    private var legalLinks: some View {
        HStack(spacing: 16) {
            Link("Terms of Use", destination: termsURL)
            Text("|")
                .foregroundStyle(.quaternary)
            Link("Privacy Policy", destination: privacyURL)
        }
        .font(.caption2)
        .foregroundStyle(Color.white.opacity(0.3))
    }

    private var termsURL: URL {
        URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    }

    private var privacyURL: URL {
        URL(string: "https://withcoach.app/privacy")!
    }

    // MARK: - Data Loading

    private func loadOfferings() async {
        offeringsError = nil
        do {
            let offerings = try await withTimeout(seconds: 10) {
                try await Purchases.shared.offerings()
            }
            guard let current = offerings.current else {
                offeringsError = "No subscription plans available. Please try again later."
                return
            }
            packages = current.availablePackages
            selectedPackage = preferredDefault(from: packages)
        } catch {
            offeringsError = "Could not load subscription plans. Check your connection and try again."
            AppLogger.general.error("Paywall: failed to load offerings — \(error)")
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw CancellationError()
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }

    private func preferredDefault(from packages: [Package]) -> Package? {
        // Weekly pre-selected: trial-start rate is the primary metric for first paywall.
        // Annual remains visible as the alternative.
        packages.first { $0.packageType == .weekly }
            ?? packages.first { $0.packageType == .annual }
            ?? packages.first
    }

    // MARK: - Purchase

    private func purchase() async {
        guard let package = selectedPackage else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            guard !result.userCancelled else { return }

            let isActive = result.customerInfo.entitlements[PurchaseService.entitlementID]?.isActive == true
            if isActive {
                await PurchaseService.shared.refreshStatus()
                onDismiss()
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let info = try await Purchases.shared.restorePurchases()
            let isActive = info.entitlements[PurchaseService.entitlementID]?.isActive == true
            if isActive {
                await PurchaseService.shared.refreshStatus()
                onDismiss()
                dismiss()
            } else {
                errorMessage = "No previous purchases found."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Savings Badge

    private func savingsBadge(for package: Package) -> String? {
        guard let baseline = shortestPeriodPackage else { return nil }
        guard baseline.identifier != package.identifier else { return nil }

        let baseWeeklyPrice = weeklyEquivalentPrice(for: baseline)
        let packageWeeklyPrice = weeklyEquivalentPrice(for: package)
        guard baseWeeklyPrice > 0 else { return nil }

        let savings = ((baseWeeklyPrice - packageWeeklyPrice) / baseWeeklyPrice) * 100
        let percent = NSDecimalNumber(decimal: savings).intValue
        return percent > 0 ? "Save \(percent)%" : nil
    }

    private var shortestPeriodPackage: Package? {
        packages.min { weeksInPeriod($0) < weeksInPeriod($1) }
    }

    private func weeksInPeriod(_ package: Package) -> Int {
        switch package.packageType {
        case .weekly:  return 1
        case .monthly: return 4
        case .annual:  return 52
        default:       return 1
        }
    }

    private func weeklyEquivalentPrice(for package: Package) -> Decimal {
        let price = package.storeProduct.price as Decimal
        let weeks = Decimal(weeksInPeriod(package))
        return price / weeks
    }

    // MARK: - Animation

    private func animateHero() {
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            heroScale = 1.0
            heroOpacity = 1.0
        }
    }
}
