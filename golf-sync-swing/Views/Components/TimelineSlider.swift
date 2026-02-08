//
//  TimelineSlider.swift
//  golf-sync-swing
//
//  Dark-themed timeline with swing range markers and impact dots.
//

import SwiftUI

struct TimelineSlider: View {
    @Bindable var viewModel: VideoPlayerViewModel
    var swings: [SwingMarker] = []
    var onSwingTap: ((SwingMarker) -> Void)?
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
                swingMarkers(width: geometry.size.width)
                progressFill(width: geometry.size.width)
                handle(width: geometry.size.width)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: geometry.size.width))
        }
        .frame(height: 20)
    }

    private var trackBackground: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.2))
            .frame(height: 4)
    }

    private func progressFill(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.appTeal)
            .frame(width: width * viewModel.progress, height: 4)
    }

    private func handle(width: CGFloat) -> some View {
        let size: CGFloat = isDragging ? 14 : 10
        return Circle()
            .fill(Color.white)
            .frame(width: size, height: size)
            .shadow(radius: 2)
            .offset(x: width * viewModel.progress - size / 2)
    }

    // MARK: - Swing Markers

    @ViewBuilder
    private func swingMarkers(width: CGFloat) -> some View {
        ForEach(Array(swings.enumerated()), id: \.element.id) { index, swing in
            swingMarker(swing: swing, index: index, width: width)
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
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.mintMist)
                    .frame(width: markerWidth, height: 12)
                    .offset(x: startX + markerWidth / 2 - width / 2)

                Circle()
                    .fill(Color.sand)
                    .frame(width: 8, height: 8)
                    .offset(x: impactX - width / 2)
            }
            .frame(width: width)
            .onTapGesture { onSwingTap?(swing) }
        }
    }

    // MARK: - Time Labels

    private var timeLabels: some View {
        HStack {
            Text(formatTime(viewModel.currentTime))
                .font(.caption2).monospacedDigit()
                .foregroundStyle(.white.opacity(isDragging ? 0.5 : 0.3))

            Spacer()

            Text(formatTime(viewModel.duration))
                .font(.caption2).monospacedDigit()
                .foregroundStyle(.white.opacity(isDragging ? 0.5 : 0.3))
        }
    }

    // MARK: - Gesture

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                let progress = max(0, min(1, value.location.x / width))
                viewModel.seekToProgress(progress)
            }
            .onEnded { _ in
                isDragging = false
            }
    }

    // MARK: - Formatting

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let hundredths = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
    }
}
