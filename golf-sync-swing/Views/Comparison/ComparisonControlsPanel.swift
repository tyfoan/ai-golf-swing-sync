//
//  ComparisonControlsPanel.swift
//  golf-sync-swing
//
//  Below the stage: the overlay opacity (stacked mode only), the timeline with its
//  impact mark, and the transport.
//

import SwiftUI

struct ComparisonControlsPanel: View {
    @Bindable var viewModel: ComparisonViewModel

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.comparisonMode.showsOpacitySlider {
                OverlayOpacitySlider(opacity: $viewModel.stackedOpacity)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            ComparisonTimelineSlider(viewModel: viewModel)
            TransportControlsView(model: viewModel)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// How see-through the front swing is in stacked mode.
struct OverlayOpacitySlider: View {
    @Binding var opacity: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.caption).foregroundStyle(.secondary)
            Slider(value: $opacity, in: 0.1...0.9)
                .tint(Color.appTeal)
            Image(systemName: "circle.righthalf.filled")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
