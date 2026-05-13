//
//  PaywallPlanPicker.swift
//  golf-sync-swing
//
//  Three stacked plan cards (Lifetime, Annual default-selected, Weekly).
//  Each card shows the real billed price + trial copy + savings badge —
//  no hidden tricks, per Seraleev's transparency rule.
//

import SwiftUI

struct PaywallPlanPicker: View {

    let plans: [PaywallPlan]
    @Binding var selectedId: PaywallPlan.ID?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(plans) { plan in
                PaywallPlanCard(
                    plan: plan,
                    isSelected: plan.id == selectedId,
                    onTap: { selectedId = plan.id }
                )
            }
        }
    }
}

struct PaywallPlanCard: View {

    let plan: PaywallPlan
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(isSelected ? 0.06 : 0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(borderColor, lineWidth: 1.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 12) {
            selectionIndicator
            VStack(alignment: .leading, spacing: 4) {
                if let badge = plan.savingsBadge {
                    badgeLabel(badge)
                }
                titleRow
                detailRow
            }
            Spacer(minLength: 0)
            trailingPrice
        }
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                .frame(width: 22, height: 22)
            if isSelected {
                Circle()
                    .fill(Color.onboardingGold)
                    .frame(width: 14, height: 14)
            }
        }
    }

    private var titleRow: some View {
        Text(planTitle)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
    }

    private var detailRow: some View {
        Text(plan.lineUnderPrice)
            .font(.footnote)
            .foregroundStyle(Color.white.opacity(0.65))
    }

    @ViewBuilder
    private var trailingPrice: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(plan.priceString)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            if let trial = plan.trialString {
                Text(trial)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.onboardingGold)
            } else if let equivalent = plan.equivalentString {
                Text(equivalent)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }

    private func badgeLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(Color.onboardingDeepGreen)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.onboardingGold)
            )
    }

    private var planTitle: LocalizedStringKey {
        switch plan.kind {
        case .lifetime: return "Lifetime"
        case .annual:   return "Annual"
        case .weekly:   return "Weekly"
        }
    }

    private var borderColor: Color {
        isSelected ? Color.onboardingGold : Color.white.opacity(0.15)
    }
}
