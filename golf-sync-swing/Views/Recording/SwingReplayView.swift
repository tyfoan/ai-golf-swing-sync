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
    var playbackSpeed: Float = 1.0
    var onLoaded: (() -> Void)?

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var retryCount = 0
    @State private var isPlaying = true
    @State private var isMuted = true
    @State private var loopObserver: NSObjectProtocol?

    /// Maximum retries if video isn't ready
    private let maxRetries = 5
    /// Delay between retries
    private let retryDelay: UInt64 = 300_000_000 // 300ms in nanoseconds

    private var clipDuration: TimeInterval {
        endTime - startTime
    }

    var body: some View {
        ZStack {
            Color.black

            if let player {
                VideoPlayer(player: player)
                    .disabled(true) // No native controls
                    .onAppear {
                        player.isMuted = isMuted
                        player.rate = playbackSpeed
                        setupLooping()
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

            // Floating replay controls
            if player != nil {
                VStack {
                    Spacer()
                    replayControls
                        .padding(.bottom, 12)
                }
            }
            // Note: Replay badge is shown by parent RecordingView
        }
        .task {
            await loadVideo()
        }
        .onDisappear {
            if let observer = loopObserver {
                NotificationCenter.default.removeObserver(observer)
                loopObserver = nil
            }
            player?.pause()
            player = nil
        }
    }

    // MARK: - Replay Controls

    private var replayControls: some View {
        HStack(spacing: 16) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            Button {
                isMuted.toggle()
                player?.isMuted = isMuted
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.rate = playbackSpeed
        }
        isPlaying.toggle()
    }

    // MARK: - Video Loading

    private func loadVideo() async {
        // Small initial delay
        try? await Task.sleep(for: .milliseconds(100))

        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            loadError = "Video file not found"
            isLoading = false
            onLoaded?()
            return
        }

        // Create a fresh asset each attempt (don't cache stale duration)
        let asset = AVURLAsset(url: videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        do {
            // Check if asset is playable
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                // Retry if not playable yet
                if retryCount < maxRetries {
                    retryCount += 1
                    try? await Task.sleep(nanoseconds: retryDelay)
                    await loadVideo()
                    return
                }
                loadError = "Video not ready yet"
                isLoading = false
                onLoaded?()
                return
            }

            let duration = try await asset.load(.duration)
            let videoDuration = CMTimeGetSeconds(duration)

            // Check if video has enough content for the full swing
            // If not, retry to let more frames be written
            if videoDuration < endTime && retryCount < maxRetries {
                retryCount += 1
                try? await Task.sleep(nanoseconds: retryDelay)
                await loadVideo()
                return
            }

            // Validate times - use actual video duration
            let safeStartTime = max(0, min(startTime, videoDuration - 0.1))
            let safeEndTime = max(safeStartTime + 0.5, min(endTime, videoDuration))

            // Create player item
            let playerItem = AVPlayerItem(asset: asset)

            // Set up time range
            playerItem.forwardPlaybackEndTime = CMTime(seconds: safeEndTime, preferredTimescale: 600)

            await MainActor.run {
                let avPlayer = AVPlayer(playerItem: playerItem)
                avPlayer.seek(to: CMTime(seconds: safeStartTime, preferredTimescale: 600))
                self.player = avPlayer
                self.isLoading = false
                self.onLoaded?()
            }
        } catch {
            // Retry on error
            if retryCount < maxRetries {
                retryCount += 1
                try? await Task.sleep(nanoseconds: retryDelay)
                await loadVideo()
                return
            }
            await MainActor.run {
                loadError = "Loading: \(error.localizedDescription)"
                isLoading = false
                onLoaded?()
            }
        }
    }

    private func setupLooping() {
        guard let player else { return }

        let loopStart = startTime
        let speed = playbackSpeed

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            let seekTime = CMTime(seconds: loopStart, preferredTimescale: 600)
            player?.seek(to: seekTime) { _ in
                player?.rate = speed
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
