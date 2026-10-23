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

    /// Indicator width plus its spacing, so badge and detail line up with the title.
    private static let textInset: CGFloat = 34

    var body: some View {
        Button(action: onTap) {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // Badge, then title and price, then detail and trial: each on its own full-width
    // row, so nothing wraps on a 4.7-inch screen and the pinned panel stays short.
    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let badge = plan.card.savingsBadge {
                badgeLabel(badge)
                    .padding(.leading, Self.textInset)
            }
            headline
            detailLine
                .padding(.leading, Self.textInset)
        }
    }

    private var headline: some View {
        HStack(alignment: .center, spacing: 12) {
            selectionIndicator
            titleRow
            Spacer(minLength: 8)
            priceLabel
        }
    }

    private var detailLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            detailRow
            Spacer(minLength: 8)
            trailingNote
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
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
    }

    private var priceLabel: some View {
        Text(plan.card.priceString)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
    }

    private var detailRow: some View {
        Text(plan.card.lineUnderPrice)
            .font(.footnote)
            .foregroundStyle(Color.white.opacity(0.7))
    }

    @ViewBuilder
    private var trailingNote: some View {
        if let trial = plan.card.trialString {
            Text(trial)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.onboardingGold)
        } else if let equivalent = plan.card.equivalentString {
            Text(equivalent)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.6))
        }
    }

    private func badgeLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
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
