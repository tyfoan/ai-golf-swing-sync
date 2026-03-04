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
    var pipDisplayMode: PipDisplayMode {
        if mainViewShowsReplay { return .liveCamera }
        if lastDetectedSwing != nil { return .lastSwingReplay }
        return .liveCamera
    }
    var isLoadingReplay: Bool = false

    // MARK: - Dependencies

    var modelContext: ModelContext?

    // MARK: - Collaborators

    let cameraService = CameraService()
    private let detectionOrchestrator = DetectionOrchestrator()
    private let photosSaveService = PhotosSaveService()
    private let videoStorageService = VideoStorageService.shared

    private var countdownTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var isCountingDown: Bool { if case .countdown = state { return true }; return false }
    var countdownValue: Int { if case .countdown(let v) = state { return v }; return 0 }
    var isRecording: Bool { state == .recording }
    var isFinalizingVideo: Bool { state == .finalizingVideo }
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
                self.playbackSpeed = 0.5
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
                    self.state = .reviewing
                }
            }
        }
    }

    // MARK: - Actions

    func startRecording() {
        guard state == .idle else { return }
        countdownTask?.cancel()
        state = .countdown(remaining: 5)

        countdownTask = Task {
            if !cameraService.captureSession.isRunning, !cameraService.isSessionConfiguredForCurrentParams {
                cameraService.setupSession(position: .front, frameRate: 30)
                try? await Task.sleep(for: .milliseconds(300))
            }
            if !cameraService.captureSession.isRunning {
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
        guard cameraService.isSessionRunning else {
            state = .idle
            errorMessage = "Camera session is not running."
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
        state = .saving

        let authorized = await PhotosSaveService.requestAuthorization()
        guard authorized else {
            errorMessage = "Photos access denied. Please enable in Settings."
            state = .reviewing
            return
        }

        do {
            // Save to Photos library
            if detectedSwings.isEmpty {
                try await photosSaveService.saveFullRecording(from: url)
            } else {
                for swing in detectedSwings {
                    try await photosSaveService.saveClip(
                        from: url,
                        startTime: swing.startTime,
                        endTime: swing.endTime
                    )
                }
            }

            // Persist to SwiftData for History tab
            let persisted = await persistToSwiftData(recordingURL: url)

            if persisted { try? FileManager.default.removeItem(at: url) }
            recordingURL = nil
            detectedSwings.removeAll()
            mainViewShowsReplay = false
            isLoadingReplay = false
            replayingSwingIndex = nil
            state = .saved
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { state = .idle; return }
            state = .idle
        } catch {
            errorMessage = error.localizedDescription
            state = .reviewing
        }
    }

    private func persistToSwiftData(recordingURL: URL) async -> Bool {
        guard let modelContext else { return false }

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
            return true
        } catch {
            AppLogger.detection.error("Failed to persist swing data: \(error.localizedDescription)")
            return false
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
