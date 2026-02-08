//
//  SwingMarkerSlider.swift
//  golf-sync-swing
//

import SwiftUI

struct SwingMarkerSlider: View {
    @Binding var startTime: TimeInterval
    @Binding var contactTime: TimeInterval
    @Binding var endTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var draggingHandle: DraggingHandle?

    private enum DraggingHandle {
        case start, contact, end
    }

    private let handleSize: CGFloat = 24
    private let trackHeight: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - handleSize

            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: trackHeight)
                    .padding(.horizontal, handleSize / 2)

                // Active range (between start and end)
                let startX = (startTime / duration) * width
                let endX = (endTime / duration) * width
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(Color.mintMist)
                    .frame(width: endX - startX, height: trackHeight)
                    .offset(x: startX + handleSize / 2)

                // Start handle (green)
                handleView(color: .fairwayGreen, position: startTime / duration * width)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                draggingHandle = .start
                                let newTime = clampTime(value.location.x / width * duration, min: 0, max: contactTime - 0.1)
                                startTime = newTime
                                onSeek(newTime)
                            }
                            .onEnded { _ in draggingHandle = nil }
                    )

                // Contact handle (red/orange)
                handleView(color: .sand, position: contactTime / duration * width)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                draggingHandle = .contact
                                let newTime = clampTime(value.location.x / width * duration, min: startTime + 0.1, max: endTime - 0.1)
                                contactTime = newTime
                                onSeek(newTime)
                            }
                            .onEnded { _ in draggingHandle = nil }
                    )

                // End handle (green)
                handleView(color: .fairwayGreen, position: endTime / duration * width)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                draggingHandle = .end
                                let newTime = clampTime(value.location.x / width * duration, min: contactTime + 0.1, max: duration)
                                endTime = newTime
                                onSeek(newTime)
                            }
                            .onEnded { _ in draggingHandle = nil }
                    )
            }
        }
        .frame(height: handleSize + 8)
    }

    private func handleView(color: Color, position: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: 8, height: handleSize)
            .shadow(radius: 2)
            .offset(x: position + handleSize / 2 - 4)
    }

    private func clampTime(_ time: TimeInterval, min: TimeInterval, max: TimeInterval) -> TimeInterval {
        Swift.max(min, Swift.min(max, time))
    }
}
