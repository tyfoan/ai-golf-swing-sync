//
//  RecordingTopBar.swift
//  golf-sync-swing
//
//  Top bar for recording view showing cancel, timer, and swing count.
//

import SwiftUI

struct RecordingTopBar: View {
    let state: RecordingState
    let isRecording: Bool
    let isCountingDown: Bool
    let swingCount: Int
    let recordedDuration: TimeInterval
    let onCancel: () -> Void

    var body: some View {
        HStack {
            if isRecording || isCountingDown {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.green)
                        .clipShape(Circle())
                }
            }

            Spacer()

            if isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)

                    Text(formatDuration(recordedDuration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }

            Spacer()

            if swingCount > 0 {
                Text("\(swingCount)")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.green)
                    .clipShape(Circle())
            }
        }
        .padding()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration - Double(Int(duration))) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}
