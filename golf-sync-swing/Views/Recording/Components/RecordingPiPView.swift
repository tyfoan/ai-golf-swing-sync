//
//  RecordingPiPView.swift
//  golf-sync-swing
//
//  Picture-in-picture overlay during recording showing alternate view
//  (live camera or last swing replay).
//

import SwiftUI

struct RecordingPiPView: View {
    let pipDisplayMode: PipDisplayMode
    let sessionConfigurationId: Int
    let captureSession: AVCaptureSession
    let lastSwing: SwingClip?
    let recordingURL: URL?
    let playbackSpeed: Float
    let onTap: () -> Void

    private let cornerRadius: CGFloat = 12

    var body: some View {
        VStack {
            HStack {
                Spacer()

                ZStack(alignment: .topLeading) {
                    content
                        .frame(width: 120, height: 160)

                    badge
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(pipDisplayMode == .lastSwingReplay ? Color.sand : Color.fairwayGreen, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                .onTapGesture(perform: onTap)
            }
            .padding()

            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        if pipDisplayMode == .liveCamera {
            CameraPreviewView(session: captureSession)
                .id("pip-camera-\(sessionConfigurationId)")
        } else if let swing = lastSwing, let url = recordingURL {
            SwingReplayView(videoURL: url, startTime: swing.startTime, endTime: swing.endTime, playbackSpeed: playbackSpeed)
        }
    }

    private var badge: some View {
        HStack(spacing: 4) {
            if pipDisplayMode == .liveCamera {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("REC").font(.caption2.bold()).foregroundStyle(.white)
            } else {
                Image(systemName: "arrow.counterclockwise").font(.caption2.bold()).foregroundStyle(.white)
                Text("REPLAY").font(.caption2.bold()).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
    }
}

import AVFoundation
