//
//  CameraService.swift
//  golf-sync-swing
//
//  Facade for camera capture session management.
//  Delegates to collaborators:
//    CameraPermissionManager      - Permission requests and state checks
//    CaptureSessionConfigurator   - Session setup and format negotiation
//    RecordingCoordinator         - Recording lifecycle and duration timer
//
//  Error types: CameraError.swift
//

import AVFoundation
import Observation
import UIKit

@Observable
final class CameraService: NSObject {

    // MARK: - Observable State

    var isSessionRunning = false
    var isRecording = false
    var recordedDuration: TimeInterval = 0
    var sessionConfigurationId: Int = 0
    var droppedFrameCount: Int = 0
    var currentError: CameraError?
    var isInterrupted = false

    // MARK: - Capture Session

    let captureSession = AVCaptureSession()
    private(set) var currentCameraPosition: AVCaptureDevice.Position = .back

    // MARK: - Collaborators

    private let permissionManager = CameraPermissionManager()
    private let configurator = CaptureSessionConfigurator()
    private let recordingCoordinator = RecordingCoordinator()
    private let notificationHandler = CameraNotificationHandler()

    // MARK: - Internal State

    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var isAudioSessionConfigured = false
    private var isSessionConfigured = false
    private var targetFrameRate: Double = 60

    // MARK: - Queues

    private let sessionQueue = DispatchQueue(label: "com.golfsync.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.golfsync.camera.videoOutput", qos: .userInteractive, autoreleaseFrequency: .workItem)
    private let audioOutputQueue = DispatchQueue(label: "com.golfsync.camera.audioOutput", qos: .userInteractive, autoreleaseFrequency: .workItem)

    // MARK: - Callbacks

    var onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)?
    var onAudioCaptured: ((CMSampleBuffer) -> Void)?
    var onRecordingFinished: ((URL?, Error?) -> Void)?
    var onSessionInterrupted: ((CameraError.InterruptionReason) -> Void)?
    var onSessionResumed: (() -> Void)?
    var onError: ((CameraError) -> Void)?

    // MARK: - Init

    override init() {
        super.init()
        setupNotificationHandler()
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let granted = await permissionManager.requestPermissions()
        if !granted {
            let status = permissionManager.checkPermissionState()
            DispatchQueue.main.async {
                self.currentError = status.video == .restricted ? .permissionRestricted : .permissionDenied
            }
        }
        return granted
    }

    func checkPermissionState() -> (video: AVAuthorizationStatus, audio: AVAuthorizationStatus) {
        permissionManager.checkPermissionState()
    }

    // MARK: - Session Setup

    func setupSession(position: AVCaptureDevice.Position = .back, frameRate: Double = 60) {
        sessionQueue.async { [weak self] in
            self?.configureSession(position: position, frameRate: frameRate)
        }
    }

    private func configureSession(position: AVCaptureDevice.Position, frameRate: Double) {
        configureAudioSession()

        let (outputs, error) = configurator.configure(
            session: captureSession,
            config: .init(position: position, frameRate: frameRate),
            videoDelegate: self,
            audioDelegate: self,
            videoQueue: videoOutputQueue,
            audioQueue: audioOutputQueue
        )

        if let error {
            DispatchQueue.main.async {
                self.currentError = error
                self.onError?(error)
            }
            return
        }

        movieFileOutput = outputs.movieFileOutput
        currentCameraPosition = position
        targetFrameRate = frameRate
        isSessionConfigured = true

        DispatchQueue.main.async {
            self.sessionConfigurationId += 1
            self.currentError = nil
        }
    }

    // MARK: - Session Control

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async { self.isSessionRunning = self.captureSession.isRunning }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning { self.captureSession.stopRunning() }
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
        deactivateAudioSession()
    }

    func pauseSession() {
        guard captureSession.isRunning else { return }
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    func resumeSession() {
        let permissions = checkPermissionState()
        guard permissions.video == .authorized else {
            DispatchQueue.main.async { self.currentError = .permissionDenied }
            return
        }
        guard !captureSession.isRunning else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            if !self.isAudioSessionConfigured { self.configureAudioSession() }
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
        guard let movieOutput = movieFileOutput else { return nil }

        var url: URL?
        sessionQueue.sync {
            url = recordingCoordinator.startRecording(movieOutput: movieOutput, delegate: self)
        }

        if url == nil {
            DispatchQueue.main.async {
                self.currentError = .insufficientStorage
                self.onError?(.insufficientStorage)
            }
        } else {
            DispatchQueue.main.async {
                self.isRecording = true
                self.recordedDuration = 0
                self.droppedFrameCount = 0
            }
        }

        return url
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.recordingCoordinator.stopRecording(movieOutput: self.movieFileOutput)
            DispatchQueue.main.async { self.isRecording = false }
        }
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        guard !isAudioSessionConfigured else { return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
            try audioSession.setActive(true)
            isAudioSessionConfigured = true
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isAudioSessionConfigured = false
    }

    // MARK: - Notifications

    private func setupNotificationHandler() {
        notificationHandler.register(for: captureSession)

        notificationHandler.onInterrupted = { [weak self] reason in
            DispatchQueue.main.async {
                self?.isInterrupted = true
                self?.currentError = .sessionInterrupted(reason)
                self?.onSessionInterrupted?(reason)
            }
        }

        notificationHandler.onInterruptionEnded = { [weak self] in
            DispatchQueue.main.async {
                self?.isInterrupted = false
                self?.currentError = nil
                self?.onSessionResumed?()
            }
            self?.sessionQueue.async { [weak self] in
                guard let self, !self.captureSession.isRunning else { return }
                self.captureSession.startRunning()
                DispatchQueue.main.async { self.isSessionRunning = self.captureSession.isRunning }
            }
        }

        notificationHandler.onRuntimeError = { [weak self] error in
            if error.code == .mediaServicesWereReset {
                self?.sessionQueue.async { [weak self] in
                    guard let self, self.isSessionRunning else { return }
                    self.captureSession.startRunning()
                    DispatchQueue.main.async { self.isSessionRunning = self.captureSession.isRunning }
                }
            } else {
                DispatchQueue.main.async {
                    self?.currentError = .configurationFailed(error.localizedDescription)
                    self?.onError?(.configurationFailed(error.localizedDescription))
                }
            }
        }
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
        DispatchQueue.main.async { self.droppedFrameCount += 1 }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        recordingCoordinator.markRecordingFinished()
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            self?.recordedDuration = self?.recordingCoordinator.recordedDuration ?? 0
            self?.onRecordingFinished?(outputFileURL, error)
        }
    }
}
