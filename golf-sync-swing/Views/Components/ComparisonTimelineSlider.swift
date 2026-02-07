//
//  ComparisonTimelineSlider.swift
//  golf-sync-swing
//
//  Timeline scrubber for the comparison view.
//

import SwiftUI

struct ComparisonTimelineSlider: View {
    @Bindable var viewModel: ComparisonViewModel
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * viewModel.progress, height: 4)

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
                        .onEnded { _ in isDragging = false }
                )
            }
            .frame(height: 20)

            HStack {
                Text(formatTime(viewModel.currentTime))
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(viewModel.totalDuration))
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
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
