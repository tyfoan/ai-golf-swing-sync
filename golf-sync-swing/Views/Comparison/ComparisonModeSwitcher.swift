//
//  ComparisonModeSwitcher.swift
//  golf-sync-swing
//
//  The four comparison modes as one glass capsule of icons, so switching between
//  side-by-side and one-above-the-other is a single visible tap. Premium modes carry a
//  lock; the caller decides what a tap on one does.
//

import SwiftUI

struct ComparisonModeSwitcher: View {
    let selection: ComparisonMode
    let onSelect: (ComparisonMode) -> Void

    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ComparisonMode.allCases) { mode in
                segment(mode)
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
    }

    private func segment(_ mode: ComparisonMode) -> some View {
        Button { onSelect(mode) } label: {
            Image(systemName: mode.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(mode == selection ? Color.white : Color.primary.opacity(mode.isAvailable ? 0.85 : 0.35))
                .frame(width: 44, height: 38)
                .background { selectionCapsule(mode) }
                .overlay(alignment: .topTrailing) { lockBadge(mode) }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName(of: mode))
        .accessibilityAddTraits(mode == selection ? .isSelected : [])
    }

    @ViewBuilder
    private func selectionCapsule(_ mode: ComparisonMode) -> some View {
        if mode == selection {
            Capsule().fill(Color.fairwayGreen).matchedGeometryEffect(id: "selection", in: highlight)
        }
    }

    @ViewBuilder
    private func lockBadge(_ mode: ComparisonMode) -> some View {
        if !mode.isAvailable {
            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.onboardingGoldDim)
                .padding(5)
        }
    }

    private func accessibilityName(of mode: ComparisonMode) -> String {
        guard !mode.isAvailable else { return mode.displayName }
        return String(localized: "\(mode.displayName) (Pro)", comment: "Mode picker label for premium-locked modes")
    }
}
