//
//  RecordingViewModel.swift
//  golf-sync-swing
//
//  Orchestrator for recording workflow.
//  Delegates to collaborators:
//    CameraService - Camera session management
//
//  Types: RecordingTypes.swift (RecordingState, PipDisplayMode, SwingClip)
//

import SwiftUI
import SwiftData
import AVFoundation
import CoreMedia
import os

@MainActor
@Observable
final class RecordingViewModel {

    // MARK: - State

    var state: RecordingState = .idle
    var detectedSwings: [SwingClip] = []
    var recordingURL: URL?

    // MARK: - UI State

    var playbackSpeed: Float = 1.0
    var errorMessage: String?
    var mainViewShowsReplay: Bool = false
    var replayingSwingIndex: Int? = nil
    var requiresLibraryUpgrade: Bool = false
    private(set) var saveOutcome: SaveOutcome?
    // PiP is always the live camera now — replays go straight to the main view.
    // Running a SwingReplayView in PiP simultaneously with one in main caused
    // FigSharedMemPool/PlayerRemoteXPC churn on the in-progress recording file.
    var pipDisplayMode: PipDisplayMode { .liveCamera }
    var isLoadingReplay: Bool = false

    // MARK: - Dependencies

    var modelContext: ModelContext?

    // MARK: - Collaborators

    let cameraService = CameraService.shared
    private let detectionOrchestrator = DetectionOrchestrator()
    private let photosSaveService = PhotosSaveService()
    private let videoStorageService = VideoStorageService.shared

    private var countdownTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var isCountingDown: Bool { if case .countdown = state { return true }; return false }
    var countdownValue: Int { if case .countdown(let v) = state { return v }; return 0 }
    var isRecording: Bool { state == .recording }
    var isFinalizingVideo: Bool { state == .finalizingVideo }
    var isSaving: Bool { state == .saving }
    var isReviewing: Bool { state == .reviewing }
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
        detectionOrchestrator.onSwingDetected = { [weak self] clip in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.detectedSwings.append(clip)
                self.playbackSpeed = 1.0
                Analytics.shared.track(.swingDetected)
                // Detection feedback only — haptic + green flash + swing-count
                // badge in the top bar. We do NOT play the in-progress recording
                // file: opening it with AVURLAsset causes iOS to terminate the
                // recording (FigApplicationStateMonitor interrupt). Replay is
                // available after the user stops recording.
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    deinit {
        detectionOrchestrator.onSwingDetected = nil
        cameraService.onRecordingFinished = nil
        cameraService.onFrameCaptured = nil
        cameraService.onAudioCaptured = nil
    }

    private func setupCallbacks() {
        cameraService.onRecordingFinished = { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    AppLogger.camera.error("RecordingViewModel: onRecordingFinished error=\(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                    self.detectionOrchestrator.stop()
                    self.cameraService.onFrameCaptured = nil
                    self.cameraService.onAudioCaptured = nil
                    self.mainViewShowsReplay = false
                    self.isLoadingReplay = false
                    self.replayingSwingIndex = nil
                    self.state = .idle
                } else {
                    self.cameraService.pauseSession()
                    await self.handleRecordingFinished()
                }
            }
        }
    }

    /// Auto-save flow after a recording finishes. No swings detected → discard
    /// the recording (don't clutter Photos or History with unmarked clips).
    /// Swings detected → kick saveToPhotos directly, skipping the manual
    /// Delete/Save Review step. The FinalizingVideoOverlay stays visible
    /// continuously from .finalizingVideo through .saving to .saved, so there
    /// is no UI flash mid-flow.
    private func handleRecordingFinished() async {
        if detectedSwings.isEmpty {
            AppLogger.camera.info("RecordingViewModel: no swings detected, discarding recording")
            deleteRecording()
            return
        }
        await saveToPhotos()
        // saveToPhotos sets state .saving as soon as preconditions pass. If
        // state is still .finalizingVideo here, the save was blocked (library
        // gate / paywall) — drop into .reviewing so the user has a manual
        // Save/Delete fallback once they dismiss the paywall.
        if state == .finalizingVideo {
            state = .reviewing
        }
    }

    // MARK: - Actions

    func startRecording() {
        guard state == .idle else { return }
        countdownTask?.cancel()
        state = .countdown(remaining: 5)

        countdownTask = Task {
            let started = await ensureSessionRunning()
            guard !Task.isCancelled else { return }
            guard started else {
                state = .idle
                errorMessage = String(localized: "Camera could not start. Try closing and reopening the app.", comment: "Error message shown when the capture session fails to start during the recording countdown")
                return
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

    /// Configure (if needed) and start the capture session, then poll until
    /// it's actually running. Uses `resumeSession` so the audio session is
    /// reactivated when iOS deactivated it after a previous recording — plain
    /// `startSession` skips that step and silently no-ops on the second start.
    private func ensureSessionRunning(timeout: TimeInterval = 3.0) async -> Bool {
        if cameraService.captureSession.isRunning { return true }

        if !cameraService.isSessionConfiguredForCurrentParams {
            cameraService.setupSession(position: .front, frameRate: 30)
            try? await Task.sleep(for: .milliseconds(300))
        }

        cameraService.resumeSession()

        let deadline = Date().addingTimeInterval(timeout)
        while !cameraService.captureSession.isRunning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return cameraService.captureSession.isRunning
    }

    private func beginRecording() {
        // Source of truth: AVCaptureSession's own state. The @Observable mirror
        // `isSessionRunning` is updated via DispatchQueue.main.async and can lag
        // behind the real session — `ensureSessionRunning()` polls the real one
        // and we must agree, or we false-error mid-countdown.
        guard cameraService.captureSession.isRunning else {
            state = .idle
            errorMessage = String(localized: "Camera session is not running.", comment: "Error message when the user taps record but the AVCaptureSession is not active")
            return
        }
        guard let url = cameraService.startRecording() else {
            state = .idle
            errorMessage = cameraService.currentError?.errorDescription
            return
        }

        recordingURL = url
        detectedSwings.removeAll()
        mainViewShowsReplay = false
        isLoadingReplay = false
        replayingSwingIndex = nil
        state = .recording
        Analytics.shared.track(.recordingStarted)
        cameraService.onFrameCaptured = { [weak self] pixelBuffer, timestamp in
            self?.detectionOrchestrator.processFrame(
                pixelBuffer: pixelBuffer,
                timestamp: CMTimeGetSeconds(timestamp)
            )
        }
        detectionOrchestrator.start()
    }

    func stopRecording() {
        guard isRecording else { return }
        mainViewShowsReplay = false
        isLoadingReplay = false
        replayingSwingIndex = nil
        detectionOrchestrator.stop()
        cameraService.onFrameCaptured = nil
        cameraService.onAudioCaptured = nil
        state = .finalizingVideo
        cameraService.stopRecording()
    }

    // MARK: - PiP & Replay

    func swapMainAndPip() {
        guard !detectedSwings.isEmpty else { return }
        if replayingSwingIndex == nil {
            replayingSwingIndex = detectedSwings.indices.last
        }
        mainViewShowsReplay.toggle()
        isLoadingReplay = mainViewShowsReplay
        AppLogger.ui.info("swapMainAndPip: mainViewShowsReplay=\(self.mainViewShowsReplay) loadingReplay=\(self.isLoadingReplay)")
    }

    func showSwing(at index: Int) {
        guard detectedSwings.indices.contains(index) else { return }
        replayingSwingIndex = index
        mainViewShowsReplay = true
        isLoadingReplay = true
    }

    func showLiveCamera() {
        mainViewShowsReplay = false
        isLoadingReplay = false
        replayingSwingIndex = nil
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

    func saveToPhotos() async {
        guard let url = recordingURL else { return }
        guard !libraryGateBlocksSave() else { requiresLibraryUpgrade = true; return }
        state = .saving
        guard await ensurePhotosAuthorized() else { return }
        do {
            try await writeRecordingToPhotos(from: url)
            let savedVideo = await persistToSwiftData(recordingURL: url)
            finalizeSave(with: savedVideo, originalURL: url)
        } catch {
            errorMessage = error.localizedDescription
            state = .reviewing
        }
    }

    /// Returns to idle after the saved-state hand-off has been consumed
    /// (currently: auto-navigate to History). Distinct from `cancel()`,
    /// which also tears down the capture session.
    func dismissSavedState() {
        saveOutcome = nil
        state = .idle
    }

    private func libraryGateBlocksSave() -> Bool {
        guard let modelContext else { return false }
        return !LibraryGateService.canAddSwing(in: modelContext)
    }

    private func ensurePhotosAuthorized() async -> Bool {
        let authorized = await PhotosSaveService.requestAuthorization()
        guard !authorized else { return true }
        errorMessage = String(localized: "Photos access denied. Please enable in Settings.", comment: "Error shown after Save when the user has denied Photos write permission")
        state = .reviewing
        return false
    }

    private func writeRecordingToPhotos(from url: URL) async throws {
        if detectedSwings.isEmpty {
            try await photosSaveService.saveFullRecording(from: url)
            return
        }
        for swing in detectedSwings {
            try await photosSaveService.saveClip(
                from: url,
                startTime: swing.startTime,
                endTime: swing.endTime
            )
        }
    }

    private func finalizeSave(with savedVideo: SwingVideo?, originalURL: URL) {
        Analytics.shared.track(.swingSaved(
            saveType: detectedSwings.isEmpty ? "full" : "clip",
            count: detectedSwings.count
        ))
        if let savedVideo {
            saveOutcome = SaveOutcome(videoID: savedVideo.id, swingCount: detectedSwings.count)
            try? FileManager.default.removeItem(at: originalURL)
        }
        recordingURL = nil
        detectedSwings.removeAll()
        mainViewShowsReplay = false
        isLoadingReplay = false
        replayingSwingIndex = nil
        state = .saved
    }

    private func persistToSwiftData(recordingURL: URL) async -> SwingVideo? {
        guard let modelContext else { return nil }

        do {
            let storedURL = try videoStorageService.copyVideoToStorage(from: recordingURL)
            let swingVideo = await videoStorageService.createSwingVideo(from: storedURL)
            swingVideo.hasBeenAnalyzed = !detectedSwings.isEmpty
            swingVideo.analysisDate = detectedSwings.isEmpty ? nil : Date()

            modelContext.insert(swingVideo)

            for clip in detectedSwings {
                let marker = SwingMarker(
                    startTime: clip.startTime,
                    contactTime: clip.impactTime,
                    endTime: clip.endTime
                )
                marker.isAutoDetected = true
                marker.detectionConfidence = clip.confidence
                marker.isFavorite = clip.isFavorite
                marker.video = swingVideo
                modelContext.insert(marker)
            }

            try modelContext.save()
            return swingVideo
        } catch {
            AppLogger.detection.error("Failed to persist swing data: \(error.localizedDescription)")
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
        saveOutcome = nil
        state = .idle
    }

    func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
        detectionOrchestrator.stop()
        cameraService.onFrameCaptured = nil
        cameraService.onAudioCaptured = nil
        cameraService.stopRecording()
        cameraService.stopSession()
        recordingURL = nil
        detectedSwings.removeAll()
        mainViewShowsReplay = false
        isLoadingReplay = false
        replayingSwingIndex = nil
        saveOutcome = nil
        state = .idle
    }

    func cleanup() {
        detectionOrchestrator.stop()
        detectionOrchestrator.onSwingDetected = nil
        cameraService.onRecordingFinished = nil
        cameraService.onFrameCaptured = nil
        cameraService.onAudioCaptured = nil
        cameraService.stopSession()
    }
}
