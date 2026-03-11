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
    var showControls: Bool = true
    var onLoaded: (() -> Void)?

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var retryCount = 0
    @State private var isPlaying = true
    @State private var isMuted = true
    @State private var loopObserver: Any?
    @State private var safeStartTime: TimeInterval = 0
    @State private var safeEndTime: TimeInterval = 0

    /// Maximum retries if video isn't ready
    private let maxRetries = 5
    /// Delay between retries
    private let retryDelay: UInt64 = 150_000_000 // 150ms in nanoseconds

    private var clipDuration: TimeInterval {
        endTime - startTime
    }

    var body: some View {
        ZStack {
            Color.black

            if let player {
                VideoPlayer(player: player)
                    .disabled(true) // No native controls
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

            // Floating replay controls (hidden in PiP mode)
            if player != nil && showControls {
                VStack {
                    Spacer()
                    replayControls
                        .padding(.bottom, 12)
                }
            }
        }
        .task {
            await loadVideo()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .onChange(of: playbackSpeed) { _, newSpeed in
            player?.rate = newSpeed
            setupLooping()
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
                    guard !Task.isCancelled else { return }
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
                guard !Task.isCancelled else { return }
                retryCount += 1
                try? await Task.sleep(nanoseconds: retryDelay)
                await loadVideo()
                return
            }

            // Validate times - clamp to actual video duration
            let clampedStart = max(0, min(startTime, videoDuration - 0.1))
            let clampedEnd = max(clampedStart + 0.5, min(endTime, videoDuration))

            // Create player item
            let playerItem = AVPlayerItem(asset: asset)

            // Note: Do NOT use forwardPlaybackEndTime — it silently pauses
            // without firing AVPlayerItemDidPlayToEndTime. Looping is handled
            // by a boundary time observer in setupLooping().

            await MainActor.run {
                cleanupPlayer()
                self.safeStartTime = clampedStart
                self.safeEndTime = clampedEnd
                let avPlayer = AVPlayer(playerItem: playerItem)
                avPlayer.isMuted = isMuted
                avPlayer.seek(to: CMTime(seconds: clampedStart, preferredTimescale: 600)) { _ in
                    avPlayer.rate = self.playbackSpeed
                }
                self.player = avPlayer
                self.isLoading = false
                setupLooping()
                self.onLoaded?()
            }
        } catch {
            // Retry on error
            if retryCount < maxRetries {
                guard !Task.isCancelled else { return }
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

    private func cleanupPlayer() {
        removeLoopObserver()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func setupLooping() {
        guard let player else { return }

        removeLoopObserver()

        let loopStart = CMTime(seconds: safeStartTime, preferredTimescale: 600)
        let loopEnd = CMTime(seconds: safeEndTime, preferredTimescale: 600)
        let speed = playbackSpeed

        loopObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: loopEnd)],
            queue: .main
        ) { [weak player] in
            player?.seek(to: loopStart) { _ in
                player?.rate = speed
            }
        }
    }

    private func removeLoopObserver() {
        guard let observer = loopObserver else { return }
        player?.removeTimeObserver(observer)
        loopObserver = nil
    }
}

#Preview {
    SwingReplayView(
        videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
        startTime: 1.0,
        endTime: 3.5
    )
}
