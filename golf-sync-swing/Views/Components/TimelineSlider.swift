//
//  TimelineSlider.swift
//  golf-sync-swing
//

import SwiftUI

struct TimelineSlider: View {
    @Bindable var viewModel: VideoPlayerViewModel
    var swings: [SwingMarker] = []
    var onSwingTap: ((SwingMarker) -> Void)?
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 4)

                    // Swing markers on timeline
                    ForEach(Array(swings.enumerated()), id: \.element.id) { index, swing in
                        swingMarker(swing: swing, index: index, width: geometry.size.width)
                    }

                    // Progress fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * viewModel.progress, height: 4)

                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 16 : 12, height: isDragging ? 16 : 12)
                        .shadow(radius: 2)
                        .offset(x: geometry.size.width * viewModel.progress - (isDragging ? 8 : 6))
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            viewModel.seekToProgress(progress)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
            .frame(height: 20)

            // Time labels
            HStack {
                Text(formatTime(viewModel.currentTime))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formatTime(viewModel.duration))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func swingMarker(swing: SwingMarker, index: Int, width: CGFloat) -> some View {
        let duration = viewModel.duration
        if duration > 0 {
            let startX = (swing.startTime / duration) * width
            let endX = (swing.endTime / duration) * width
            let markerWidth = max(4, endX - startX)
            let impactX = (swing.contactTime / duration) * width

            ZStack {
                // Swing range highlight
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green.opacity(0.3))
                    .frame(width: markerWidth, height: 12)
                    .offset(x: startX + markerWidth / 2 - width / 2)

                // Impact point marker (orange)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .offset(x: impactX - width / 2)
            }
            .onTapGesture {
                onSwingTap?(swing)
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let hundredths = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
    }
}
