//
//  PaywallCTA.swift
//  golf-sync-swing
//
//  Full-width call-to-action button with the plan's disclosure under it:
//  the trial, the price that follows and the renewal, or the one-time
//  payment for lifetime. Disabled while a purchase is in flight.
//

import SwiftUI

struct PaywallCTA: View {

    let plan: PaywallPlan?
    let isWorking: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            actionButton
            disclosure
        }
    }

    private var actionButton: some View {
        Button(action: onTap) {
            buttonFace
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(buttonFill, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.fairwayGreen.opacity(0.4), radius: 12, y: 4)
        }
        .disabled(plan == nil || isWorking)
        .opacity(plan == nil ? 0.5 : 1)
    }

    /// A spinner while the purchase is in flight, the label otherwise.
    private var buttonFace: some View {
        ZStack {
            if isWorking {
                ProgressView().tint(.white)
            } else {
                Text(label)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var buttonFill: LinearGradient {
        LinearGradient(
            colors: [Color.onboardingRichGreen, Color.fairwayGreen],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var disclosure: some View {
        Text(plan?.disclosure ?? " ")
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.75))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var label: String {
        guard let plan else { return String(localized: "Continue", comment: "Paywall CTA placeholder while plans are loading") }
        switch plan.kind {
        case .lifetime:
            return String(localized: "Buy Forever — \(plan.card.priceString)", comment: "Paywall lifetime CTA button label with price")
        case .annual where plan.card.trialString != nil:
            return String(localized: "Start \(plan.card.trialString ?? "")", comment: "Paywall trial-start CTA (e.g. 'Start 7-day free trial')")
        case .annual:
            return String(localized: "Subscribe — \(plan.card.priceString)", comment: "Paywall annual subscribe CTA with price")
        case .weekly where plan.card.trialString != nil:
            return String(localized: "Start \(plan.card.trialString ?? "")", comment: "Paywall trial-start CTA (e.g. 'Start 3-day free trial')")
        case .weekly:
            return String(localized: "Subscribe — \(plan.card.priceString)", comment: "Paywall weekly subscribe CTA with price")
        }
    }
}
