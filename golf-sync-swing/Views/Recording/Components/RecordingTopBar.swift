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
    let swingCount: Int
    let recordedDuration: TimeInterval
    let onCancel: () -> Void

    /// Abandons the take in progress. Every state that accepts input and holds something to
    /// abandon needs it — without it, recovery states like `.reviewing` after a failed save
    /// stranded the user. `.idle` is deliberately excluded now that the capture UI lives on
    /// the Camera tab: there is nothing to cancel on the ready screen and nowhere to dismiss
    /// to. The blocking finalize/save overlays (and `.saved`, which navigates away) go
    /// without because their work must not be interrupted half-done.
    private var showsCancel: Bool {
        switch state {
        case .countdown, .recording, .reviewing: return true
        case .idle, .finalizingVideo, .saving, .saved: return false
        }
    }

    var body: some View {
        HStack {
            if showsCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.fairwayGreen)
                        .clipShape(Circle())
                }
            }

            Spacer()

            if isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.flagRed)
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

            if swingCount > 0 && isRecording {
                Text("\(swingCount)")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.fairwayGreen)
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
