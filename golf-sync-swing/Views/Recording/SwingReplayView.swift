//
//  SwingReplayView.swift
//  golf-sync-swing
//
//  Plays a swing clip segment in a loop during recording
//

import SwiftUI
import AVKit

struct SwingReplayView: View {
    let videoURL: URL
    let startTime: TimeInterval
    let endTime: TimeInterval

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var loadError: String?

    private var clipDuration: TimeInterval {
        endTime - startTime
    }

    var body: some View {
        ZStack {
            Color.black

            if let player {
                VideoPlayer(player: player)
                    .disabled(true) // No controls
                    .onAppear {
                        setupLooping()
                        player.play()
                    }
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            } else if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding()
            }

            // Replay badge
            VStack {
                HStack {
                    Label("REPLAY", systemImage: "arrow.counterclockwise")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green)
                        .clipShape(Capsule())

                    Spacer()
                }
                .padding()

                Spacer()
            }
        }
        .task {
            await loadVideo()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func loadVideo() async {
        // Small delay to let the video file be written
        try? await Task.sleep(for: .milliseconds(200))

        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            loadError = "Video file not found"
            isLoading = false
            return
        }

        let asset = AVURLAsset(url: videoURL)

        do {
            // Check if asset is playable
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                loadError = "Video not ready yet"
                isLoading = false
                return
            }

            let duration = try await asset.load(.duration)
            let videoDuration = CMTimeGetSeconds(duration)

            // Validate times
            let safeStartTime = max(0, min(startTime, videoDuration - 0.1))
            let safeEndTime = max(safeStartTime + 0.1, min(endTime, videoDuration))

            // Create player item
            let playerItem = AVPlayerItem(asset: asset)

            // Set up time range
            playerItem.forwardPlaybackEndTime = CMTime(seconds: safeEndTime, preferredTimescale: 600)

            await MainActor.run {
                let avPlayer = AVPlayer(playerItem: playerItem)
                avPlayer.seek(to: CMTime(seconds: safeStartTime, preferredTimescale: 600))
                self.player = avPlayer
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = "Loading: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func setupLooping() {
        guard let player else { return }

        // Loop the clip by observing when playback ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            let seekTime = CMTime(seconds: startTime, preferredTimescale: 600)
            player?.seek(to: seekTime) { _ in
                player?.play()
            }
        }
    }
}

#Preview {
    SwingReplayView(
        videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
        startTime: 1.0,
        endTime: 3.5
    )
}
