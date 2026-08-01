//
//  RecordingTypes.swift
//  golf-sync-swing
//
//  Shared types for recording workflow
//

import Foundation

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case countdown(remaining: Int)
    case recording
    case finalizingVideo
    case saving
    case saved
    case reviewing

    static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording),
             (.finalizingVideo, .finalizingVideo),
             (.saving, .saving), (.saved, .saved), (.reviewing, .reviewing): return true
        case (.countdown(let a), .countdown(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Save Outcome

/// Captured after `saveRecording()` completes so the post-save hand-off knows
/// which recording to point the user at and how many swings to summarise.
struct SaveOutcome: Equatable {
    let videoID: UUID
    let swingCount: Int
}

// MARK: - Swing Replay

/// One detected swing, ready to draw: the frames `SwingFrameBuffer` yielded for its range,
/// and the number the top bar's swing badge is counting.
///
/// Frames, never a video. The recording file cannot be opened while it is being written —
/// `AVURLAsset` on the in-progress .mov makes iOS terminate the capture — and a second
/// `AVCaptureVideoPreviewLayer` cannot be attached to the running session either.
struct SwingReplay: Identifiable {
    /// The `SwingClip`'s own id, so a newer swing replaces an older one by identity.
    let id: UUID

    /// 1-based, matching the counter in `RecordingTopBar`.
    let number: Int

    /// Oldest first. EMPTY exactly while `loading` is set: a swing is published the moment it is
    /// detected, before the tail of its own clip has been captured and encoded, so that the
    /// screen can say so instead of showing nothing for a second.
    let frames: [Data]

    /// The wait, while there is one. Nil once the frames are here and the replay can play.
    let loading: Loading?

    /// Defaulted so a playable replay reads exactly as it did before there was a loading state.
    init(id: UUID, number: Int, frames: [Data], loading: Loading? = nil) {
        self.id = id
        self.number = number
        self.frames = frames
        self.loading = loading
    }

    /// The wait a detected swing is still inside, described well enough to draw a progress bar
    /// that is telling the truth.
    ///
    /// It is a REAL wait and not a contrivance: a clip runs to `impact + 1.0` while detection
    /// reports the swing a few frames after impact, so the last second of the swing has not
    /// happened yet when the golfer is told it was detected. `RecordingViewModel.loadReplay`
    /// has always slept it out. This is that sleep, made visible.
    struct Loading: Equatable {
        /// `ProcessInfo.systemUptime` when the wait began — monotonic, and the same clock the
        /// capture path's timings are taken on. An instant rather than a fraction so a surface
        /// mounted PART WAY through the wait (the tile and the full screen trade places on a tap)
        /// resumes the bar where the wait actually is instead of restarting it.
        let startedAt: TimeInterval

        /// How long the wait is expected to take, in seconds, and therefore how long the bar has
        /// to fill. The replay normally arrives EARLIER than this — the view model presents it the
        /// moment the frames are ready — and that asymmetry is deliberate: a bar that has not
        /// finished when the picture arrives is honest, a bar that finished first is a lie.
        let duration: TimeInterval

        var elapsed: TimeInterval { max(0, ProcessInfo.processInfo.systemUptime - startedAt) }

        var remaining: TimeInterval { max(0, duration - elapsed) }

        /// 0…1. A non-positive duration reads as finished rather than as division by zero.
        var fraction: Double {
            guard duration > 0 else { return 1 }
            return min(1, elapsed / duration)
        }
    }
}

// MARK: - Swing Clip

/// Detected swing clip during recording
struct SwingClip: Identifiable, Equatable {
    let id: UUID
    let startTime: TimeInterval
    let impactTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let detectionTime: TimeInterval
    let audioConfirmed: Bool
    var isFavorite: Bool = false

    init(id: UUID = UUID(), startTime: TimeInterval, impactTime: TimeInterval, endTime: TimeInterval, confidence: Double, detectionTime: TimeInterval, audioConfirmed: Bool = false, isFavorite: Bool = false) {
        self.id = id
        self.startTime = startTime
        self.impactTime = impactTime
        self.endTime = endTime
        self.confidence = confidence
        self.detectionTime = detectionTime
        self.audioConfirmed = audioConfirmed
        self.isFavorite = isFavorite
    }

}
