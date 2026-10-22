//
//  ExportQualityPicker.swift
//  golf-sync-swing
//
//  One row per export tier. A locked tier stays visible but routes its tap to
//  the caller (the paywall) instead of selecting itself.
//

import SwiftUI

struct ExportQualityPicker: View {

    @Binding var selection: ExportQuality
    let renderSize: (ExportQuality) -> CGSize
    let onLockedTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quality").font(.subheadline).foregroundStyle(.secondary)
            ForEach(ExportQuality.allCases) { quality in
                row(quality)
            }
        }
    }

    private func row(_ quality: ExportQuality) -> some View {
        Button { choose(quality) } label: {
            rowLabel(quality)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == quality ? .isSelected : [])
    }

    private func rowLabel(_ quality: ExportQuality) -> some View {
        let isSelected = selection == quality
        let size = renderSize(quality)
        return HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.fairwayGreen : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: quality.title(renderSize: size))
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(quality.isLocked ? .secondary : .primary)
                Text(quality.detail(renderSize: size))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            lockBadge(quality)
        }
        .padding(.vertical, 6).padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(isSelected ? Color.fairwayGreen.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func lockBadge(_ quality: ExportQuality) -> some View {
        if quality.isLocked {
            Image(systemName: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func choose(_ quality: ExportQuality) {
        guard !quality.isLocked else {
            onLockedTap()
            return
        }
        selection = quality
    }
}
