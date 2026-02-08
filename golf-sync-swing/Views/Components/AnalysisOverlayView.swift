//
//  AnalysisOverlayView.swift
//  golf-sync-swing
//
//  Small non-blocking pill shown while auto-detection runs.
//  Positioned at the bottom of the video area so it doesn't
//  obscure the content.
//

import SwiftUI

struct AnalysisOverlayView: View {
    let isAnalyzing: Bool
    let progress: Float
    let status: String

    var body: some View {
        if isAnalyzing {
            VStack {
                Spacer()
                pill
            }
            .padding(.bottom, 8)
        }
    }

    private var pill: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
            Text(status)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            Text("\(Int(progress * 100))%")
                .font(.caption2).monospacedDigit()
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial.opacity(0.8))
        .clipShape(Capsule())
    }
}
