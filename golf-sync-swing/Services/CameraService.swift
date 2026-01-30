//
//  CameraService.swift
//  golf-sync-swing
//
//  Manages camera capture session for recording golf swings
//

import AVFoundation
import UIKit
import Combine

final class CameraService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var recordedDuration: TimeInterval = 0

    // MARK: - Capture Session

    let captureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var movieFileOutput: AVCaptureMovieFileOutput?

    // MARK: - Queues

    private let sessionQueue = DispatchQueue(label: "com.golfsync.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.golfsync.camera.videoOutput")

    // MARK: - Callbacks

    /// Called for each video frame captured (for pose detection)
    var onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)?

    /// Called when recording completes
    var onRecordingFinished: ((URL?, Error?) -> Void)?

    // MARK: - Configuration

    private var targetFrameRate: Double = 60
    private var currentCameraPosition: AVCaptureDevice.Position = .back

    // MARK: - Recording State

    private var recordingStartTime: Date?
    private var durationTimer: Timer?

    // MARK: - Setup

    func requestPermissions() async -> Bool {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        var videoGranted = videoStatus == .authorized
        var audioGranted = audioStatus == .authorized

        if videoStatus == .notDetermined {
            videoGranted = await AVCaptureDevice.requestAccess(for: .video)
        }

        if audioStatus == .notDetermined {
            audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
        }

        return videoGranted && audioGranted
    }

    func setupSession(position: AVCaptureDevice.Position = .back, frameRate: Double = 60) {
        sessionQueue.async { [weak self] in
            self?.configureSession(position: position, frameRate: frameRate)
        }
    }

    private func configureSession(position: AVCaptureDevice.Position, frameRate: Double) {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        // Remove existing inputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            print("Failed to get video device")
            captureSession.commitConfiguration()
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
                videoDeviceInput = videoInput
                currentCameraPosition = position
            }

            // Configure frame rate
            configureFrameRate(device: videoDevice, targetFPS: frameRate)

        } catch {
            print("Failed to create video input: \(error)")
            captureSession.commitConfiguration()
            return
        }

        // Add audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                    audioDeviceInput = audioInput
                }
            } catch {
                print("Failed to create audio input: \(error)")
            }
        }

        // Add video data output (for frame analysis)
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            videoDataOutput = videoOutput

            // Set video orientation
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if position == .front && connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
        }

        // Add movie file output (for recording)
        let movieOutput = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
            movieFileOutput = movieOutput

            // Set video orientation for recording
            if let connection = movieOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if position == .front && connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
        }

        captureSession.commitConfiguration()
        targetFrameRate = frameRate
    }

    private func configureFrameRate(device: AVCaptureDevice, targetFPS: Double) {
        do {
            try device.lockForConfiguration()

            // Find the best format supporting target frame rate
            var bestFormat: AVCaptureDevice.Format?
            var bestFrameRateRange: AVFrameRateRange?

            for format in device.formats {
                for range in format.videoSupportedFrameRateRanges {
                    if range.maxFrameRate >= targetFPS {
                        if bestFrameRateRange == nil || range.maxFrameRate < bestFrameRateRange!.maxFrameRate {
                            bestFormat = format
                            bestFrameRateRange = range
                        }
                    }
                }
            }

            if let format = bestFormat, let range = bestFrameRateRange {
                device.activeFormat = format
                let actualFPS = min(targetFPS, range.maxFrameRate)
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(actualFPS))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(actualFPS))
            }

            device.unlockForConfiguration()
        } catch {
            print("Failed to configure frame rate: \(error)")
        }
    }

    // MARK: - Session Control

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = self.captureSession.isRunning
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    // MARK: - Camera Switching

    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = currentCameraPosition == .back ? .front : .back
        setupSession(position: newPosition, frameRate: targetFrameRate)
    }

    func setCamera(position: AVCaptureDevice.Position) {
        if position != currentCameraPosition {
            setupSession(position: position, frameRate: targetFrameRate)
        }
    }

    // MARK: - Recording

    func startRecording() -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        sessionQueue.async { [weak self] in
            guard let self, let movieOutput = self.movieFileOutput else { return }

            if movieOutput.isRecording {
                return
            }

            // Configure video stabilization if available
            if let connection = movieOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }

            movieOutput.startRecording(to: outputURL, recordingDelegate: self)

            DispatchQueue.main.async {
                self.isRecording = true
                self.recordedDuration = 0
                self.recordingStartTime = Date()
                self.startDurationTimer()
            }
        }

        return outputURL
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, let movieOutput = self.movieFileOutput else { return }

            if movieOutput.isRecording {
                movieOutput.stopRecording()
            }

            DispatchQueue.main.async {
                self.stopDurationTimer()
            }
        }
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let startTime = self.recordingStartTime else { return }
            self.recordedDuration = Date().timeIntervalSince(startTime)
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        onFrameCaptured?(pixelBuffer, timestamp)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            self?.onRecordingFinished?(outputFileURL, error)
        }
    }
}
