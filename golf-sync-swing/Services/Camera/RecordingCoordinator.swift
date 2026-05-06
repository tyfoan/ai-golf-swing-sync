//
//  RecordingCoordinator.swift
//  golf-sync-swing
//
//  Manages the recording lifecycle: start/stop, duration timer,
//  background task, and disk space validation.
//

import AVFoundation
import UIKit

protocol RecordingCoordinating {
    var isRecording: Bool { get }
    var recordedDuration: TimeInterval { get }
    func startRecording(movieOutput: AVCaptureMovieFileOutput, delegate: AVCaptureFileOutputRecordingDelegate) -> URL?
    func stopRecording(movieOutput: AVCaptureMovieFileOutput?)
}

final class RecordingCoordinator: RecordingCoordinating {

    private(set) var isRecording = false
    private(set) var recordedDuration: TimeInterval = 0

    /// Called when recording exceeds maximumDuration
    var onMaximumDurationReached: (() -> Void)?
    /// Called every timer tick with the current recorded duration so observers
    /// (e.g. an @Observable CameraService) can mirror the value into a stored
    /// property — SwiftUI doesn't observe across non-Observable objects.
    var onDurationTick: ((TimeInterval) -> Void)?

    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var currentRecordingURL: URL?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTimer: Timer?

    private let minimumDiskSpace: Int64 = 500 * 1024 * 1024
    private let maximumDuration: TimeInterval = 1800

    deinit {
        durationTimer?.invalidate()
        backgroundTimer?.invalidate()
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }

    func startRecording(movieOutput: AVCaptureMovieFileOutput, delegate: AVCaptureFileOutputRecordingDelegate) -> URL? {
        guard hasEnoughDiskSpace() else { return nil }
        guard !movieOutput.isRecording else { return nil }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        currentRecordingURL = outputURL

        let beginTask = { [weak self] in
            guard let self else { return }
            self.backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                self?.endBackgroundTask()
            }
            self.backgroundTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
                self?.endBackgroundTask()
            }
        }

        if Thread.isMainThread {
            beginTask()
        } else {
            DispatchQueue.main.sync { beginTask() }
        }

        if let connection = movieOutput.connection(with: .video),
           connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }

        movieOutput.startRecording(to: outputURL, recordingDelegate: delegate)

        isRecording = true
        recordedDuration = 0
        recordingStartTime = Date()
        startDurationTimer()

        return outputURL
    }

    func stopRecording(movieOutput: AVCaptureMovieFileOutput?) {
        stopDurationTimer()

        guard let movieOutput, movieOutput.isRecording else {
            isRecording = false
            endBackgroundTask()
            return
        }

        movieOutput.stopRecording()
    }

    func markRecordingFinished() {
        isRecording = false
        stopDurationTimer()
        endBackgroundTask()
    }

    // MARK: - Private

    private func hasEnoughDiskSpace() -> Bool {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let values = try? paths.first?.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity >= minimumDiskSpace
        }
        return false
    }

    private func endBackgroundTask() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private func startDurationTimer() {
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let startTime = self.recordingStartTime else { return }
            self.recordedDuration = Date().timeIntervalSince(startTime)
            self.onDurationTick?(self.recordedDuration)
            if self.recordedDuration >= self.maximumDuration {
                self.onMaximumDurationReached?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        durationTimer = timer
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}
