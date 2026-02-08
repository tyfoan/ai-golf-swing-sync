//
//  SwingDetectionPanel.swift
//  golf-sync-swing
//
//  Swing detection UI: auto-detect button, progress, swing list.
//  Extracted from SingleVideoPlayerView.
//

import SwiftUI

struct SwingDetectionPanel: View {
    @Bindable var video: SwingVideo
    let selectedSwingId: UUID?
    let isAnalyzing: Bool
    let analysisProgress: Float
    let analysisStatus: String

    var onAutoDetect: () -> Void
    var onManualAdd: () -> Void
    var onSwingTap: (SwingMarker) -> Void
    var onSwingEdit: (SwingMarker) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isAnalyzing {
                analysisProgressView
            } else if video.swings.isEmpty {
                emptySwingsView
            } else {
                swingsList
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("Swings")
                .font(.headline)

            Spacer()

            if !isAnalyzing {
                Button("AUTO-DETECT") { onAutoDetect() }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                    .padding(.trailing, 8)

                Button("MANUAL") { onManualAdd() }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var analysisProgressView: some View {
        VStack(spacing: 12) {
            ProgressView(value: Double(analysisProgress))
                .progressViewStyle(.linear)

            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text(analysisStatus.isEmpty ? "Analyzing swing..." : analysisStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("\(Int(analysisProgress * 100))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var emptySwingsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("No swings detected")
                .font(.headline)

            Text("Tap AUTO-DETECT to analyze the video, or add markers manually.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if video.hasBeenAnalyzed {
                Text("Previously analyzed - no swing found")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var swingsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(video.swings.enumerated()), id: \.element.id) { (item: (offset: Int, element: SwingMarker)) in
                    swingRow(swing: item.element, index: item.offset)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func swingRow(swing: SwingMarker, index: Int) -> some View {
        VStack(spacing: 0) {
            SwingRowView(
                swing: swing,
                index: index,
                isSelected: selectedSwingId == swing.id,
                onTap: { onSwingTap(swing) },
                onEdit: { onSwingEdit(swing) }
            )

            if swing.isAutoDetected {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .font(.caption2)
                    Text("Auto-detected \u{2022} \(swing.confidenceDescription) confidence")
                        .font(.caption2)
                }
                .foregroundStyle(swing.detectionConfidence >= 0.7 ? .green : .orange)
                .padding(.top, 4)
            }
        }
    }
}
