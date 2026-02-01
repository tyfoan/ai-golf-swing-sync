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
    var currentPose: BodyPose?
    var detectedSwings: [SwingClip] = []
    var recordingURL: URL?

    // MARK: - UI State

    var showPoseOverlay = true
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
    // Skip more frames in debug builds for better performance
    // These are nonisolated because they're accessed from background threads
    #if DEBUG
    nonisolated(unsafe) private let poseDetector = LivePoseDetector(processEveryNthFrame: 3)
    #else
    nonisolated(unsafe) private let poseDetector = LivePoseDetector(processEveryNthFrame: 2)
    #endif
    nonisolated(unsafe) private let swingDetector = LiveSwingDetector()
    nonisolated(unsafe) private let audioImpactDetector = AudioImpactDetector()

    // MARK: - Background Processing

    /// Dedicated queue for pose detection (avoid main thread blocking)
    nonisolated(unsafe) private let poseProcessingQueue = DispatchQueue(
        label: "com.golfsync.pose.processing",
        qos: .userInteractive
    )

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
        setupCallbacks()

        // Warm up Vision model on background thread to avoid first-frame lag
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.poseDetector.warmup()
        }
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

        // Audio processing callback - for impact sound detection
        cameraService.onAudioCaptured = { [weak self] sampleBuffer in
            guard let self, self.isCurrentlyRecording else { return }
            self.audioImpactDetector.processAudioBuffer(sampleBuffer)
        }

        // Audio impact detected - forward to swing detector for confirmation
        audioImpactDetector.onImpactDetected = { [weak self] timestamp, _ in
            guard let self else { return }
            // Convert to file-relative time
            if let startTime = self.recordingStartTimestamp {
                let relativeTime = timestamp - startTime
                self.swingDetector.confirmAudioImpact(at: relativeTime)
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

        // Swing detection callback - fires immediately on detection
        swingDetector.onSwingDetected = { [weak self] bounds in
            Task { @MainActor [weak self] in
                self?.handleSwingDetected(bounds)
            }
        }
    }

    // MARK: - Frame Processing (Background Thread)

    /// Process frame on background queue for minimal latency
    /// This method is nonisolated because it runs on a background queue for performance
    nonisolated private func processFrameOnBackground(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
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

        // Build full pose frame with all joints for enhanced detection
        let poseFrame = PoseFrame(
            timestamp: relativeTime,
            // Wrists
            leftWristY: pose.leftWristPosition.map { Double($0.y) },
            rightWristY: pose.rightWristPosition.map { Double($0.y) },
            // Shoulders
            leftShoulderY: pose.leftShoulderPosition.map { Double($0.y) },
            rightShoulderY: pose.rightShoulderPosition.map { Double($0.y) },
            leftShoulderX: pose.leftShoulderPosition.map { Double($0.x) },
            rightShoulderX: pose.rightShoulderPosition.map { Double($0.x) },
            // Hips
            leftHipY: pose.leftHipPosition.map { Double($0.y) },
            rightHipY: pose.rightHipPosition.map { Double($0.y) },
            leftHipX: pose.leftHipPosition.map { Double($0.x) },
            rightHipX: pose.rightHipPosition.map { Double($0.x) }
        )

        // Feed full pose data to swing detector for multi-joint analysis
        swingDetector.addPose(poseFrame)

        // Update UI on main thread (only pose display, not detection logic)
        DispatchQueue.main.async { [weak self] in
            self?.currentPose = pose
        }
    }

    // MARK: - Swing Detection

    private func handleSwingDetected(_ bounds: SwingBounds) {
        // Create clip and add to list
        let clip = SwingClip(from: bounds)
        detectedSwings.append(clip)

        // IMMEDIATELY switch to replay mode to avoid having two camera previews
        // (main + PiP both showing camera causes black screen issues)
        replayingSwingIndex = detectedSwings.count - 1
        mainViewShowsReplay = true
        pipDisplayMode = .liveCamera

        // Show processing state while waiting for video frames
        state = .processingSwing

        // Wait for video file to have all frames, then transition to recording state
        Task {
            // Calculate wait time: endTime - detectionTime + buffer
            // This ensures the video file has all frames from start to end
            let waitMs = Int(clip.requiredWaitTime * 1000)
            try? await Task.sleep(for: .milliseconds(waitMs))

            await MainActor.run {
                self.state = .recording
            }
        }
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
        swingDetector.reset()
        audioImpactDetector.reset()
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
        currentPose = nil
        mainViewShowsReplay = false
        replayingSwingIndex = nil
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
        currentPose = nil
        poseDetector.reset()
        swingDetector.reset()
        audioImpactDetector.reset()
    }
}
