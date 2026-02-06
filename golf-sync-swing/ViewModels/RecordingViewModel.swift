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

// MARK: - Recording State

/// Recording workflow states
enum RecordingState: Equatable {
    case idle
    case countdown(remaining: Int)
    case recording
    case processingSwing  // Brief loading state while preparing replay
    case finalizingVideo  // Waiting for video file to finish writing
    case saving
    case reviewing

    static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.countdown(let a), .countdown(let b)): return a == b
        case (.recording, .recording): return true
        case (.processingSwing, .processingSwing): return true
        case (.finalizingVideo, .finalizingVideo): return true
        case (.saving, .saving): return true
        case (.reviewing, .reviewing): return true
        default: return false
        }
    }
}

// Note: PipDisplayMode and SwingClip are defined in Models/RecordingTypes.swift

@MainActor
@Observable
final class RecordingViewModel {

    // MARK: - State

    var state: RecordingState = .idle
    var detectedSwings: [SwingClip] = []
    var recordingURL: URL?

    // MARK: - UI State

    var playbackSpeed: Float = 1.0
    var showSaveConfirmation = false
    var errorMessage: String?

    /// What the main view shows (live camera or swing replay)
    var mainViewShowsReplay: Bool = false

    /// Index of swing currently being replayed in main view (nil = show live camera)
    var replayingSwingIndex: Int? = nil

    /// What the PiP shows when main view shows replay
    var pipDisplayMode: PipDisplayMode = .liveCamera

    // MARK: - Services

    let cameraService = CameraService()

    // MARK: - Swing Detectors

    /// Action Classifier — pose-based, works from any camera angle (default for live)
    nonisolated(unsafe) private let actionClassifier = ActionClassifierDetector()

    /// SwingNet — video event detection, best for side-view offline sync
    nonisolated(unsafe) private let swingNetDetector = SwingNetDetector()

    /// The active detector used for live recording (Action Classifier by default)
    nonisolated(unsafe) private var activeDetector: any RealTimeSwingDetector

    // MARK: - Background Processing

    /// Dedicated queue for pose detection (avoid main thread blocking)
    nonisolated(unsafe) private let poseProcessingQueue = DispatchQueue(
        label: "com.golfsync.pose.processing",
        qos: .userInteractive
    )

    /// Gate to prevent queuing frames while processing is busy.
    /// Without this, camera delivers frames faster than they process,
    /// captured CVPixelBuffers accumulate in the queue, exhausting the camera buffer pool → OutOfBuffers.
    nonisolated(unsafe) private var _isProcessingFrame = false

    // MARK: - Recording Timing (Thread-Safe)

    /// Lock for thread-safe access to recording state from background threads
    nonisolated(unsafe) private var recordingLock = NSLock()

    /// Timestamp of first frame when recording started (for calculating file-relative times)
    nonisolated(unsafe) private var _recordingStartTimestamp: TimeInterval?

    /// Flag to track if we're currently recording
    nonisolated(unsafe) private var _isCurrentlyRecording: Bool = false

    /// Thread-safe getter/setter for recording flag (can be accessed from any thread)
    nonisolated var isCurrentlyRecording: Bool {
        get {
            recordingLock.lock()
            defer { recordingLock.unlock() }
            return _isCurrentlyRecording
        }
        set {
            recordingLock.lock()
            defer { recordingLock.unlock() }
            _isCurrentlyRecording = newValue
        }
    }

    /// Thread-safe getter/setter for recording start timestamp (can be accessed from any thread)
    nonisolated var recordingStartTimestamp: TimeInterval? {
        get {
            recordingLock.lock()
            defer { recordingLock.unlock() }
            return _recordingStartTimestamp
        }
        set {
            recordingLock.lock()
            defer { recordingLock.unlock() }
            _recordingStartTimestamp = newValue
        }
    }

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
        if case .processingSwing = state { return true } // Still recording during processing
        return false
    }

    var isProcessingSwing: Bool {
        if case .processingSwing = state { return true }
        return false
    }

    var isFinalizingVideo: Bool {
        if case .finalizingVideo = state { return true }
        return false
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
        // Default to Action Classifier (angle-independent)
        activeDetector = actionClassifier

        print("═══════════════════════════════════════════════════════════════")
        print("RecordingViewModel INITIALIZING")
        print("═══════════════════════════════════════════════════════════════")

        setupCallbacks()

        print("RecordingViewModel ready")
        print("   Live detector: Action Classifier (pose-based, any angle)")
        print("   Offline sync:  SwingNet (GolfDB)")
        print("═══════════════════════════════════════════════════════════════")
    }

    private func setupCallbacks() {
        // Frame processing callback - process on background queue for speed
        cameraService.onFrameCaptured = { [weak self] pixelBuffer, timestamp in
            guard let self else { return }

            // Log first few frames to confirm callback is working
            if timestamp.seconds < 2.0 && Int(timestamp.seconds * 10) % 5 == 0 {
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                print("📷 Frame: t=\(String(format: "%.2f", timestamp.seconds))s, \(width)x\(height), recording=\(self.isCurrentlyRecording)")
            }

            // Gate: drop frame if processing queue is busy.
            // This prevents camera pixel buffers from accumulating in the queue
            // (which exhausts the buffer pool → OutOfBuffers → temporal distortion).
            guard !self._isProcessingFrame else { return }
            self._isProcessingFrame = true

            self.poseProcessingQueue.async {
                defer { self._isProcessingFrame = false }
                self.processFrameOnBackground(pixelBuffer, timestamp: timestamp)
            }
        }

        // Recording finished callback - video file is now fully written
        cameraService.onRecordingFinished = { [weak self] url, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    self.errorMessage = error.localizedDescription
                    self.state = .idle
                } else {
                    // Video file is now complete - transition to reviewing and show save dialog
                    self.state = .reviewing
                    self.showSaveConfirmation = true
                }
            }
        }

        // Setup swing detector callbacks
        setupSwingDetectorCallbacks()
    }

    private func setupSwingDetectorCallbacks() {
        // Action Classifier callbacks (default live detector)
        actionClassifier.onSwingDetected = { [weak self] bounds in
            Task { @MainActor [weak self] in
                self?.handleSwingDetected(bounds)
            }
        }
        actionClassifier.onPhaseChanged = { phase, confidence in
            print("ActionClassifier Phase: \(phase) (\(Int(confidence * 100))%)")
        }

        // SwingNet callbacks (available as alternative / offline)
        swingNetDetector.onSwingDetected = { [weak self] bounds in
            Task { @MainActor [weak self] in
                self?.handleSwingDetected(bounds)
            }
        }
        swingNetDetector.onPhaseChanged = { phase, confidence in
            print("SwingNet Phase: \(phase) (\(Int(confidence * 100))%)")
        }
    }

    // MARK: - Frame Processing (Background Thread)

    /// Track frames processed for logging
    nonisolated(unsafe) private var _frameProcessedCount: Int = 0

    /// Process frame on background queue for minimal latency
    /// This method is nonisolated because it runs on a background queue for performance
    nonisolated private func processFrameOnBackground(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        // Only process during recording
        guard isCurrentlyRecording else { return }

        let frameTime = timestamp.seconds

        // Capture first frame timestamp for file-relative timing
        if recordingStartTimestamp == nil {
            recordingStartTimestamp = frameTime
            print("📹 RecordingVM: First frame at \(frameTime)s")
        }

        // Calculate file-relative timestamp
        let relativeTime = frameTime - (recordingStartTimestamp ?? 0)

        // Log frame processing periodically
        _frameProcessedCount += 1
        if _frameProcessedCount % 60 == 0 {
            print("📹 RecordingVM: Processed \(_frameProcessedCount) frames, t=\(String(format: "%.2f", relativeTime))s")
        }

        // Route to active detector
        activeDetector.processFrame(pixelBuffer, at: relativeTime)
    }

    // MARK: - Swing Detection

    private func handleSwingDetected(_ bounds: SwingBounds) {
        print("🎯 RecordingVM: handleSwingDetected called!")
        print("   - startTime: \(String(format: "%.2f", bounds.startTime))s")
        print("   - impactTime: \(String(format: "%.2f", bounds.impactTime))s")
        print("   - endTime: \(String(format: "%.2f", bounds.endTime))s")
        print("   - confidence: \(Int(bounds.confidence * 100))%")

        // Create clip and add to list
        let clip = SwingClip(from: bounds)
        detectedSwings.append(clip)

        print("🎯 RecordingVM: Total swings detected: \(detectedSwings.count)")

        // Keep camera as main view — show detected swing in PiP (smooth, non-jarring)
        replayingSwingIndex = detectedSwings.count - 1
        mainViewShowsReplay = false
        pipDisplayMode = .lastSwingReplay
        // No state change — recording continues seamlessly
    }

    // MARK: - Actions

    func startRecording() {
        guard state == .idle else { return }

        // Start countdown
        state = .countdown(remaining: 5)

        Task {
            // Ensure camera is running (should already be from onAppear, but just in case)
            if !cameraService.captureSession.isRunning {
                cameraService.setupSession(position: .front, frameRate: 30)
                cameraService.startSession()
                // Wait for camera to initialize
                try? await Task.sleep(for: .milliseconds(300))
            }

            // Run countdown 5-4-3-2-1
            for i in stride(from: 5, through: 1, by: -1) {
                state = .countdown(remaining: i)
                try? await Task.sleep(for: .seconds(1))

                // Check if cancelled
                if state == .idle { return }
            }

            // Start actual recording
            beginRecording()
        }
    }

    private func beginRecording() {
        recordingStartTimestamp = nil // Will be set on first frame
        isCurrentlyRecording = true
        _frameProcessedCount = 0

        let detectorName = activeDetector is ActionClassifierDetector
            ? "Action Classifier (pose-based, any angle)"
            : "SwingNet (GolfDB video events)"

        print("═══════════════════════════════════════════════════════════════")
        print("RECORDING STARTED")
        print("═══════════════════════════════════════════════════════════════")
        print("   Detector: \(detectorName)")
        print("   Camera: \(isFrontCamera ? "Front" : "Back")")
        print("═══════════════════════════════════════════════════════════════")

        // startRecording() now returns optional URL (nil if disk space error)
        guard let url = cameraService.startRecording() else {
            // Error already set by CameraService, cancel recording
            isCurrentlyRecording = false
            state = .idle
            errorMessage = cameraService.currentError?.errorDescription
            return
        }

        recordingURL = url
        detectedSwings.removeAll()
        mainViewShowsReplay = false
        replayingSwingIndex = nil
        pipDisplayMode = .liveCamera
        activeDetector.reset()
        state = .recording
    }

    func stopRecording() {
        guard isRecording else { return }

        isCurrentlyRecording = false

        // Show finalizing state while waiting for video file to be written
        state = .finalizingVideo

        // Stop recording - this triggers onRecordingFinished callback when done
        // The callback will show the save confirmation dialog
        cameraService.stopRecording()
    }

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

    func cancel() {
        isCurrentlyRecording = false
        cameraService.stopRecording()
        cameraService.stopSession()
        recordingURL = nil
        recordingStartTimestamp = nil
        detectedSwings.removeAll()
        mainViewShowsReplay = false
        replayingSwingIndex = nil
        activeDetector.reset()
        state = .idle
    }

    func toggleFavorite(at index: Int) {
        guard detectedSwings.indices.contains(index) else { return }
        detectedSwings[index].isFavorite.toggle()
    }

    // MARK: - Save Recording

    func saveRecording(to modelContext: ModelContext) async -> SwingVideo? {
        guard let sourceURL = recordingURL else { return nil }

        state = .saving

        // Store swing count before clearing (for verification)
        let swingsToSave = detectedSwings
        let expectedDuration = cameraService.recordedDuration

        do {
            // Verify source file exists and has content
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                errorMessage = "Recording file not found"
                state = .reviewing
                return nil
            }

            // Small delay to ensure file is fully written to disk
            try? await Task.sleep(for: .milliseconds(500))

            // Copy to permanent storage
            let permanentURL = try VideoStorageService.shared.copyVideoToStorage(from: sourceURL)

            // Create SwingVideo
            var video = await VideoStorageService.shared.createSwingVideo(from: permanentURL)

            // WORKAROUND: AVFoundation sometimes reports wrong duration from file metadata
            // If the file duration seems wrong (significantly different from expected), use expected
            let durationMismatch = abs(video.duration - expectedDuration)
            if durationMismatch > 5.0 && expectedDuration > 0 {
                print("⚠️ Duration mismatch detected! File reports \(video.duration)s, expected \(expectedDuration)s")
                print("⚠️ Using expected duration from recording timer")
                video.duration = expectedDuration
            }

            // Log for debugging
            print("📹 Saving video: expected \(expectedDuration)s, actual \(video.duration)s, \(swingsToSave.count) swings")

            // Add ALL swing markers
            for (index, clip) in swingsToSave.enumerated() {
                let marker = SwingMarker(
                    startTime: clip.startTime,
                    contactTime: clip.impactTime,
                    endTime: clip.endTime
                )
                marker.isAutoDetected = true
                marker.detectionConfidence = clip.confidence
                marker.video = video
                video.swings.append(marker)
                print("📍 Saved swing \(index + 1): \(clip.startTime)s - \(clip.endTime)s")
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
        mainViewShowsReplay = false
        replayingSwingIndex = nil
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
        activeDetector.reset()
    }
}
