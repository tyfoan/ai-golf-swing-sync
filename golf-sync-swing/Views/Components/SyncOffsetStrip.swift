//
//  SyncOffsetStrip.swift
//  golf-sync-swing
//
//  Visible sync-offset adjustment: ± frame nudge buttons
//  with a label showing the current offset in milliseconds.
//

import SwiftUI

struct SyncOffsetStrip: View {
    let viewModel: ComparisonViewModel

    /// One frame at 30 fps ≈ 33ms
    private let frameStep: TimeInterval = 1.0 / 30.0

    var body: some View {
        HStack(spacing: 12) {
            nudgeButton(icon: "chevron.left.2", delta: -frameStep * 5)
            nudgeButton(icon: "chevron.left",   delta: -frameStep)
            offsetLabel
            nudgeButton(icon: "chevron.right",  delta: frameStep)
            nudgeButton(icon: "chevron.right.2", delta: frameStep * 5)
        }
    }

    // MARK: - Subviews

    private func nudgeButton(icon: String, delta: TimeInterval) -> some View {
        Button {
            viewModel.adjustSyncOffset(by: delta)
        } label: {
            Image(systemName: icon)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 32, height: 28)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var offsetLabel: some View {
        let ms = Int(viewModel.syncOffset * 1000)
        let sign = ms >= 0 ? "+" : ""
        return Text("Sync \(sign)\(ms)ms")
            .font(.caption2).monospacedDigit()
            .foregroundStyle(.white.opacity(0.4))
            .frame(minWidth: 80)
    }
}
