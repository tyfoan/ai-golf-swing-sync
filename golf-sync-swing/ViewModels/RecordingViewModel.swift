//
//  RecordingViewModel.swift
//  golf-sync-swing
//
//  State machine for recording workflow
//  Optimized for fast swing detection with background processing
//

import SwiftUI
import AVFoundation
import SwiftData

/// Recording workflow states
enum RecordingState: Equatable {
    case idle
    case countdown(remaining: Int)
    case recording
    case showingReplay(swingIndex: Int)
    case saving
    case reviewing

    static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.countdown(let a), .countdown(let b)): return a == b
        case (.recording, .recording): return true
        case (.showingReplay(let a), .showingReplay(let b)): return a == b
        case (.saving, .saving): return true
        case (.reviewing, .reviewing): return true
        default: return false
        }
    }
}

/// Detected swing clip during recording
struct SwingClip: Identifiable {
    let id: UUID
    let startTime: TimeInterval
    let impactTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    var isFavorite: Bool = false

    init(from bounds: SwingBounds) {
        self.id = bounds.id
        self.startTime = bounds.startTime
        self.impactTime = bounds.impactTime
        self.endTime = bounds.endTime
        self.confidence = bounds.confidence
    }
}

@MainActor
@Observable
final class RecordingViewModel {

    // MARK: - State

    var state: RecordingState = .idle
    var currentPose: BodyPose?
    var detectedSwings: [SwingClip] = []
    var recordingURL: URL?

    // MARK: - UI State

    var showPoseOverlay = true
    var playbackSpeed: Float = 1.0
    var showSaveConfirmation = false
    var errorMessage: String?

    // MARK: - Services

    let cameraService = CameraService()
    private let poseDetector = LivePoseDetector(processEveryNthFrame: 2)
    private let swingDetector = LiveSwingDetector()

    // MARK: - Background Processing

    /// Dedicated queue for pose detection (avoid main thread blocking)
    private let poseProcessingQueue = DispatchQueue(
        label: "com.golfsync.pose.processing",
        qos: .userInteractive
    )

    // MARK: - Recording Timing

    /// Timestamp of first frame when recording started (for calculating file-relative times)
    private var recordingStartTimestamp: TimeInterval?

    /// Flag to track if we're currently recording (thread-safe access)
    private var isCurrentlyRecording: Bool = false

    // MARK: - Computed Properties

    var isCountingDown: Bool {
        if case .countdown = state { return true }
        return false
    }

    var countdownValue: Int {
        if case .countdown(let v) = state { return v }
        return 0
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        if case .showingReplay = state { return true } // Still recording during replay
        return false
    }

    var isShowingReplay: Bool {
        if case .showingReplay = state { return true }
        return false
    }

    var currentReplaySwing: SwingClip? {
        if case .showingReplay(let index) = state {
            return detectedSwings.indices.contains(index) ? detectedSwings[index] : nil
        }
        return nil
    }

    var isReviewing: Bool {
        if case .reviewing = state { return true }
        return false
    }

    var isSaving: Bool {
        if case .saving = state { return true }
        return false
    }

    var swingCount: Int {
        detectedSwings.count
    }

    var isFrontCamera: Bool {
        cameraService.currentCameraPosition == .front
    }

    // MARK: - Init

    init() {
        setupCallbacks()
    }

    private func setupCallbacks() {
        // Frame processing callback - process on background queue for speed
        cameraService.onFrameCaptured = { [weak self] pixelBuffer, timestamp in
            guard let self else { return }

            // Process on background queue to avoid blocking camera
            self.poseProcessingQueue.async {
                self.processFrameOnBackground(pixelBuffer, timestamp: timestamp)
            }
        }

        // Recording finished callback
        cameraService.onRecordingFinished = { [weak self] url, error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }

        // Swing detection callback - fires immediately on detection
        swingDetector.onSwingDetected = { [weak self] bounds in
            Task { @MainActor [weak self] in
                self?.handleSwingDetected(bounds)
            }
        }
    }

    // MARK: - Frame Processing (Background Thread)

    /// Process frame on background queue for minimal latency
    private func processFrameOnBackground(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        // Only process during recording
        guard isCurrentlyRecording else { return }

        let frameTime = timestamp.seconds

        // Capture first frame timestamp for file-relative timing
        if recordingStartTimestamp == nil {
            recordingStartTimestamp = frameTime
        }

        // Calculate file-relative timestamp
        let relativeTime = frameTime - (recordingStartTimestamp ?? 0)

        // Update adaptive processing based on swing tracking state
        poseDetector.setActiveTracking(swingDetector.isTrackingSwing)

        // Detect pose (this is the heavy computation)
        guard let pose = poseDetector.detectPose(in: pixelBuffer, at: timestamp) else {
            return
        }

        // Feed BOTH wrist positions to swing detector for smart wrist selection
        let leftWristY = pose.leftWristPosition.map { Double($0.y) }
        let rightWristY = pose.rightWristPosition.map { Double($0.y) }

        swingDetector.addPose(
            timestamp: relativeTime,
            leftWristY: leftWristY,
            rightWristY: rightWristY
        )

        // Update UI on main thread (only pose display, not detection logic)
        DispatchQueue.main.async { [weak self] in
            self?.currentPose = pose
        }
    }

    // MARK: - Swing Detection

    private func handleSwingDetected(_ bounds: SwingBounds) {
        let clip = SwingClip(from: bounds)
        detectedSwings.append(clip)

        // Show replay (recording continues in background)
        state = .showingReplay(swingIndex: detectedSwings.count - 1)

        // Auto-dismiss replay after 3 seconds
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                if case .showingReplay = self.state {
                    self.state = .recording
                }
            }
        }
    }

    // MARK: - Actions

    func startRecording() {
        guard state == .idle else { return }

        // Start countdown
        state = .countdown(remaining: 5)

        Task {
            // Setup FRONT camera for countdown (user sees themselves to position)
            cameraService.setupSession(position: .front, frameRate: 30)
            cameraService.startSession()

            // Run countdown
            for i in stride(from: 5, through: 1, by: -1) {
                state = .countdown(remaining: i)
                try? await Task.sleep(for: .seconds(1))

                // Check if cancelled
                if state == .idle { return }
            }

            // Use FRONT camera for recording at 30fps for better quality
            cameraService.setupSession(position: .front, frameRate: 30)

            // Small delay for camera to initialize
            try? await Task.sleep(for: .milliseconds(300))

            // Start actual recording
            beginRecording()
        }
    }

    private func beginRecording() {
        recordingStartTimestamp = nil // Will be set on first frame
        isCurrentlyRecording = true
        recordingURL = cameraService.startRecording()
        detectedSwings.removeAll()
        swingDetector.reset()
        state = .recording
    }

    func stopRecording() {
        guard isRecording else { return }

        isCurrentlyRecording = false
        cameraService.stopRecording()

        // Always show save confirmation dialog
        showSaveConfirmation = true
    }

    func dismissReplay() {
        if case .showingReplay = state {
            state = .recording
        }
    }

    func cancel() {
        isCurrentlyRecording = false
        cameraService.stopRecording()
        cameraService.stopSession()
        recordingURL = nil
        recordingStartTimestamp = nil
        detectedSwings.removeAll()
        currentPose = nil
        state = .idle
    }

    func togglePoseOverlay() {
        showPoseOverlay.toggle()
    }

    func toggleFavorite(at index: Int) {
        guard detectedSwings.indices.contains(index) else { return }
        detectedSwings[index].isFavorite.toggle()
    }

    // MARK: - Save Recording

    func saveRecording(to modelContext: ModelContext) async -> SwingVideo? {
        guard let sourceURL = recordingURL else { return nil }

        state = .saving

        do {
            // Copy to permanent storage
            let permanentURL = try VideoStorageService.shared.copyVideoToStorage(from: sourceURL)

            // Create SwingVideo
            let video = await VideoStorageService.shared.createSwingVideo(from: permanentURL)

            // Add swing markers
            for clip in detectedSwings {
                let marker = SwingMarker(
                    startTime: clip.startTime,
                    contactTime: clip.impactTime,
                    endTime: clip.endTime
                )
                marker.isAutoDetected = true
                marker.detectionConfidence = clip.confidence
                marker.video = video
                video.swings.append(marker)
            }

            // Save to SwiftData
            modelContext.insert(video)

            // Cleanup temp file
            try? FileManager.default.removeItem(at: sourceURL)

            state = .idle
            recordingURL = nil
            detectedSwings.removeAll()

            return video

        } catch {
            errorMessage = error.localizedDescription
            state = .reviewing
            return nil
        }
    }

    func deleteRecording() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        recordingStartTimestamp = nil
        detectedSwings.removeAll()
        state = .idle
    }

    func enterReviewMode() {
        showSaveConfirmation = false
        state = .reviewing
    }

    // MARK: - Cleanup

    func cleanup() {
        isCurrentlyRecording = false
        cameraService.stopSession()
        currentPose = nil
        poseDetector.reset()
        swingDetector.reset()
    }
}
