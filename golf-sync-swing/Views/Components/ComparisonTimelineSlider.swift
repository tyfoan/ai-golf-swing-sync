//
//  ComparisonTimelineSlider.swift
//  golf-sync-swing
//
//  Dark-themed timeline scrubber for the comparison view.
//

import SwiftUI

struct ComparisonTimelineSlider: View {
    @Bindable var viewModel: ComparisonViewModel
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 4) {
            trackView
            timeLabels
        }
    }

    // MARK: - Track

    private var trackView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                trackBackground
                trackProgress(width: geometry.size.width)
                handle(containerWidth: geometry.size.width)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(dragGesture(containerWidth: geometry.size.width))
        }
        .frame(height: 20)
    }

    private var trackBackground: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.2))
            .frame(height: 4)
    }

    private func trackProgress(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.appTeal)
            .frame(width: width * viewModel.progress, height: 4)
    }

    private func handle(containerWidth: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: isDragging ? 14 : 10, height: isDragging ? 14 : 10)
            .shadow(radius: 2)
            .offset(x: containerWidth * viewModel.progress - (isDragging ? 7 : 5))
    }

    private func dragGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                let progress = max(0, min(1, value.location.x / containerWidth))
                viewModel.seekToProgress(progress)
            }
            .onEnded { _ in isDragging = false }
    }

    // MARK: - Time Labels

    private var timeLabels: some View {
        HStack {
            Text(formatTime(viewModel.currentTime))
            Spacer()
            Text(formatTime(viewModel.totalDuration))
        }
        .font(.caption2).monospacedDigit()
        .foregroundStyle(.white.opacity(isDragging ? 0.5 : 0.3))
        .animation(.easeInOut(duration: 0.2), value: isDragging)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let hundredths = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
    }
}
