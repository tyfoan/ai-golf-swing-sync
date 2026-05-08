//
//  PaywallCTA.swift
//  golf-sync-swing
//
//  Full-width call-to-action button + small sub-line. Label and sub-line
//  adapt to the selected plan (trial wording for subs, "buy forever" for
//  lifetime). Disabled while a purchase is in flight.
//

import SwiftUI

struct PaywallCTA: View {

    let plan: PaywallPlan?
    let isWorking: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            actionButton
            subline
        }
    }

    private var actionButton: some View {
        Button(action: onTap) {
            ZStack {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(label)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
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
        .disabled(plan == nil || isWorking)
        .opacity(plan == nil ? 0.5 : 1)
    }

    private var subline: some View {
        Text(sublineText)
            .font(.caption2)
            .foregroundStyle(Color.white.opacity(0.5))
    }

    private var label: String {
        guard let plan else { return "Continue" }
        switch plan.kind {
        case .lifetime:
            return "Buy Forever — \(plan.priceString)"
        case .annual where plan.trialString != nil:
            return "Start \(plan.trialString ?? "")"
        case .annual:
            return "Subscribe — \(plan.priceString)"
        case .weekly where plan.trialString != nil:
            return "Start \(plan.trialString ?? "")"
        case .weekly:
            return "Subscribe — \(plan.priceString)"
        }
    }

    private var sublineText: String {
        guard let plan else { return " " }
        return plan.kind == .lifetime ? "One-time payment." : "Cancel anytime."
    }
}
