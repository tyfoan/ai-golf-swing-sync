# Milestone 3: Recording with Real-Time Swing Detection

## Reference: Golf Swing Cam App Flow

Based on analysis of Golf Swing Cam:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         RECORDING WORKFLOW                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. TAP "Start Recording"                                           │
│           ↓                                                         │
│  2. COUNTDOWN (5-4-3-2-1)                                          │
│     - Front camera preview (user sees themselves)                   │
│     - Cancel button available                                       │
│           ↓                                                         │
│  3. RECORDING STARTS                                                │
│     - Main view: Back camera (captures swing)                       │
│     - PiP corner: Front camera (user's face)                       │
│     - Real-time body pose skeleton overlay                          │
│     - Continuous swing detection in background                      │
│           ↓                                                         │
│  4. SWING DETECTED → Auto-extract clip                              │
│     - "Loading replay..." overlay                                   │
│     - Extract swing segment (start → impact → end)                  │
│           ↓                                                         │
│  5. INSTANT REPLAY (Recording continues!)                           │
│     - Main view: Plays back detected swing (with pose overlay)      │
│     - PiP corner: LIVE camera feed - recording still active         │
│     - User can star/favorite the swing                              │
│     - User can keep swinging → next swing detected → repeat         │
│           ↓                                                         │
│  6. STOP RECORDING                                                  │
│     - Action sheet: Save (N Swings) / Delete / Cancel               │
│           ↓                                                         │
│  7. REVIEW MODE                                                     │
│     - Toggle: "Full Video" / "Swings Only"                          │
│     - Swings carousel at bottom                                     │
│     - "EDIT MANUALLY" option                                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## View States During Recording

```
┌────────────────────────────────────────────────────────────────────────┐
│  STATE 1: COUNTDOWN                                                    │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │                    FRONT CAMERA (full screen)                    │  │
│  │                         User sees self                           │  │
│  │                            "4"                                   │  │
│  │                                                                  │  │
│  │                          CANCEL                                  │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────┐
│  STATE 2: RECORDING (waiting for swing)                                │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  [X]                                                             │  │
│  │                                                                  │  │
│  │                   BACK CAMERA (main view)                        │  │
│  │                  + Pose skeleton overlay                         │  │
│  │                  Recording the swing area                        │  │
│  │                                                                  │  │
│  │              [1.0x] [⏸] [☆] [🧍]                                  │  │
│  │                       [⏺]                                        │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────┐
│  STATE 3: SWING DETECTED → INSTANT REPLAY                              │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  [X]                                        ┌────────────┐       │  │
│  │                                             │ 🔴 LIVE    │       │  │
│  │                                             │ Back cam   │       │  │
│  │            REPLAY OF DETECTED SWING         │ (PiP)      │       │  │
│  │            + Pose skeleton overlay          │ Recording  │       │  │
│  │            Looping playback                 │ continues! │       │  │
│  │                                             └────────────┘       │  │
│  │              [1.0x] [⏸] [☆] [🧍]                                  │  │
│  │                       [⏺]                                        │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  → After 3 seconds OR next swing detected → back to STATE 2            │
│  → User can do MULTIPLE swings without stopping                        │
└────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────┐
│  STATE 4: STOP RECORDING                                               │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                                             ┌────────────┐       │  │
│  │                                             │ Last frame │       │  │
│  │          LAST SWING PREVIEW                 │ (frozen)   │       │  │
│  │                                             └────────────┘       │  │
│  │  ┌─────────────────────────────────────────────────────────────┐ │  │
│  │  │  Save Recording (2 Swings)                                  │ │  │
│  │  │  Delete Recording                                           │ │  │
│  │  │  Cancel                                                     │ │  │
│  │  └─────────────────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Technical Architecture

### Components Needed

```
Services/
├── CameraService.swift           # AVCaptureSession management
├── LivePoseDetector.swift        # Real-time Vision pose on camera frames
├── LiveSwingDetector.swift       # Detects swing in real-time (modified SwingDetector)
├── VideoSegmentExtractor.swift   # Extract swing clips from recording buffer
└── RecordingSessionManager.swift # Orchestrates the full recording workflow

Views/
├── RecordingView.swift           # Main recording UI
├── CountdownView.swift           # 5-4-3-2-1 overlay
├── CameraPreviewView.swift       # UIViewRepresentable for AVCaptureVideoPreviewLayer
├── PoseOverlayView.swift         # Draws skeleton on camera feed
├── LiveRecordingView.swift       # Recording mode with PiP
├── SwingReplayView.swift         # Instant replay after detection
└── RecordingReviewView.swift     # Full video / Swings Only toggle

ViewModels/
└── RecordingViewModel.swift      # State machine for recording workflow

Models/
├── RecordingSession.swift        # Current recording state + detected swings
└── SwingClip.swift               # Extracted swing segment with timestamps
```

---

## Phase 1: Camera Setup

### 1.1 CameraService

```swift
import AVFoundation
import Vision

final class CameraService: NSObject {
    // Dual camera support (iPhone X+ only)
    private let captureSession = AVCaptureMultiCamSession() // or AVCaptureSession for single

    private var backCameraInput: AVCaptureDeviceInput?
    private var frontCameraInput: AVCaptureDeviceInput?

    private var videoOutput: AVCaptureVideoDataOutput?
    private var movieOutput: AVCaptureMovieFileOutput?

    // Frame callback for pose detection
    var onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)?

    func setupDualCamera() async throws {
        // Check if multi-cam is supported
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            // Fallback to single camera
            try await setupSingleCamera()
            return
        }

        // Setup back camera (main recording)
        let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

        // Setup front camera (PiP)
        let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)

        // Configure for high frame rate (120fps if available)
        try configureFrameRate(device: backCamera, targetFPS: 120)

        // Add inputs and outputs...
    }

    func startRecording(to url: URL) {
        movieOutput?.startRecording(to: url, recordingDelegate: self)
    }

    func stopRecording() {
        movieOutput?.stopRecording()
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        onFrameCaptured?(pixelBuffer, timestamp)
    }
}
```

### 1.2 CameraPreviewView (SwiftUI)

```swift
import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
```

---

## Phase 2: Real-Time Pose Detection

### 2.1 LivePoseDetector

```swift
import Vision

actor LivePoseDetector {
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var lastPose: BodyPose?

    /// Process frame and return pose (called on every camera frame)
    func detectPose(in pixelBuffer: CVPixelBuffer) async -> BodyPose? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([poseRequest])

            guard let observation = poseRequest.results?.first else {
                return nil
            }

            let pose = BodyPose(from: observation)
            lastPose = pose
            return pose
        } catch {
            return nil
        }
    }
}

/// Simplified pose for UI rendering
struct BodyPose {
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let confidence: Float

    init(from observation: VNHumanBodyPoseObservation) {
        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

        let jointNames: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck,
            .rightShoulder, .rightElbow, .rightWrist,
            .leftShoulder, .leftElbow, .leftWrist,
            .rightHip, .rightKnee, .rightAnkle,
            .leftHip, .leftKnee, .leftAnkle
        ]

        for name in jointNames {
            if let point = try? observation.recognizedPoint(name),
               point.confidence > 0.3 {
                joints[name] = point.location
            }
        }

        self.joints = joints
        self.confidence = observation.confidence
    }
}
```

### 2.2 PoseOverlayView

```swift
import SwiftUI

struct PoseOverlayView: View {
    let pose: BodyPose?
    let frameSize: CGSize

    // Skeleton connections
    private let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        // Torso
        (.neck, .rightShoulder), (.neck, .leftShoulder),
        (.rightShoulder, .rightHip), (.leftShoulder, .leftHip),
        (.rightHip, .leftHip),
        // Right arm
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        // Left arm
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        // Right leg
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        // Left leg
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        // Head
        (.nose, .neck)
    ]

    var body: some View {
        Canvas { context, size in
            guard let pose = pose else { return }

            // Draw connections
            for (from, to) in connections {
                guard let fromPoint = pose.joints[from],
                      let toPoint = pose.joints[to] else { continue }

                let start = convertPoint(fromPoint, to: size)
                let end = convertPoint(toPoint, to: size)

                var path = Path()
                path.move(to: start)
                path.addLine(to: end)

                context.stroke(path, with: .color(.white), lineWidth: 3)
            }

            // Draw joint dots
            for (_, point) in pose.joints {
                let center = convertPoint(point, to: size)
                let circle = Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5,
                                                     width: 10, height: 10))
                context.fill(circle, with: .color(.white))
            }
        }
    }

    private func convertPoint(_ point: CGPoint, to size: CGSize) -> CGPoint {
        // Vision coordinates: origin bottom-left, normalized 0-1
        // SwiftUI: origin top-left
        CGPoint(
            x: point.x * size.width,
            y: (1 - point.y) * size.height
        )
    }
}
```

---

## Phase 3: Real-Time Swing Detection

### 3.1 LiveSwingDetector

Key insight: Detect swing **during recording** using a sliding window of recent poses.

```swift
actor LiveSwingDetector {
    // Ring buffer of recent poses (last ~3 seconds)
    private var poseHistory: [(timestamp: TimeInterval, pose: BodyPose)] = []
    private let maxHistoryDuration: TimeInterval = 3.0

    // Detection state
    private var isInSwing = false
    private var swingStartTime: TimeInterval?

    // Callback when swing is detected
    var onSwingDetected: ((SwingBounds) -> Void)?

    struct SwingBounds {
        let startTime: TimeInterval
        let impactTime: TimeInterval
        let endTime: TimeInterval
    }

    /// Add pose to history and check for swing
    func addPose(_ pose: BodyPose, at timestamp: TimeInterval) {
        // Add to history
        poseHistory.append((timestamp, pose))

        // Trim old entries
        let cutoff = timestamp - maxHistoryDuration
        poseHistory.removeAll { $0.timestamp < cutoff }

        // Detect swing phases
        detectSwing(currentTime: timestamp)
    }

    private func detectSwing(currentTime: TimeInterval) {
        guard poseHistory.count >= 10 else { return }

        // Calculate wrist velocity
        let recentPoses = poseHistory.suffix(10)
        var velocities: [Double] = []

        for i in 1..<recentPoses.count {
            let prev = recentPoses[recentPoses.startIndex + i - 1]
            let curr = recentPoses[recentPoses.startIndex + i]

            guard let prevWrist = prev.pose.joints[.rightWrist] ?? prev.pose.joints[.leftWrist],
                  let currWrist = curr.pose.joints[.rightWrist] ?? curr.pose.joints[.leftWrist] else {
                continue
            }

            let dt = curr.timestamp - prev.timestamp
            guard dt > 0 else { continue }

            let velocityY = (currWrist.y - prevWrist.y) / dt
            velocities.append(velocityY)
        }

        // Detect swing start: movement begins
        if !isInSwing {
            let avgVelocity = velocities.reduce(0, +) / Double(velocities.count)
            if abs(avgVelocity) > 0.15 {
                isInSwing = true
                swingStartTime = currentTime - 0.3 // Include setup
            }
        }

        // Detect impact: fast downward + deceleration
        if isInSwing, let startTime = swingStartTime {
            if let lastVel = velocities.last,
               velocities.count >= 2,
               lastVel < -0.4, // Fast downward
               velocities[velocities.count - 1] > velocities[velocities.count - 2] { // Decelerating

                let impactTime = currentTime
                let endTime = currentTime + 0.5 // Will be refined

                onSwingDetected?(SwingBounds(
                    startTime: startTime,
                    impactTime: impactTime,
                    endTime: endTime
                ))

                // Reset for next swing
                isInSwing = false
                swingStartTime = nil
            }

            // Timeout: if no impact within 3 seconds, reset
            if currentTime - startTime > 3.0 {
                isInSwing = false
                swingStartTime = nil
            }
        }
    }
}
```

---

## Phase 4: Recording View with PiP

### 4.1 LiveRecordingView

```swift
struct LiveRecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()

    var body: some View {
        ZStack {
            // Main camera view (back camera)
            CameraPreviewView(session: viewModel.cameraService.session)
                .ignoresSafeArea()

            // Pose skeleton overlay
            PoseOverlayView(pose: viewModel.currentPose, frameSize: UIScreen.main.bounds.size)

            // PiP front camera (top right)
            if viewModel.isRecording {
                FrontCameraPiPView(session: viewModel.cameraService.frontSession)
                    .frame(width: 120, height: 160)
                    .cornerRadius(12)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            // Close button (top left)
            VStack {
                HStack {
                    Button(action: viewModel.cancel) {
                        Image(systemName: "xmark")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding()
                Spacer()
            }

            // Bottom controls
            VStack {
                Spacer()

                if viewModel.isRecording {
                    // Recording controls
                    HStack(spacing: 24) {
                        // Speed selector
                        SpeedButton(speed: $viewModel.playbackSpeed)

                        // Pause/Resume
                        Button(action: viewModel.togglePause) {
                            Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.gray.opacity(0.6))
                                .clipShape(Circle())
                        }

                        // Favorite
                        Button(action: viewModel.toggleFavorite) {
                            Image(systemName: viewModel.isFavorite ? "star.fill" : "star")
                                .font(.title)
                                .foregroundColor(.white)
                        }

                        // Pose toggle
                        Button(action: viewModel.togglePose) {
                            Image(systemName: "figure.stand")
                                .font(.title)
                                .foregroundColor(viewModel.showPose ? .green : .white)
                        }
                    }
                    .padding(.bottom, 20)
                }

                // Record/Stop button
                Button(action: viewModel.isRecording ? viewModel.stopRecording : viewModel.startRecording) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 70, height: 70)

                        if viewModel.isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red)
                                .frame(width: 30, height: 30)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 60, height: 60)
                        }
                    }
                }
                .padding(.bottom, 30)
            }

            // Countdown overlay
            if viewModel.isCountingDown {
                CountdownOverlay(count: viewModel.countdownValue)
            }

            // Swing detected → Replay mode
            // Main view becomes replay, camera moves to PiP
            if viewModel.showingReplay, let clip = viewModel.lastDetectedSwing {
                // Main: Replay of detected swing
                SwingReplayView(clip: clip, recordingURL: viewModel.recordingURL)

                // PiP: Live camera (recording continues)
                CameraPreviewView(session: viewModel.cameraService.session)
                    .frame(width: 120, height: 160)
                    .cornerRadius(12)
                    .overlay(
                        // Recording indicator
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .padding(8),
                        alignment: .topLeading
                    )
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }
}
```

### 4.2 CountdownView

```swift
struct CountdownOverlay: View {
    let count: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)

            Text("\(count)")
                .font(.system(size: 200, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(radius: 10)

            VStack {
                Spacer()
                Button("CANCEL") {
                    // Cancel countdown
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.bottom, 50)
            }
        }
        .ignoresSafeArea()
    }
}
```

---

## Phase 5: Recording State Machine

### 5.1 RecordingViewModel

```swift
@MainActor
@Observable
final class RecordingViewModel {
    enum State {
        case idle
        case countdown(remaining: Int)
        case recording
        case showingReplay(SwingClip)
        case reviewing
    }

    var state: State = .idle

    // Camera
    let cameraService = CameraService()
    private let poseDetector = LivePoseDetector()
    private let swingDetector = LiveSwingDetector()

    // Current state
    var currentPose: BodyPose?
    var detectedSwings: [SwingClip] = []
    var recordingURL: URL?

    // UI state
    var isCountingDown: Bool { if case .countdown = state { return true } else { return false } }
    var countdownValue: Int { if case .countdown(let v) = state { return v } else { return 0 } }
    var isRecording: Bool { if case .recording = state { return true } else { return false } }
    var showingReplay: Bool { if case .showingReplay = state { return true } else { return false } }
    var lastDetectedSwing: SwingClip? { if case .showingReplay(let c) = state { return c } else { return nil } }

    var showPose = true
    var isPaused = false
    var isFavorite = false
    var playbackSpeed: Float = 1.0

    init() {
        setupCallbacks()
    }

    private func setupCallbacks() {
        // Frame callback → pose detection
        cameraService.onFrameCaptured = { [weak self] buffer, time in
            Task { [weak self] in
                guard let self else { return }
                let pose = await poseDetector.detectPose(in: buffer)
                await MainActor.run {
                    self.currentPose = pose
                }
                if let pose {
                    await swingDetector.addPose(pose, at: time.seconds)
                }
            }
        }

        // Swing detected callback
        Task {
            await swingDetector.onSwingDetected = { [weak self] bounds in
                await self?.handleSwingDetected(bounds)
            }
        }
    }

    func startRecording() {
        state = .countdown(remaining: 5)
        runCountdown()
    }

    private func runCountdown() {
        Task {
            for i in stride(from: 5, through: 1, by: -1) {
                state = .countdown(remaining: i)
                try? await Task.sleep(for: .seconds(1))
            }
            beginRecording()
        }
    }

    private func beginRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        recordingURL = url

        cameraService.startRecording(to: url)
        state = .recording
    }

    func stopRecording() {
        cameraService.stopRecording()
        state = .reviewing
    }

    private func handleSwingDetected(_ bounds: LiveSwingDetector.SwingBounds) async {
        guard case .recording = state else { return }

        // Extract swing clip from recording buffer
        // This would use VideoSegmentExtractor to create a clip
        let clip = SwingClip(
            startTime: bounds.startTime,
            impactTime: bounds.impactTime,
            endTime: bounds.endTime,
            isFavorite: false
        )

        await MainActor.run {
            detectedSwings.append(clip)
            state = .showingReplay(clip)
        }

        // Auto-dismiss replay after 3 seconds
        try? await Task.sleep(for: .seconds(3))
        await MainActor.run {
            if case .showingReplay = state {
                state = .recording
            }
        }
    }

    func dismissReplay() {
        state = .recording
    }

    func cancel() {
        cameraService.stopRecording()
        state = .idle
    }

    func togglePause() { isPaused.toggle() }
    func toggleFavorite() { isFavorite.toggle() }
    func togglePose() { showPose.toggle() }
}
```

---

## Phase 6: Review Mode

### 6.1 RecordingReviewView

```swift
struct RecordingReviewView: View {
    let recordingURL: URL
    let swings: [SwingClip]
    @State private var viewMode: ViewMode = .fullVideo
    @State private var selectedSwingIndex: Int = 0

    enum ViewMode: String, CaseIterable {
        case fullVideo = "Full Video"
        case swingsOnly = "Swings Only"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { /* dismiss */ }) {
                        Image(systemName: "arrow.left")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.green)
                            .clipShape(Circle())
                    }

                    Spacer()

                    // View mode picker
                    Menu {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Button(mode.rawValue) {
                                viewMode = mode
                            }
                        }
                    } label: {
                        HStack {
                            Text(viewMode.rawValue)
                                .foregroundColor(.white)
                            Image(systemName: "chevron.down")
                                .foregroundColor(.white)
                        }
                    }

                    Spacer()

                    Button(action: { /* share */ }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                }
                .padding()

                // Video player
                SwingVideoPlayer(
                    url: recordingURL,
                    swings: viewMode == .swingsOnly ? swings : nil,
                    selectedSwingIndex: $selectedSwingIndex
                )

                // Swings carousel (only in Swings Only mode)
                if viewMode == .swingsOnly && !swings.isEmpty {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Swings")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            Button("EDIT MANUALLY") {
                                // Open swing editor
                            }
                            .foregroundColor(.green)
                        }
                        .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(swings.indices, id: \.self) { index in
                                    SwingThumbnailView(
                                        swing: swings[index],
                                        index: index + 1,
                                        isSelected: index == selectedSwingIndex
                                    )
                                    .onTapGesture {
                                        selectedSwingIndex = index
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
    }
}
```

---

## Implementation Order

### Week 1: Camera Foundation
1. [ ] CameraService with back camera recording
2. [ ] CameraPreviewView (SwiftUI wrapper)
3. [ ] Basic recording start/stop
4. [ ] High frame rate configuration (120fps)

### Week 2: Real-Time Pose
1. [ ] LivePoseDetector with frame callback
2. [ ] PoseOverlayView skeleton rendering
3. [ ] Performance optimization (skip frames if needed)
4. [ ] Test pose detection accuracy

### Week 3: Live Swing Detection
1. [ ] LiveSwingDetector with ring buffer
2. [ ] Real-time velocity tracking
3. [ ] Swing detection callbacks
4. [ ] Test detection latency

### Week 4: Recording Flow
1. [ ] RecordingViewModel state machine
2. [ ] CountdownView
3. [ ] LiveRecordingView with pose overlay
4. [ ] Swing detected notification UI

### Week 5: PiP & Replay
1. [ ] Dual camera setup (if supported)
2. [ ] Front camera PiP view
3. [ ] SwingReplayOverlay
4. [ ] Recording continues during replay

### Week 6: Review Mode
1. [ ] RecordingReviewView
2. [ ] Full Video / Swings Only toggle
3. [ ] Swings carousel
4. [ ] Manual edit integration
5. [ ] Save/Delete recording

---

## Technical Challenges

### 1. Dual Camera (Multi-Cam)
- Only iPhone XS+ supports AVCaptureMultiCamSession
- Fallback: Single camera with no PiP for older devices
- Battery drain is significant with dual cameras

### 2. Real-Time Pose Performance
- Vision pose detection: ~30ms per frame on iPhone 12+
- At 120fps, can only process every 4th frame
- Use separate dispatch queue for ML processing

### 3. Ring Buffer for Swing Extraction
- Need to keep last 3-5 seconds of frames in memory
- CVPixelBuffer pool to avoid memory spikes
- Extract to file when swing detected

### 4. Recording During Replay (Critical UX Feature)
- AVCaptureMovieFileOutput **never stops** during replay
- Main view: AVPlayer for replay clip (looping)
- PiP view: Live AVCaptureVideoPreviewLayer (shows recording continues)
- User sees: "I can keep swinging while reviewing my last swing"
- Multiple swings in one session without stopping recording
- PiP acts as visual indicator that recording is still active

---

## Dependencies

- iOS 14+ for VNDetectHumanBodyPoseRequest
- iOS 13+ for AVCaptureMultiCamSession (iPhone XS+)
- Camera permission (NSCameraUsageDescription)
- Microphone permission for audio (NSMicrophoneUsageDescription)

---

## Related Files

- [Milestone 2 Research](./milestone-2-research.md) - Pose detection details
- [SwingDetector.swift](../golf-sync-swing/Services/SwingDetector.swift) - Existing detection logic
- [Architecture](../docs/architecture.md) - System design
