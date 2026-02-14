//
//  RecordingViewModel.swift
//  golf-sync-swing
//
//  Orchestrator for recording workflow.
//  Delegates to collaborators:
//    FrameProcessingGate  - Thread-safe frame gating and timing
//    CameraService        - Camera session management
//    ActionClassifierDetector - Live swing detection
//
//  Types: RecordingTypes.swift (RecordingState, PipDisplayMode, SwingClip)
//

import SwiftUI
import AVFoundation
import SwiftData

@MainActor
@Observable
final class RecordingViewModel {

    // MARK: - State

    var state: RecordingState = .idle
    var detectedSwings: [SwingClip] = []
    var recordingURL: URL?

    // MARK: - UI State

    var playbackSpeed: Float = 1.0
    var savedVideo: SwingVideo?
    var errorMessage: String?
    var mainViewShowsReplay: Bool = false
    var replayingSwingIndex: Int? = nil
    var pipDisplayMode: PipDisplayMode = .liveCamera
    var isLoadingReplay: Bool = false
    var detectionAnimationActive: Bool = false
    var skeletonEnabled: Bool = false
    var currentJointMap: BodyJointMap?

    // MARK: - Collaborators

    let cameraService = CameraService()
    nonisolated(unsafe) private let detector = ActionClassifierDetector()
    nonisolated(unsafe) private let frameGate = FrameProcessingGate()

    private var countdownTask: Task<Void, Never>?
    private let saveService = RecordingSaveService()
    nonisolated(unsafe) private let poseProcessingQueue = DispatchQueue(
        label: "com.golfsync.pose.processing", qos: .userInteractive
    )

    // MARK: - Computed Properties

    var isCountingDown: Bool { if case .countdown = state { return true }; return false }
    var countdownValue: Int { if case .countdown(let v) = state { return v }; return 0 }
    var isRecording: Bool { state == .recording || state == .processingSwing }
    var isProcessingSwing: Bool { state == .processingSwing }
    var isFinalizingVideo: Bool { state == .finalizingVideo }
    var isReviewing: Bool { state == .reviewing }
    var isSaving: Bool { state == .saving }
    var swingCount: Int { detectedSwings.count }
    var isFrontCamera: Bool { cameraService.currentCameraPosition == .front }
    var lastDetectedSwing: SwingClip? { detectedSwings.last }

    var currentReplaySwing: SwingClip? {
        guard let index = replayingSwingIndex, detectedSwings.indices.contains(index) else { return nil }
        return detectedSwings[index]
    }

    var pipSwing: SwingClip? { currentReplaySwing ?? lastDetectedSwing }

    // MARK: - Init

    init() {
        setupCallbacks()
    }

    private func setupCallbacks() {
        cameraService.onFrameCaptured = { [weak self] pixelBuffer, timestamp in
            guard let self else { return }
            guard self.frameGate.tryAcquire() else { return }
            self.poseProcessingQueue.async {
                defer { self.frameGate.release() }
                self.processFrameOnBackground(pixelBuffer, timestamp: timestamp)
            }
        }

        cameraService.onRecordingFinished = { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.mainViewShowsReplay = false
                    self.isLoadingReplay = false
                    self.replayingSwingIndex = nil
                    self.state = .idle
                } else {
                    self.state = .reviewing
                }
            }
        }

        detector.onSwingDetected = { [weak self] bounds in
            Task { @MainActor [weak self] in self?.handleSwingDetected(bounds) }
        }
    }

    // MARK: - Frame Processing (Background Thread)

    nonisolated private func processFrameOnBackground(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard frameGate.isCurrentlyRecording else { return }
        let relativeTime = frameGate.recordFrame(at: timestamp.seconds)
        detector.processFrame(pixelBuffer, at: relativeTime)

        // Throttle skeleton updates to ~15fps (every other frame)
        let shouldPublishSkeleton = frameGate.frameProcessedCount % 2 == 0
        guard shouldPublishSkeleton else { return }

        let jointMap = detector.posePublisher.latestJointMap
        Task { @MainActor [weak self] in
            self?.currentJointMap = jointMap
        }
    }

    // MARK: - Swing Detection

    private func handleSwingDetected(_ bounds: SwingBounds) {
        guard isRecording else { return }
        let clip = SwingClip(from: bounds)
        detectedSwings.append(clip)
        replayingSwingIndex = detectedSwings.count - 1
        mainViewShowsReplay = true
        isLoadingReplay = true
        pipDisplayMode = .liveCamera
        triggerDetectionAnimation()
    }

    private func triggerDetectionAnimation() {
        detectionAnimationActive = true
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            detectionAnimationActive = false
        }
    }

    // MARK: - Actions

    func startRecording() {
        guard state == .idle else { return }
        countdownTask?.cancel()
        state = .countdown(remaining: 5)

        countdownTask = Task {
            if !cameraService.captureSession.isRunning {
                cameraService.setupSession(position: .front, frameRate: 30)
                cameraService.startSession()
                try? await Task.sleep(for: .milliseconds(300))
            }

            for i in stride(from: 5, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                state = .countdown(remaining: i)
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }

            beginRecording()
        }
    }

    private func beginRecording() {
        frameGate.reset()
        frameGate.isCurrentlyRecording = true

        guard let url = cameraService.startRecording() else {
            frameGate.isCurrentlyRecording = false
            state = .idle
            errorMessage = cameraService.currentError?.errorDescription
            return
        }

        recordingURL = url
        detectedSwings.removeAll()
        mainViewShowsReplay = false
        isLoadingReplay = false
        replayingSwingIndex = nil
        pipDisplayMode = .liveCamera
        detector.reset()
        state = .recording
    }

    func stopRecording() {
        guard isRecording else { return }
        frameGate.isCurrentlyRecording = false
        mainViewShowsReplay = false
        isLoadingReplay = false
        replayingSwingIndex = nil
        state = .finalizingVideo
        cameraService.stopRecording()
    }

    // MARK: - PiP & Replay

    func togglePipDisplay() {
        switch pipDisplayMode {
        case .liveCamera:
            if lastDetectedSwing != nil { pipDisplayMode = .lastSwingReplay }
        case .lastSwingReplay:
            if mainViewShowsReplay { pipDisplayMode = .liveCamera }
        }
    }

    func swapMainAndPip() {
        guard !detectedSwings.isEmpty else { return }
        if replayingSwingIndex == nil {
            replayingSwingIndex = detectedSwings.indices.last
        }
        mainViewShowsReplay.toggle()
        isLoadingReplay = mainViewShowsReplay
        pipDisplayMode = mainViewShowsReplay ? .liveCamera : .lastSwingReplay
    }

    func showSwing(at index: Int) {
        guard detectedSwings.indices.contains(index) else { return }
        replayingSwingIndex = index
        mainViewShowsReplay = true
        isLoadingReplay = true
        pipDisplayMode = .liveCamera
    }

    func showLiveCamera() {
        mainViewShowsReplay = false
        isLoadingReplay = false
        replayingSwingIndex = nil
        if lastDetectedSwing != nil { pipDisplayMode = .lastSwingReplay }
    }

    func replayDidLoad() {
        isLoadingReplay = false
    }

    func toggleFavorite(at index: Int) {
        guard detectedSwings.indices.contains(index) else { return }
        detectedSwings[index].isFavorite.toggle()
    }

    private static let speeds: [Float] = [0.25, 0.5, 1.0]

    func cyclePlaybackSpeed() {
        guard let nextIndex = Self.speeds.firstIndex(of: playbackSpeed).map({ $0 + 1 }) else {
            playbackSpeed = Self.speeds[0]
            return
        }
        playbackSpeed = Self.speeds[nextIndex % Self.speeds.count]
    }

    // MARK: - Save & Delete

    func saveRecording(to modelContext: ModelContext) async -> SwingVideo? {
        guard let sourceURL = recordingURL else { return nil }
        state = .saving

        do {
            let video = try await saveService.save(
                sourceURL: sourceURL,
                swings: detectedSwings,
                expectedDuration: cameraService.recordedDuration,
                modelContext: modelContext
            )
            recordingURL = nil
            detectedSwings.removeAll()
            mainViewShowsReplay = false
            isLoadingReplay = false
            replayingSwingIndex = nil
            savedVideo = video
            state = .idle
            return video
        } catch {
            errorMessage = error.localizedDescription
            state = .reviewing
            return nil
        }
    }

    func deleteRecording() {
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL = nil
        detectedSwings.removeAll()
        mainViewShowsReplay = false
        isLoadingReplay = false
        replayingSwingIndex = nil
        state = .idle
    }

    func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
        frameGate.isCurrentlyRecording = false
        cameraService.stopRecording()
        cameraService.stopSession()
        recordingURL = nil
        detectedSwings.removeAll()
        mainViewShowsReplay = false
        isLoadingReplay = false
        replayingSwingIndex = nil
        detector.reset()
        state = .idle
    }

    func cleanup() {
        frameGate.isCurrentlyRecording = false
        cameraService.stopSession()
        detector.reset()
    }
}
