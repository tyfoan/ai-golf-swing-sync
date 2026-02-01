//
//  SwingPlaybackManager.swift
//  golf-sync-swing
//
//  Manages swing replay and PiP display during recording
//

import Foundation

// PipDisplayMode and SwingClip are defined in RecordingTypes.swift

/// Manages swing playback state during recording
@MainActor
@Observable
final class SwingPlaybackManager {

    // MARK: - State

    /// All detected swings
    private(set) var detectedSwings: [SwingClip] = []

    /// What the main view shows (live camera or swing replay)
    var mainViewShowsReplay: Bool = false

    /// Index of swing currently being replayed in main view (nil = show live camera)
    var replayingSwingIndex: Int? = nil

    /// What the PiP shows when main view shows replay
    var pipDisplayMode: PipDisplayMode = .liveCamera

    /// Playback speed for replay
    var playbackSpeed: Float = 1.0

    // MARK: - Computed Properties

    var swingCount: Int {
        detectedSwings.count
    }

    /// The swing currently being shown in main view replay
    var currentReplaySwing: SwingClip? {
        guard let index = replayingSwingIndex,
              detectedSwings.indices.contains(index) else {
            return nil
        }
        return detectedSwings[index]
    }

    /// The last detected swing (for PiP replay)
    var lastDetectedSwing: SwingClip? {
        detectedSwings.last
    }

    // MARK: - Swing Management

    /// Add a new detected swing
    func addSwing(_ bounds: SwingBounds) {
        let clip = SwingClip(from: bounds)
        detectedSwings.append(clip)

        // Immediately switch to replay mode
        replayingSwingIndex = detectedSwings.count - 1
        mainViewShowsReplay = true
        pipDisplayMode = .liveCamera
    }

    /// Toggle favorite status for a swing
    func toggleFavorite(at index: Int) {
        guard detectedSwings.indices.contains(index) else { return }
        detectedSwings[index].isFavorite.toggle()
    }

    /// Clear all swings
    func clearSwings() {
        detectedSwings.removeAll()
        replayingSwingIndex = nil
        mainViewShowsReplay = false
        pipDisplayMode = .liveCamera
    }

    // MARK: - View Switching

    /// Toggle PiP between live camera and last swing replay
    func togglePipDisplay() {
        switch pipDisplayMode {
        case .liveCamera:
            if lastDetectedSwing != nil {
                pipDisplayMode = .lastSwingReplay
            }
        case .lastSwingReplay:
            // Only allow camera in PiP if main shows replay
            if mainViewShowsReplay {
                pipDisplayMode = .liveCamera
            }
        }
    }

    /// Swap main view and PiP content
    func swapMainAndPip() {
        if mainViewShowsReplay {
            // Main shows replay, swap to show live camera in main
            mainViewShowsReplay = false
            // PiP MUST show replay (not camera) to avoid two camera previews
            if lastDetectedSwing != nil {
                pipDisplayMode = .lastSwingReplay
            }
        } else {
            // Main shows live camera, swap to show replay if available
            if let lastIndex = detectedSwings.indices.last {
                replayingSwingIndex = lastIndex
                mainViewShowsReplay = true
                // Now PiP can safely show camera (main shows replay)
                pipDisplayMode = .liveCamera
            }
        }
    }

    /// Show specific swing in main view
    func showSwing(at index: Int) {
        guard detectedSwings.indices.contains(index) else { return }
        replayingSwingIndex = index
        mainViewShowsReplay = true
        // PiP shows camera when main shows replay
        pipDisplayMode = .liveCamera
    }

    /// Return to live camera in main view
    func showLiveCamera() {
        mainViewShowsReplay = false
        replayingSwingIndex = nil
        // PiP MUST show replay (not camera) to avoid two camera previews
        if lastDetectedSwing != nil {
            pipDisplayMode = .lastSwingReplay
        }
    }

    /// Reset all state
    func reset() {
        clearSwings()
        playbackSpeed = 1.0
    }
}
