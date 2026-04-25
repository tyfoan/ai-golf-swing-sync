//
//  SubscriptionOptionView.swift
//  golf-sync-swing
//
//  A selectable subscription plan card showing price, period,
//  and optional savings badge.
//

import SwiftUI
import RevenueCat

struct SubscriptionOptionView: View {

    let package: Package
    let isSelected: Bool
    let savingsBadge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                selectionIndicator
                priceInfo
                Spacer()
                badge
            }
            .padding(16)
            .background(cardBackground)
            .overlay(cardBorder)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Components

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Color.onboardingGold : Color.white.opacity(0.2), lineWidth: 2)
                .frame(width: 22, height: 22)

            if isSelected {
                Circle()
                    .fill(Color.onboardingGold)
                    .frame(width: 14, height: 14)
            }
        }
    }

    private var priceInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(periodLabel)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text(package.storeProduct.localizedPriceString + " / " + shortPeriod)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(.leading, 8)
    }

    @ViewBuilder
    private var badge: some View {
        if let savingsBadge {
            Text(savingsBadge)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.onboardingGold, in: Capsule())
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isSelected ? Color.onboardingGold.opacity(0.08) : Color.white.opacity(0.04))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(isSelected ? Color.onboardingGold : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
    }

    // MARK: - Helpers

    private var periodLabel: String {
        switch package.packageType {
        case .weekly:  return "Weekly"
        case .monthly: return "Monthly"
        case .annual:  return "Annual"
        default:       return package.storeProduct.localizedTitle
        }
    }

    private var shortPeriod: String {
        switch package.packageType {
        case .weekly:  return "week"
        case .monthly: return "month"
        case .annual:  return "year"
        default:       return "period"
        }
    }
}
