//
//  CameraService.swift
//  golf-sync-swing
//
//  Manages camera capture session for recording golf swings
//  Production-ready with proper lifecycle, interruption, and error handling
//

import AVFoundation
import UIKit
import Observation

// MARK: - Camera Errors

enum CameraError: LocalizedError, Equatable {
    case permissionDenied
    case permissionRestricted
    case noVideoDevice
    case noAudioDevice
    case configurationFailed(String)
    case insufficientStorage
    case sessionInterrupted(InterruptionReason)
    case recordingFailed(String)

    enum InterruptionReason: Equatable {
        case audioInUse
        case videoInUse
        case backgrounded
        case systemPressure
        case unknown
    }

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera access denied. Please enable in Settings."
        case .permissionRestricted:
            return "Camera access is restricted on this device."
        case .noVideoDevice:
            return "No camera available on this device."
        case .noAudioDevice:
            return "No microphone available on this device."
        case .configurationFailed(let reason):
            return "Camera configuration failed: \(reason)"
        case .insufficientStorage:
            return "Not enough storage space. Please free up at least 500MB."
        case .sessionInterrupted(let reason):
            switch reason {
            case .audioInUse:
                return "Recording interrupted by another audio app."
            case .videoInUse:
                return "Camera is being used by another app."
            case .backgrounded:
                return "Recording paused because app went to background."
            case .systemPressure:
                return "Recording paused due to system resource constraints."
            case .unknown:
                return "Recording was interrupted."
            }
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        }
    }
}

// MARK: - Camera Service

@Observable
final class CameraService: NSObject {

    // MARK: - Observable State

    var isSessionRunning = false
    var isRecording = false
    var recordedDuration: TimeInterval = 0
    var sessionConfigurationId: Int = 0
    var droppedFrameCount: Int = 0

    /// Current error state (nil = no error)
    var currentError: CameraError?

    /// Whether session is interrupted (phone call, etc.)
    var isInterrupted = false

    // MARK: - Capture Session

    let captureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var movieFileOutput: AVCaptureMovieFileOutput?

    // MARK: - Queues

    private let sessionQueue = DispatchQueue(label: "com.golfsync.camera.session")
    private let videoOutputQueue = DispatchQueue(
        label: "com.golfsync.camera.videoOutput",
        qos: .userInteractive,
        autoreleaseFrequency: .workItem
    )
    private let audioOutputQueue = DispatchQueue(
        label: "com.golfsync.camera.audioOutput",
        qos: .userInteractive,
        autoreleaseFrequency: .workItem
    )

    // MARK: - Callbacks

    var onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)?
    var onAudioCaptured: ((CMSampleBuffer) -> Void)?
    var onRecordingFinished: ((URL?, Error?) -> Void)?
    var onSessionInterrupted: ((CameraError.InterruptionReason) -> Void)?
    var onSessionResumed: (() -> Void)?
    var onError: ((CameraError) -> Void)?

    // MARK: - Configuration

    private var targetFrameRate: Double = 60
    private(set) var currentCameraPosition: AVCaptureDevice.Position = .back

    // MARK: - Recording State

    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var currentRecordingURL: URL?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var isAudioSessionConfigured = false
    private var isSessionConfigured = false

    // MARK: - Constants

    /// Minimum required disk space (500MB for ~1 min of 1080p30)
    private let minimumDiskSpace: Int64 = 500 * 1024 * 1024

    // MARK: - Init

    override init() {
        super.init()
        setupNotifications()
    }

    deinit {
        removeNotifications()
    }

    // MARK: - Notifications Setup

    private func setupNotifications() {
        // Session interruption notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: captureSession
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: captureSession
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: captureSession
        )

        // Audio session interruption
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioSessionInterrupted),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        // Thermal state monitoring
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    private func removeNotifications() {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Session Interruption Handling

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        guard let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
              let interruptionReason = AVCaptureSession.InterruptionReason(rawValue: reason) else {
            DispatchQueue.main.async {
                self.isInterrupted = true
                self.onSessionInterrupted?(.unknown)
            }
            return
        }

        var errorReason: CameraError.InterruptionReason = .unknown

        switch interruptionReason {
        case .videoDeviceNotAvailableInBackground:
            errorReason = .backgrounded
        case .audioDeviceInUseByAnotherClient:
            errorReason = .audioInUse
        case .videoDeviceInUseByAnotherClient:
            errorReason = .videoInUse
        case .videoDeviceNotAvailableDueToSystemPressure:
            errorReason = .systemPressure
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            errorReason = .videoInUse
        case .sensitiveContentMitigationActivated:
            errorReason = .unknown
        @unknown default:
            errorReason = .unknown
        }

        print("⚠️ Session interrupted: \(interruptionReason.rawValue)")

        DispatchQueue.main.async {
            self.isInterrupted = true
            self.currentError = .sessionInterrupted(errorReason)
            self.onSessionInterrupted?(errorReason)
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        print("✅ Session interruption ended")

        DispatchQueue.main.async {
            self.isInterrupted = false
            self.currentError = nil
            self.onSessionResumed?()
        }

        // Restart session if it was running before interruption
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = self.captureSession.isRunning
                }
            }
        }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }

        print("❌ Session runtime error: \(error.localizedDescription)")

        // Attempt to recover from media services reset
        if error.code == .mediaServicesWereReset {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if self.isSessionRunning {
                    self.captureSession.startRunning()
                    DispatchQueue.main.async {
                        self.isSessionRunning = self.captureSession.isRunning
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.currentError = .configurationFailed(error.localizedDescription)
                self.onError?(.configurationFailed(error.localizedDescription))
            }
        }
    }

    @objc private func audioSessionInterrupted(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            print("⚠️ Audio session interrupted")
            DispatchQueue.main.async {
                self.isInterrupted = true
            }

        case .ended:
            print("✅ Audio session interruption ended")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // Reactivate audio session
                    try? AVAudioSession.sharedInstance().setActive(true)
                    DispatchQueue.main.async {
                        self.isInterrupted = false
                    }
                }
            }

        @unknown default:
            break
        }
    }

    @objc private func thermalStateChanged(_ notification: Notification) {
        let state = ProcessInfo.processInfo.thermalState

        switch state {
        case .nominal, .fair:
            print("🌡️ Thermal state: normal")
        case .serious:
            print("⚠️ Thermal state: serious - consider reducing load")
        case .critical:
            print("🔥 Thermal state: critical - pausing non-essential processing")
            // Could reduce frame rate or pause pose detection here
        @unknown default:
            break
        }
    }

    // MARK: - Permissions

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

        // Update error state based on permissions
        if !videoGranted {
            DispatchQueue.main.async {
                self.currentError = videoStatus == .restricted ? .permissionRestricted : .permissionDenied
            }
        }

        return videoGranted && audioGranted
    }

    /// Check current permission state (call on app foreground)
    func checkPermissionState() -> (video: AVAuthorizationStatus, audio: AVAuthorizationStatus) {
        return (
            AVCaptureDevice.authorizationStatus(for: .video),
            AVCaptureDevice.authorizationStatus(for: .audio)
        )
    }

    // MARK: - Audio Session Configuration

    func configureAudioSession() throws {
        guard !isAudioSessionConfigured else { return }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .videoRecording,
            options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers]
        )
        try audioSession.setActive(true)
        isAudioSessionConfigured = true
    }

    func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isAudioSessionConfigured = false
    }

    // MARK: - Disk Space Validation

    func availableDiskSpace() -> Int64 {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let values = try? paths.first?.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        return 0
    }

    func hasEnoughDiskSpace() -> Bool {
        return availableDiskSpace() >= minimumDiskSpace
    }

    // MARK: - Session Setup

    func setupSession(position: AVCaptureDevice.Position = .back, frameRate: Double = 60) {
        sessionQueue.async { [weak self] in
            self?.configureSession(position: position, frameRate: frameRate)
        }
    }

    private func configureSession(position: AVCaptureDevice.Position, frameRate: Double) {
        // Configure audio session first
        do {
            try configureAudioSession()
        } catch {
            print("⚠️ Failed to configure audio session: \(error)")
        }

        captureSession.beginConfiguration()

        // Use inputPriority to allow custom activeFormat settings
        captureSession.sessionPreset = .inputPriority

        // Enable multitasking camera access on iPad
        if captureSession.isMultitaskingCameraAccessSupported {
            captureSession.isMultitaskingCameraAccessEnabled = true
        }

        // Remove existing inputs/outputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            print("❌ Failed to get video device")
            captureSession.commitConfiguration()
            DispatchQueue.main.async {
                self.currentError = .noVideoDevice
                self.onError?(.noVideoDevice)
            }
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
                videoDeviceInput = videoInput
                currentCameraPosition = position
            }

            // Configure format and frame rate
            configureDeviceFormat(device: videoDevice, targetFPS: frameRate)

        } catch {
            print("❌ Failed to create video input: \(error)")
            captureSession.commitConfiguration()
            DispatchQueue.main.async {
                self.currentError = .configurationFailed(error.localizedDescription)
                self.onError?(.configurationFailed(error.localizedDescription))
            }
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
                print("⚠️ Failed to create audio input: \(error)")
            }
        }

        // Add video data output (for frame analysis)
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        // Use YUV format for better performance (Vision handles both formats)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            videoDataOutput = videoOutput

            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = false
                }
            }
        }

        // Add audio data output (for impact detection)
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: audioOutputQueue)
        if captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
            audioDataOutput = audioOutput
        }

        // Add movie file output (for recording)
        let movieOutput = AVCaptureMovieFileOutput()
        // Write file fragments every 5 seconds to reduce data loss on crash
        movieOutput.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 1)

        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
            movieFileOutput = movieOutput

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
        isSessionConfigured = true

        DispatchQueue.main.async {
            self.sessionConfigurationId += 1
            self.currentError = nil
        }
    }

    private func configureDeviceFormat(device: AVCaptureDevice, targetFPS: Double) {
        do {
            try device.lockForConfiguration()

            // Find the best format: 1080p that supports target frame rate
            var bestFormat: AVCaptureDevice.Format?
            var bestFrameRateRange: AVFrameRateRange?

            for format in device.formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)

                // Target 1080p (1920x1080)
                guard dimensions.width == 1920 && dimensions.height == 1080 else { continue }

                for range in format.videoSupportedFrameRateRanges {
                    if range.maxFrameRate >= targetFPS {
                        if bestFrameRateRange == nil || range.maxFrameRate > bestFrameRateRange!.maxFrameRate {
                            bestFormat = format
                            bestFrameRateRange = range
                        }
                    }
                }
            }

            // Fallback: find highest resolution that supports target frame rate
            if bestFormat == nil {
                var bestResolution: Int = 0
                for format in device.formats {
                    let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    let resolution = Int(dimensions.width) * Int(dimensions.height)

                    for range in format.videoSupportedFrameRateRanges {
                        if range.maxFrameRate >= targetFPS && resolution > bestResolution {
                            bestFormat = format
                            bestFrameRateRange = range
                            bestResolution = resolution
                        }
                    }
                }
            }

            if let format = bestFormat, let range = bestFrameRateRange {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                print("📹 Selected format: \(dimensions.width)x\(dimensions.height) @ \(range.maxFrameRate)fps")

                device.activeFormat = format
                let actualFPS = min(targetFPS, range.maxFrameRate)
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(actualFPS))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(actualFPS))

                // Enable low-light boost if available
                if device.isLowLightBoostSupported {
                    device.automaticallyEnablesLowLightBoostWhenAvailable = true
                }
            }

            device.unlockForConfiguration()
        } catch {
            print("❌ Failed to configure device format: \(error)")
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

    /// Fully stop session (cleanup for app termination or view unload)
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
        deactivateAudioSession()
    }

    /// Pause session (for tab switching or app backgrounding)
    /// Does NOT deactivate audio session to allow fast resume
    func pauseSession() {
        // Quick check before dispatching
        guard captureSession.isRunning else { return }

        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    /// Resume session (for app foregrounding or tab switch)
    /// This is optimized for fast resume - avoids redundant configuration
    func resumeSession() {
        // Check permissions first
        let permissions = checkPermissionState()
        guard permissions.video == .authorized else {
            DispatchQueue.main.async {
                self.currentError = .permissionDenied
            }
            return
        }

        // Quick check before dispatching to session queue
        guard !captureSession.isRunning else { return }

        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }

            // Only configure audio session if not already configured
            // This makes tab switching much faster
            if !self.isAudioSessionConfigured {
                try? self.configureAudioSession()
            }

            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = self.captureSession.isRunning
                self.currentError = nil
                self.isInterrupted = false
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

    func startRecording() -> URL? {
        // Validate disk space first
        guard hasEnoughDiskSpace() else {
            DispatchQueue.main.async {
                self.currentError = .insufficientStorage
                self.onError?(.insufficientStorage)
            }
            return nil
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        currentRecordingURL = outputURL

        // Begin background task to ensure recording completes
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }

        sessionQueue.async { [weak self] in
            guard let self, let movieOutput = self.movieFileOutput else { return }

            if movieOutput.isRecording {
                return
            }

            // Configure video stabilization
            // Using .auto which automatically selects the best available mode
            if let connection = movieOutput.connection(with: .video),
               connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }

            movieOutput.startRecording(to: outputURL, recordingDelegate: self)

            DispatchQueue.main.async {
                self.isRecording = true
                self.recordedDuration = 0
                self.recordingStartTime = Date()
                self.droppedFrameCount = 0
                self.startDurationTimer()
            }
        }

        return outputURL
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, let movieOutput = self.movieFileOutput else {
                DispatchQueue.main.async {
                    self?.stopDurationTimer()
                    self?.isRecording = false
                    self?.endBackgroundTask()
                    let error = CameraError.recordingFailed("No movie output available")
                    self?.onRecordingFinished?(nil, error)
                }
                return
            }

            if movieOutput.isRecording {
                movieOutput.stopRecording()
            } else {
                let recordingURL = self.currentRecordingURL
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.endBackgroundTask()
                    if let url = recordingURL, FileManager.default.fileExists(atPath: url.path) {
                        self.onRecordingFinished?(url, nil)
                    } else {
                        let error = CameraError.recordingFailed("Recording was not active")
                        self.onRecordingFinished?(nil, error)
                    }
                }
            }

            DispatchQueue.main.async {
                self.stopDurationTimer()
            }
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
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

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate & AVCaptureAudioDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureVideoDataOutput {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            onFrameCaptured?(pixelBuffer, timestamp)
        } else if output is AVCaptureAudioDataOutput {
            onAudioCaptured?(sampleBuffer)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Track dropped frames for monitoring
        var mode: CMAttachmentMode = 0
        if let reason = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: &mode) {
            print("⚠️ Dropped frame: \(reason)")
        }
        DispatchQueue.main.async {
            self.droppedFrameCount += 1
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            self?.endBackgroundTask()
            self?.onRecordingFinished?(outputFileURL, error)
        }
    }
}
