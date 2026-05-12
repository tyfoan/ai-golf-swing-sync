//
//  OperationProgressView.swift
//  golf-sync-swing
//
//  Reusable "something is happening" indicator. Pairs a linear progress
//  bar (or spinner when progress is unknown) with a title and optional
//  subtitle. The bar's color follows `.tint` from the environment so
//  callers can theme it per-context.
//

import SwiftUI

struct OperationProgressView: View {
    let title: String
    let subtitle: String?
    let progress: Double?

    init(title: String, subtitle: String? = nil, progress: Double? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
    }

    var body: some View {
        VStack(spacing: 12) {
            indicator
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var indicator: some View {
        if let progress {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
        } else {
            ProgressView()
                .scaleEffect(1.5)
        }
    }
}
