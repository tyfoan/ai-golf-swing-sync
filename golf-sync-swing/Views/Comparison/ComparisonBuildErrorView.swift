//
//  ComparisonBuildErrorView.swift
//  golf-sync-swing
//
//  Covers the stage when the composition could not be built, replacing an empty stage
//  with the reason and a way to try again.
//

import SwiftUI

struct ComparisonBuildErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            retryButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: StageCard.cornerRadius, style: .continuous))
    }

    private var retryButton: some View {
        Button(action: onRetry) {
            Text(String(localized: "Try Again", comment: "Button that retries loading the comparison videos after a failure"))
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(Color.appTeal)
                .clipShape(Capsule())
        }
    }
}
