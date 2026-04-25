# Smart Golf Camera Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the app from a full comparison tool into a focused smart golf camera that records on the front camera, auto-detects swings via body pose, shows instant slow-mo replay in PiP, and saves trimmed clips to Photos.

**Architecture:** Real-time pose detection pipeline — `CameraService.onFrameCaptured` feeds `CVPixelBuffer` frames into `PoseDetector` (VNSequenceRequestHandler + ring buffer), which feeds `SwingClassifier` (Create ML Action Classifier) and `PoseHeuristics` (fallback). Both strategies emit `SwingEvent` values consumed by `SwingStateMachine` (idle→detected→replay→cooldown). Impact frame is found via wrist y-minimum in the pose buffer (`ImpactDetector`). Save to Photos via `PHAssetChangeRequest`.

**Tech Stack:** Swift 5.0, SwiftUI, AVFoundation, Vision (VNDetectHumanBodyPoseRequest, VNSequenceRequestHandler), Create ML Action Classifier, Photos framework (PHAssetChangeRequest)

---

## Phase 1: Codebase Cleanup (Delete ~52 files, simplify app entry)

### Task 1: Delete comparison, paywall, onboarding, and library files

**Files to delete:**

```
# Views — comparison, library, editing, history
golf-sync-swing/Views/ComparisonView.swift
golf-sync-swing/Views/HomeView.swift
golf-sync-swing/Views/VideoLibraryView.swift
golf-sync-swing/Views/VideoPickerView.swift
golf-sync-swing/Views/SingleVideoPlayerView.swift
golf-sync-swing/Views/HistoryView.swift
golf-sync-swing/Views/SwingEditorSheet.swift
golf-sync-swing/Views/VideoPlayerView.swift
golf-sync-swing/Views/MainTabView.swift

# Views — components (comparison, playback, analysis)
golf-sync-swing/Views/Components/VideoRowView.swift
golf-sync-swing/Views/Components/PlayerTopBarView.swift
golf-sync-swing/Views/Components/SwingRowView.swift
golf-sync-swing/Views/Components/SwingMarkerSlider.swift
golf-sync-swing/Views/Components/PlaybackControlsView.swift
golf-sync-swing/Views/Components/SwingDetectionPanel.swift
golf-sync-swing/Views/Components/AnalysisOverlayView.swift
golf-sync-swing/Views/Components/TimelineSlider.swift
golf-sync-swing/Views/Components/ComparisonControlsView.swift
golf-sync-swing/Views/Components/VideoFloatingActionsView.swift
golf-sync-swing/Views/Components/SyncOffsetStrip.swift
golf-sync-swing/Views/Components/ComparisonVideoAreaView.swift
golf-sync-swing/Views/Components/ComparisonTimelineSlider.swift
golf-sync-swing/Views/Components/SkeletonOverlayView.swift
golf-sync-swing/Views/Components/PremiumBadge.swift
golf-sync-swing/Views/Components/FeatureGateModifier.swift
golf-sync-swing/Views/Components/ExportProgressView.swift
golf-sync-swing/Views/Components/SwingThumbnailView.swift
golf-sync-swing/Views/Components/SwingSelectionListView.swift

# Views — onboarding & paywall
golf-sync-swing/Views/Onboarding/OnboardingView.swift
golf-sync-swing/Views/Onboarding/OnboardingPageView.swift
golf-sync-swing/Views/Onboarding/OnboardingFeature.swift
golf-sync-swing/Views/Paywall/AppPaywallView.swift
golf-sync-swing/Views/Paywall/PaywallSource.swift
golf-sync-swing/Views/Paywall/PaywallFeatureRow.swift
golf-sync-swing/Views/Paywall/SubscriptionOptionView.swift

# Views — settings
golf-sync-swing/Views/Settings/SettingsView.swift
golf-sync-swing/Views/Settings/DebugSettingsSection.swift

# Views — recording sub-components (no longer needed)
golf-sync-swing/Views/Recording/Components/SwingAttemptCard.swift
golf-sync-swing/Views/Recording/Components/RecordingTipsSheet.swift
golf-sync-swing/Views/Recording/Components/CameraTipsOverlay.swift
golf-sync-swing/Views/Recording/Components/SpeedButton.swift
golf-sync-swing/Views/Recording/Components/RecordingOverlayView.swift
golf-sync-swing/Views/Recording/Components/SkeletonToggleButton.swift

# Services — purchase, onboarding, review, export, import, storage, screenshots
golf-sync-swing/Services/PurchaseService.swift
golf-sync-swing/Services/OnboardingService.swift
golf-sync-swing/Services/ReviewPromptService.swift
golf-sync-swing/Services/VideoExportService.swift
golf-sync-swing/Services/VideoImportService.swift
golf-sync-swing/Services/VideoPathMigrationService.swift
golf-sync-swing/Services/VideoStorageService.swift
golf-sync-swing/Services/ThumbnailService.swift
golf-sync-swing/Services/ScreenshotDataService.swift
golf-sync-swing/Services/ScreenshotModeService.swift
golf-sync-swing/Services/DevVideoPreloader.swift
golf-sync-swing/Services/RecordingSaveService.swift

# Services — old SwingNet detection pipeline (replaced by pose-based)
golf-sync-swing/Services/Detection/SwingNetDetector.swift
golf-sync-swing/Services/Detection/SwingNetInference.swift
golf-sync-swing/Services/Detection/SwingSegmenter.swift
golf-sync-swing/Services/Detection/SwingNetAnalysisRunner.swift
golf-sync-swing/Services/Sync/VideoFrameIterator.swift

# Models — SwiftData models (no database)
golf-sync-swing/Models/SwingVideo.swift
golf-sync-swing/Models/SwingMarker.swift
golf-sync-swing/Models/ComparisonSession.swift
golf-sync-swing/Models/ComparisonMode.swift
golf-sync-swing/Models/SyncTypes.swift
golf-sync-swing/Models/BodyJointMap.swift
golf-sync-swing/Models/SchemaVersioning.swift

# ViewModels — comparison, playback sync
golf-sync-swing/ViewModels/ComparisonViewModel.swift
golf-sync-swing/ViewModels/VideoPlayerViewModel.swift
golf-sync-swing/ViewModels/PlaybackSynchronizer.swift
golf-sync-swing/ViewModels/ManualPlaybackSynchronizer.swift
golf-sync-swing/ViewModels/Recording/FrameProcessingGate.swift
```

Also delete SwingNet.mlmodel if present:
```
golf-sync-swing/SwingNet.mlmodel
```

**Step 1: Delete all listed files**

```bash
# Delete from filesystem — Xcode auto-syncs via PBXFileSystemSynchronizedRootGroup
cd /Users/aleksanderogurtsov/Desktop/test/golf-sync-swing

# Views
rm -f golf-sync-swing/Views/ComparisonView.swift \
  golf-sync-swing/Views/HomeView.swift \
  golf-sync-swing/Views/VideoLibraryView.swift \
  golf-sync-swing/Views/VideoPickerView.swift \
  golf-sync-swing/Views/SingleVideoPlayerView.swift \
  golf-sync-swing/Views/HistoryView.swift \
  golf-sync-swing/Views/SwingEditorSheet.swift \
  golf-sync-swing/Views/VideoPlayerView.swift \
  golf-sync-swing/Views/MainTabView.swift

# View components
rm -f golf-sync-swing/Views/Components/VideoRowView.swift \
  golf-sync-swing/Views/Components/PlayerTopBarView.swift \
  golf-sync-swing/Views/Components/SwingRowView.swift \
  golf-sync-swing/Views/Components/SwingMarkerSlider.swift \
  golf-sync-swing/Views/Components/PlaybackControlsView.swift \
  golf-sync-swing/Views/Components/SwingDetectionPanel.swift \
  golf-sync-swing/Views/Components/AnalysisOverlayView.swift \
  golf-sync-swing/Views/Components/TimelineSlider.swift \
  golf-sync-swing/Views/Components/ComparisonControlsView.swift \
  golf-sync-swing/Views/Components/VideoFloatingActionsView.swift \
  golf-sync-swing/Views/Components/SyncOffsetStrip.swift \
  golf-sync-swing/Views/Components/ComparisonVideoAreaView.swift \
  golf-sync-swing/Views/Components/ComparisonTimelineSlider.swift \
  golf-sync-swing/Views/Components/SkeletonOverlayView.swift \
  golf-sync-swing/Views/Components/PremiumBadge.swift \
  golf-sync-swing/Views/Components/FeatureGateModifier.swift \
  golf-sync-swing/Views/Components/ExportProgressView.swift \
  golf-sync-swing/Views/Components/SwingThumbnailView.swift \
  golf-sync-swing/Views/Components/SwingSelectionListView.swift

# Onboarding & paywall
rm -f golf-sync-swing/Views/Onboarding/OnboardingView.swift \
  golf-sync-swing/Views/Onboarding/OnboardingPageView.swift \
  golf-sync-swing/Views/Onboarding/OnboardingFeature.swift \
  golf-sync-swing/Views/Paywall/AppPaywallView.swift \
  golf-sync-swing/Views/Paywall/PaywallSource.swift \
  golf-sync-swing/Views/Paywall/PaywallFeatureRow.swift \
  golf-sync-swing/Views/Paywall/SubscriptionOptionView.swift

# Settings
rm -f golf-sync-swing/Views/Settings/SettingsView.swift \
  golf-sync-swing/Views/Settings/DebugSettingsSection.swift

# Recording sub-components no longer needed
rm -f golf-sync-swing/Views/Recording/Components/SwingAttemptCard.swift \
  golf-sync-swing/Views/Recording/Components/RecordingTipsSheet.swift \
  golf-sync-swing/Views/Recording/Components/CameraTipsOverlay.swift \
  golf-sync-swing/Views/Recording/Components/SpeedButton.swift \
  golf-sync-swing/Views/Recording/Components/RecordingOverlayView.swift \
  golf-sync-swing/Views/Recording/Components/SkeletonToggleButton.swift

# Services
rm -f golf-sync-swing/Services/PurchaseService.swift \
  golf-sync-swing/Services/OnboardingService.swift \
  golf-sync-swing/Services/ReviewPromptService.swift \
  golf-sync-swing/Services/VideoExportService.swift \
  golf-sync-swing/Services/VideoImportService.swift \
  golf-sync-swing/Services/VideoPathMigrationService.swift \
  golf-sync-swing/Services/VideoStorageService.swift \
  golf-sync-swing/Services/ThumbnailService.swift \
  golf-sync-swing/Services/ScreenshotDataService.swift \
  golf-sync-swing/Services/ScreenshotModeService.swift \
  golf-sync-swing/Services/DevVideoPreloader.swift \
  golf-sync-swing/Services/RecordingSaveService.swift

# Old detection pipeline
rm -f golf-sync-swing/Services/Detection/SwingNetDetector.swift \
  golf-sync-swing/Services/Detection/SwingNetInference.swift \
  golf-sync-swing/Services/Detection/SwingSegmenter.swift \
  golf-sync-swing/Services/Detection/SwingNetAnalysisRunner.swift \
  golf-sync-swing/Services/Sync/VideoFrameIterator.swift

# Models
rm -f golf-sync-swing/Models/SwingVideo.swift \
  golf-sync-swing/Models/SwingMarker.swift \
  golf-sync-swing/Models/ComparisonSession.swift \
  golf-sync-swing/Models/ComparisonMode.swift \
  golf-sync-swing/Models/SyncTypes.swift \
  golf-sync-swing/Models/BodyJointMap.swift \
  golf-sync-swing/Models/SchemaVersioning.swift

# ViewModels
rm -f golf-sync-swing/ViewModels/ComparisonViewModel.swift \
  golf-sync-swing/ViewModels/VideoPlayerViewModel.swift \
  golf-sync-swing/ViewModels/PlaybackSynchronizer.swift \
  golf-sync-swing/ViewModels/ManualPlaybackSynchronizer.swift \
  golf-sync-swing/ViewModels/Recording/FrameProcessingGate.swift

# SwingNet model
rm -f golf-sync-swing/SwingNet.mlmodel

# Old tests
rm -f golf-sync-swingTests/SwingNetDetectorTests.swift

# Clean up empty directories
find golf-sync-swing/Views/Components -type d -empty -delete 2>/dev/null
find golf-sync-swing/Views/Onboarding -type d -empty -delete 2>/dev/null
find golf-sync-swing/Views/Paywall -type d -empty -delete 2>/dev/null
find golf-sync-swing/Views/Settings -type d -empty -delete 2>/dev/null
find golf-sync-swing/Services/Sync -type d -empty -delete 2>/dev/null
find golf-sync-swing/ViewModels/Recording -type d -empty -delete 2>/dev/null
```

**Step 2: Verify deletions**

```bash
find golf-sync-swing -name "*.swift" | wc -l
```

Expected: ~20 files remaining.

---

### Task 2: Simplify app entry point

**Files:**
- Modify: `golf-sync-swing/golf_sync_swingApp.swift`

**Step 1: Rewrite app entry point**

Replace the entire content of `golf_sync_swingApp.swift` with:

```swift
//
//  golf_sync_swingApp.swift
//  golf-sync-swing
//

import SwiftUI

@main
struct golf_sync_swingApp: App {

    var body: some Scene {
        WindowGroup {
            RecordingView()
        }
    }
}
```

**Step 2: Build to verify**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED (there may be build errors from remaining references — fix those in Task 3)

---

### Task 3: Fix remaining compilation errors

After deleting files, references in kept files will break. Fix each broken reference.

**Files likely needing edits:**
- `golf-sync-swing/ViewModels/RecordingViewModel.swift` — remove `SwiftData` import, `RecordingSaveService`, `saveRecording(to:)`, `savedVideo`
- `golf-sync-swing/Views/Recording/RecordingView.swift` — remove `SwiftData` import, `modelContext`, `fullScreenCover`, `RecordingTipsSheet`, review overlay references
- `golf-sync-swing/Views/Recording/Components/RecordingControlsView.swift` — remove `SwiftData` import, `modelContext`, `saveRecording` call
- `golf-sync-swing/Models/RecordingTypes.swift` — keep as-is (no SwiftData deps)
- `golf-sync-swing/Extensions/Color+AppTeal.swift` — remove onboarding/paywall colors

**Step 1: Fix RecordingViewModel.swift**

Remove `import SwiftData`. Remove `saveService` property. Remove `savedVideo` property. Replace `saveRecording(to:)` with a stub. Remove `RecordingSaveService` reference.

```swift
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
import AVFoundation

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
    var pipDisplayMode: PipDisplayMode = .liveCamera
    var isLoadingReplay: Bool = false

    // MARK: - Collaborators

    let cameraService = CameraService()

    private var countdownTask: Task<Void, Never>?

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
        pipDisplayMode = .liveCamera
        state = .recording
    }

    func stopRecording() {
        guard isRecording else { return }
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
        cameraService.stopSession()
    }
}
```

**Step 2: Fix RecordingView.swift**

Remove `SwiftData` import, `modelContext`, `fullScreenCover`, references to deleted components. Replace save button with Photos save (stub for now).

```swift
//
//  RecordingView.swift
//  golf-sync-swing
//
//  Main recording view container. Composes sub-views:
//    RecordingTopBar        - Cancel, timer, swing count
//    RecordingControlsView  - Start/stop/save buttons
//    RecordingPiPView       - Picture-in-picture overlay
//

import SwiftUI
import AVFoundation

struct RecordingView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = RecordingViewModel()
    @State private var showingError = false
    @State private var hasSetupCamera = false
    @State private var isTabVisible = false
    @State private var pipVisible = false

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.ignoresSafeArea()

                mainContentView
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.3), value: viewModel.mainViewShowsReplay)

                if viewModel.state == .idle {
                    PositioningGuideOverlay()
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.3), value: viewModel.state)
                }

                VStack(spacing: 0) {
                    RecordingTopBar(
                        state: viewModel.state,
                        isRecording: viewModel.isRecording,
                        isCountingDown: viewModel.isCountingDown,
                        swingCount: viewModel.swingCount,
                        recordedDuration: viewModel.cameraService.recordedDuration,
                        onCancel: viewModel.cancel
                    )

                    Spacer()

                    RecordingControlsView(viewModel: viewModel)
                }

                if viewModel.isLoadingReplay {
                    ReplayLoadingOverlay()
                        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoadingReplay)
                }

                if viewModel.isRecording && viewModel.swingCount > 0 {
                    RecordingPiPView(
                        pipDisplayMode: viewModel.pipDisplayMode,
                        sessionConfigurationId: viewModel.cameraService.sessionConfigurationId,
                        captureSession: viewModel.cameraService.captureSession,
                        lastSwing: viewModel.pipSwing,
                        recordingURL: viewModel.recordingURL,
                        playbackSpeed: viewModel.playbackSpeed,
                        onTap: viewModel.swapMainAndPip
                    )
                    .id(viewModel.pipSwing?.id)
                    .scaleEffect(pipVisible ? 1.0 : 0.5)
                    .opacity(pipVisible ? 1.0 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: pipVisible)
                    .onAppear { pipVisible = true }
                    .onDisappear { pipVisible = false }
                }

                if viewModel.isCountingDown {
                    CountdownView(count: viewModel.countdownValue) { viewModel.cancel() }
                }

                if viewModel.isFinalizingVideo {
                    FinalizingVideoOverlay(swingCount: viewModel.swingCount)
                }

                if viewModel.cameraService.isInterrupted {
                    InterruptionOverlay(
                        errorDescription: viewModel.cameraService.currentError?.errorDescription,
                        onResume: viewModel.cameraService.resumeSession
                    )
                }
            }
        }
        .onAppear { handleAppear() }
        .onDisappear { handleDisappear() }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                showingError = false
                viewModel.errorMessage = nil
            }
            if viewModel.cameraService.currentError?.errorDescription?.contains("Settings") == true {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } message: {
            Text(viewModel.errorMessage ?? viewModel.cameraService.currentError?.errorDescription ?? "An unknown error occurred")
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .onChange(of: viewModel.cameraService.currentError) { _, newError in
            if newError != nil { showingError = true }
        }
        .onChange(of: viewModel.errorMessage) { _, newError in
            if newError != nil { showingError = true }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContentView: some View {
        if viewModel.mainViewShowsReplay, let swing = viewModel.pipSwing, let url = viewModel.recordingURL {
            SwingReplayView(
                videoURL: url,
                startTime: swing.startTime,
                endTime: swing.endTime,
                playbackSpeed: viewModel.playbackSpeed,
                onLoaded: viewModel.replayDidLoad
            )
            .id("main-replay-\(swing.id)")
            .transition(.opacity)
        } else {
            CameraPreviewView(session: viewModel.cameraService.captureSession)
                .id("main-camera-\(viewModel.cameraService.sessionConfigurationId)")
                .transition(.opacity)
        }
    }

    // MARK: - Lifecycle

    private func handleAppear() {
        isTabVisible = true
        Task {
            let granted = await viewModel.cameraService.requestPermissions()
            if granted {
                if !hasSetupCamera {
                    viewModel.cameraService.setupSession(position: .front, frameRate: 30)
                    hasSetupCamera = true
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if !viewModel.cameraService.isSessionRunning && !viewModel.isRecording {
                    viewModel.cameraService.resumeSession()
                }
            }
        }
    }

    private func handleDisappear() {
        isTabVisible = false
        if !viewModel.isRecording { viewModel.cameraService.pauseSession() }
    }

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            if !viewModel.isRecording { viewModel.cameraService.pauseSession() }
        case .active:
            if isTabVisible && !viewModel.cameraService.isSessionRunning && !viewModel.isRecording {
                viewModel.cameraService.resumeSession()
            }
        case .inactive: break
        @unknown default: break
        }
    }
}

// MARK: - Supporting Overlays

private struct ReplayLoadingOverlay: View {
    var body: some View {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
            .overlay {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
    }
}

private struct FinalizingVideoOverlay: View {
    let swingCount: Int

    var body: some View {
        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Finalizing...")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
    }
}

private struct InterruptionOverlay: View {
    let errorDescription: String?
    let onResume: () -> Void

    var body: some View {
        Color.black.opacity(0.7)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(errorDescription ?? "Recording interrupted")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("Resume", action: onResume)
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
    }
}

#Preview {
    RecordingView()
}
```

**Step 3: Fix RecordingControlsView.swift**

Remove `SwiftData`, simplify save button to delete-only for now (Photos save comes in Phase 3).

```swift
//
//  RecordingControlsView.swift
//  golf-sync-swing
//
//  Bottom controls for recording view: start/stop buttons.
//

import SwiftUI

struct RecordingControlsView: View {
    @Bindable var viewModel: RecordingViewModel

    var body: some View {
        VStack(spacing: 20) {
            if viewModel.state == .idle {
                startRecordingButton
            } else if viewModel.isRecording {
                stopRecordingButton
            } else if viewModel.isReviewing {
                reviewingButtons
            }
        }
        .padding(.bottom, 100)
    }

    // MARK: - Button Variants

    private var startRecordingButton: some View {
        Button(action: viewModel.startRecording) {
            Text("Start Recording")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.fairwayGreen)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 40)
    }

    private var stopRecordingButton: some View {
        Button(action: viewModel.stopRecording) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 70, height: 70)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.flagRed)
                    .frame(width: 30, height: 30)
            }
        }
    }

    private var reviewingButtons: some View {
        HStack(spacing: 20) {
            Button(action: viewModel.deleteRecording) {
                Text("Delete")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.flagRed.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Button(action: viewModel.deleteRecording) {
                Text("Save to Photos")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.fairwayGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(.horizontal, 40)
    }
}
```

**Step 4: Simplify Color+AppTeal.swift**

Remove onboarding/paywall colors. Keep only the core theme colors.

```swift
//
//  Color+GolfTheme.swift
//  golf-sync-swing
//
//  Fairway design theme — premium golf club aesthetic.
//

import SwiftUI

extension Color {
    // MARK: - Primary Greens

    static let fairwayGreen = Color(red: 0.176, green: 0.416, blue: 0.31)
    static let pineGreen    = Color(red: 0.106, green: 0.263, blue: 0.196)
    static let mintMist     = Color(red: 0.847, green: 0.953, blue: 0.863)

    // MARK: - Warm Accents

    static let sand         = Color(red: 0.831, green: 0.639, blue: 0.451)
    static let sandLight    = Color(red: 0.996, green: 0.98, blue: 0.878)
    static let ivory        = Color(red: 0.992, green: 0.988, blue: 0.98)

    // MARK: - Semantic

    static let charcoal     = Color(red: 0.169, green: 0.176, blue: 0.169)
    static let flagRed      = Color(red: 0.757, green: 0.161, blue: 0.18)

    // MARK: - Backward Compatibility

    static let appTeal = fairwayGreen
}
```

**Step 5: Remove RevenueCat from Package.swift / SPM**

```bash
# Check for Package.swift or SPM references
ls golf-sync-swing.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/
```

Remove the RevenueCat package dependency from Xcode project settings (may need manual Xcode removal or editing the project file).

**Step 6: Build**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED

**Step 7: Commit**

```bash
git add -A
git commit -m "refactor: strip app to minimalist smart golf camera

Remove ~52 files: comparison views, paywall, onboarding, SwiftData
models, video management services, old SwingNet detection pipeline.
App entry point now opens directly to RecordingView.
Camera pipeline (6 files) and recording UI kept intact."
```

---

## Phase 2: Detection Pipeline (New files — pose-based real-time detection)

### Task 4: Create PoseFrame model

**Files:**
- Create: `golf-sync-swing/Models/PoseFrame.swift`

**Step 1: Create PoseFrame**

This is the data type that flows through the entire detection pipeline. Each frame from VNDetectHumanBodyPoseRequest produces one PoseFrame.

```swift
//
//  PoseFrame.swift
//  golf-sync-swing
//
//  A single frame of body pose data extracted from Vision.
//  Flows through the detection pipeline: PoseDetector → SwingClassifier/PoseHeuristics → SwingStateMachine.
//

import Foundation
import Vision

struct PoseFrame: Sendable {
    let timestamp: TimeInterval
    let joints: [VNHumanBodyPoseObservation.JointName: JointPosition]

    struct JointPosition: Sendable {
        let x: CGFloat
        let y: CGFloat
        let confidence: Float
    }
}

// MARK: - Convenience Accessors

extension PoseFrame {

    func joint(_ name: VNHumanBodyPoseObservation.JointName) -> JointPosition? {
        joints[name]
    }

    var leftWrist: JointPosition? { joint(.leftWrist) }
    var rightWrist: JointPosition? { joint(.rightWrist) }
    var leftShoulder: JointPosition? { joint(.leftShoulder) }
    var rightShoulder: JointPosition? { joint(.rightShoulder) }
    var leftHip: JointPosition? { joint(.leftHip) }
    var rightHip: JointPosition? { joint(.rightHip) }
    var neck: JointPosition? { joint(.neck) }

    /// The lowest wrist y-position (Vision: 0=bottom, 1=top).
    /// Returns the wrist with smaller y value (closer to ground).
    var lowestWristY: CGFloat? {
        let candidates = [leftWrist, rightWrist].compactMap { $0 }
            .filter { $0.confidence > 0.3 }
        return candidates.map(\.y).min()
    }

    /// Hip center x-coordinate (average of both hips).
    var hipCenterX: CGFloat? {
        guard let left = leftHip, let right = rightHip,
              left.confidence > 0.3, right.confidence > 0.3 else { return nil }
        return (left.x + right.x) / 2.0
    }

    /// Shoulder rotation angle in radians (atan2 of shoulder line).
    var shoulderAngle: CGFloat? {
        guard let left = leftShoulder, let right = rightShoulder,
              left.confidence > 0.3, right.confidence > 0.3 else { return nil }
        return atan2(right.y - left.y, right.x - left.x)
    }
}
```

**Step 2: Build**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add golf-sync-swing/Models/PoseFrame.swift
git commit -m "feat(detection): add PoseFrame model for pose data pipeline"
```

---

### Task 5: Create SwingEvent model

**Files:**
- Create: `golf-sync-swing/Models/SwingEvent.swift`

**Step 1: Create SwingEvent**

The output type shared by both detection strategies. The SwingStateMachine consumes these.

```swift
//
//  SwingEvent.swift
//  golf-sync-swing
//
//  Events emitted by detection strategies (SwingClassifier, PoseHeuristics).
//  Consumed by SwingStateMachine.
//

import Foundation

enum SwingEvent: Sendable {
    case swingDetected(confidence: Double, timestamp: TimeInterval)
    case noSwing
}
```

**Step 2: Build and commit**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
git add golf-sync-swing/Models/SwingEvent.swift
git commit -m "feat(detection): add SwingEvent model"
```

---

### Task 6: Create PoseDetector (VNSequenceRequestHandler + ring buffer)

**Files:**
- Create: `golf-sync-swing/Services/Detection/PoseDetector.swift`
- Test: `golf-sync-swingTests/PoseDetectorTests.swift`

**Step 1: Write the failing test**

```swift
//
//  PoseDetectorTests.swift
//  golf-sync-swingTests
//

import Testing
import Vision
@testable import golf_sync_swing

struct PoseDetectorTests {

    @Test("Ring buffer maintains correct size")
    func ringBufferSize() {
        let detector = PoseDetector(bufferCapacity: 5)
        let emptyFrame = PoseFrame(timestamp: 0, joints: [:])

        for i in 0..<10 {
            detector.appendToBuffer(emptyFrame)
        }

        #expect(detector.bufferCount == 5)
    }

    @Test("Ring buffer returns frames in chronological order")
    func ringBufferOrder() {
        let detector = PoseDetector(bufferCapacity: 3)

        for i in 0..<5 {
            let frame = PoseFrame(timestamp: TimeInterval(i), joints: [:])
            detector.appendToBuffer(frame)
        }

        let frames = detector.recentFrames(count: 3)
        #expect(frames.count == 3)
        #expect(frames[0].timestamp == 2.0)
        #expect(frames[1].timestamp == 3.0)
        #expect(frames[2].timestamp == 4.0)
    }

    @Test("Extract pose from static image produces joints")
    func extractPoseFromImage() throws {
        // Create a 160x160 blank pixel buffer
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 160, 160, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        guard let buffer = pixelBuffer else {
            Issue.record("Failed to create pixel buffer")
            return
        }

        let detector = PoseDetector()
        let frame = detector.extractPose(from: buffer, at: 0.5)

        // Blank image produces no joints — that's fine
        #expect(frame.timestamp == 0.5)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/PoseDetectorTests test 2>&1 | tail -10
```

Expected: FAIL (PoseDetector not defined)

**Step 3: Implement PoseDetector**

```swift
//
//  PoseDetector.swift
//  golf-sync-swing
//
//  Extracts body pose from camera frames using VNSequenceRequestHandler
//  and maintains a ring buffer of recent PoseFrames.
//
//  VNSequenceRequestHandler provides temporal smoothing between frames,
//  reducing joint position jitter during fast motion (downswing).
//

import CoreVideo
import Vision
import os

final class PoseDetector: @unchecked Sendable {

    private let sequenceHandler = VNSequenceRequestHandler()
    private let bufferCapacity: Int
    private var buffer: [PoseFrame]
    private var writeIndex: Int = 0
    private var totalWritten: Int = 0
    private let lock = NSLock()
    private let minimumConfidence: Float = 0.1

    init(bufferCapacity: Int = 90) {
        self.bufferCapacity = bufferCapacity
        self.buffer = []
        self.buffer.reserveCapacity(bufferCapacity)
    }

    // MARK: - Pose Extraction

    func extractPose(from pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) -> PoseFrame {
        let request = VNDetectHumanBodyPoseRequest()
        request.maximumObservations = 1

        do {
            try sequenceHandler.perform([request], on: pixelBuffer)
        } catch {
            AppLogger.detection.debug("Pose extraction failed: \(error.localizedDescription)")
            return PoseFrame(timestamp: timestamp, joints: [:])
        }

        guard let observation = request.results?.first else {
            return PoseFrame(timestamp: timestamp, joints: [:])
        }

        let joints = extractJoints(from: observation)
        return PoseFrame(timestamp: timestamp, joints: joints)
    }

    func processFrame(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> PoseFrame {
        let frame = extractPose(from: pixelBuffer, at: timestamp)
        appendToBuffer(frame)
        return frame
    }

    // MARK: - Ring Buffer

    func appendToBuffer(_ frame: PoseFrame) {
        lock.lock()
        defer { lock.unlock() }

        if buffer.count < bufferCapacity {
            buffer.append(frame)
        } else {
            buffer[writeIndex] = frame
        }

        writeIndex = (writeIndex + 1) % bufferCapacity
        totalWritten += 1
    }

    var bufferCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    func recentFrames(count: Int) -> [PoseFrame] {
        lock.lock()
        defer { lock.unlock() }

        let available = min(count, buffer.count)
        guard available > 0 else { return [] }

        var result: [PoseFrame] = []
        result.reserveCapacity(available)

        let startOffset = buffer.count < bufferCapacity
            ? max(0, buffer.count - available)
            : (writeIndex - available + bufferCapacity) % bufferCapacity

        for i in 0..<available {
            let index = buffer.count < bufferCapacity
                ? startOffset + i
                : (startOffset + i) % bufferCapacity
            result.append(buffer[index])
        }

        return result
    }

    func clearBuffer() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
        writeIndex = 0
        totalWritten = 0
    }

    // MARK: - Joint Extraction

    private static let trackedJoints: [VNHumanBodyPoseObservation.JointName] = [
        .leftWrist, .rightWrist,
        .leftShoulder, .rightShoulder,
        .leftHip, .rightHip,
        .leftElbow, .rightElbow,
        .neck,
        .leftAnkle, .rightAnkle
    ]

    private func extractJoints(from observation: VNHumanBodyPoseObservation) -> [VNHumanBodyPoseObservation.JointName: PoseFrame.JointPosition] {
        var joints: [VNHumanBodyPoseObservation.JointName: PoseFrame.JointPosition] = [:]

        for jointName in Self.trackedJoints {
            guard let point = try? observation.recognizedPoint(jointName),
                  point.confidence > minimumConfidence else {
                continue
            }

            joints[jointName] = PoseFrame.JointPosition(
                x: point.location.x,
                y: point.location.y,
                confidence: point.confidence
            )
        }

        return joints
    }
}
```

**Step 4: Run tests**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/PoseDetectorTests test 2>&1 | tail -10
```

Expected: All 3 tests PASS

**Step 5: Commit**

```bash
git add golf-sync-swing/Services/Detection/PoseDetector.swift golf-sync-swingTests/PoseDetectorTests.swift
git commit -m "feat(detection): add PoseDetector with VNSequenceRequestHandler and ring buffer"
```

---

### Task 7: Create ImpactDetector (wrist y-minimum)

**Files:**
- Create: `golf-sync-swing/Services/Detection/ImpactDetector.swift`
- Test: `golf-sync-swingTests/ImpactDetectorTests.swift`

**Step 1: Write the failing test**

```swift
//
//  ImpactDetectorTests.swift
//  golf-sync-swingTests
//

import Testing
import Vision
@testable import golf_sync_swing

struct ImpactDetectorTests {

    @Test("Finds frame with lowest wrist y-position")
    func findsLowestWristY() {
        let detector = ImpactDetector()

        let frames = (0..<10).map { i -> PoseFrame in
            // Simulate V-shaped wrist trajectory: lowest at frame 5
            let y = abs(CGFloat(i) - 5.0) * 0.1 + 0.2
            let wrist = PoseFrame.JointPosition(x: 0.5, y: y, confidence: 0.8)
            return PoseFrame(
                timestamp: TimeInterval(i) * 0.033,
                joints: [.leftWrist: wrist]
            )
        }

        let impactTime = detector.findImpactTime(in: frames)
        let expectedTime = 5.0 * 0.033

        #expect(impactTime != nil)
        #expect(abs(impactTime! - expectedTime) < 0.001)
    }

    @Test("Returns nil when no wrist data available")
    func noWristData() {
        let detector = ImpactDetector()

        let frames = (0..<5).map { i in
            PoseFrame(timestamp: TimeInterval(i) * 0.033, joints: [:])
        }

        let impactTime = detector.findImpactTime(in: frames)
        #expect(impactTime == nil)
    }

    @Test("Picks lower wrist for handedness detection")
    func picksLowerWrist() {
        let detector = ImpactDetector()

        let leftWrist = PoseFrame.JointPosition(x: 0.3, y: 0.4, confidence: 0.8)
        let rightWrist = PoseFrame.JointPosition(x: 0.7, y: 0.2, confidence: 0.8)
        let frame = PoseFrame(
            timestamp: 1.0,
            joints: [.leftWrist: leftWrist, .rightWrist: rightWrist]
        )

        let impactTime = detector.findImpactTime(in: [frame])

        // Right wrist is lower (y=0.2), so this frame is impact
        #expect(impactTime == 1.0)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/ImpactDetectorTests test 2>&1 | tail -10
```

Expected: FAIL (ImpactDetector not defined)

**Step 3: Implement ImpactDetector**

```swift
//
//  ImpactDetector.swift
//  golf-sync-swing
//
//  Finds the impact frame within a detected swing by searching for the
//  frame where the lead wrist reaches its lowest y-position.
//
//  The lead wrist reaches its lowest point at ball impact (biomechanical
//  fact). Both wrists are checked — the one with the lower y-minimum
//  determines impact (handles left/right-handed golfers).
//

import Foundation
import Vision

protocol ImpactDetecting: Sendable {
    func findImpactTime(in frames: [PoseFrame]) -> TimeInterval?
}

struct ImpactDetector: ImpactDetecting {

    private let minimumConfidence: Float = 0.3

    func findImpactTime(in frames: [PoseFrame]) -> TimeInterval? {
        var bestTime: TimeInterval?
        var lowestY: CGFloat = .greatestFiniteMagnitude

        for frame in frames {
            guard let wristY = lowestWristY(in: frame) else { continue }

            if wristY < lowestY {
                lowestY = wristY
                bestTime = frame.timestamp
            }
        }

        return bestTime
    }

    private func lowestWristY(in frame: PoseFrame) -> CGFloat? {
        let wristNames: [VNHumanBodyPoseObservation.JointName] = [.leftWrist, .rightWrist]

        let yValues = wristNames.compactMap { name -> CGFloat? in
            guard let joint = frame.joint(name),
                  joint.confidence > minimumConfidence else { return nil }
            return joint.y
        }

        return yValues.min()
    }
}
```

**Step 4: Run tests**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/ImpactDetectorTests test 2>&1 | tail -10
```

Expected: All 3 tests PASS

**Step 5: Commit**

```bash
git add golf-sync-swing/Services/Detection/ImpactDetector.swift golf-sync-swingTests/ImpactDetectorTests.swift
git commit -m "feat(detection): add ImpactDetector — wrist y-minimum for impact frame"
```

---

### Task 8: Create SwingStateMachine

**Files:**
- Create: `golf-sync-swing/Services/Detection/SwingStateMachine.swift`
- Test: `golf-sync-swingTests/SwingStateMachineTests.swift`

**Step 1: Write the failing test**

```swift
//
//  SwingStateMachineTests.swift
//  golf-sync-swingTests
//

import Testing
@testable import golf_sync_swing

struct SwingStateMachineTests {

    @Test("Starts in idle state")
    func startsIdle() {
        let machine = SwingStateMachine()
        #expect(machine.currentState == .idle)
    }

    @Test("Transitions to swingDetected on swing event")
    func detectsSwing() {
        let machine = SwingStateMachine()
        let event = SwingEvent.swingDetected(confidence: 0.8, timestamp: 1.5)
        let result = machine.handle(event: event)

        #expect(machine.currentState == .swingDetected)
        #expect(result != nil)
        #expect(result?.confidence == 0.8)
        #expect(result?.detectionTimestamp == 1.5)
    }

    @Test("Ignores swings during cooldown")
    func cooldownPreventsRetrigger() {
        let machine = SwingStateMachine(cooldownDuration: 2.0)
        _ = machine.handle(event: .swingDetected(confidence: 0.8, timestamp: 1.0))
        machine.transitionToReplay(impactTime: 1.0, startTime: 0.5, endTime: 2.0)

        // Try again within cooldown
        let result = machine.handle(event: .swingDetected(confidence: 0.9, timestamp: 2.5))
        #expect(result == nil)
        #expect(machine.currentState == .cooldown)
    }

    @Test("Returns to idle after cooldown expires")
    func cooldownExpires() {
        let machine = SwingStateMachine(cooldownDuration: 2.0)
        _ = machine.handle(event: .swingDetected(confidence: 0.8, timestamp: 1.0))
        machine.transitionToReplay(impactTime: 1.0, startTime: 0.5, endTime: 2.0)

        // Try after cooldown
        let result = machine.handle(event: .swingDetected(confidence: 0.9, timestamp: 5.0))
        #expect(result != nil)
        #expect(machine.currentState == .swingDetected)
    }

    @Test("noSwing event does not change idle state")
    func noSwingStaysIdle() {
        let machine = SwingStateMachine()
        let result = machine.handle(event: .noSwing)
        #expect(result == nil)
        #expect(machine.currentState == .idle)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/SwingStateMachineTests test 2>&1 | tail -10
```

Expected: FAIL

**Step 3: Implement SwingStateMachine**

```swift
//
//  SwingStateMachine.swift
//  golf-sync-swing
//
//  Manages swing detection state transitions.
//  States: idle → swingDetected → replayReady → cooldown → idle
//
//  The cooldown window (2s default) prevents re-triggering on the
//  follow-through motion immediately after a detected swing.
//

import Foundation
import os

struct SwingDetection: Sendable {
    let confidence: Double
    let detectionTimestamp: TimeInterval
}

final class SwingStateMachine: @unchecked Sendable {

    enum State: Equatable, Sendable {
        case idle
        case swingDetected
        case replayReady
        case cooldown
    }

    private(set) var currentState: State = .idle
    private let cooldownDuration: TimeInterval
    private var cooldownStartTime: TimeInterval = 0
    private let lock = NSLock()

    init(cooldownDuration: TimeInterval = 2.0) {
        self.cooldownDuration = cooldownDuration
    }

    // MARK: - Event Handling

    func handle(event: SwingEvent) -> SwingDetection? {
        lock.lock()
        defer { lock.unlock() }

        switch event {
        case .swingDetected(let confidence, let timestamp):
            return handleSwingDetected(confidence: confidence, timestamp: timestamp)
        case .noSwing:
            return nil
        }
    }

    func transitionToReplay(impactTime: TimeInterval, startTime: TimeInterval, endTime: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        currentState = .cooldown
        cooldownStartTime = endTime
        AppLogger.detection.info("SwingStateMachine: → cooldown (until \(String(format: "%.1f", endTime + cooldownDuration))s)")
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        currentState = .idle
        cooldownStartTime = 0
    }

    // MARK: - Private

    private func handleSwingDetected(confidence: Double, timestamp: TimeInterval) -> SwingDetection? {
        switch currentState {
        case .idle:
            currentState = .swingDetected
            AppLogger.detection.info("SwingStateMachine: → swingDetected (conf=\(String(format: "%.2f", confidence)) at \(String(format: "%.2f", timestamp))s)")
            return SwingDetection(confidence: confidence, detectionTimestamp: timestamp)

        case .cooldown:
            let elapsed = timestamp - cooldownStartTime
            guard elapsed >= cooldownDuration else { return nil }

            currentState = .swingDetected
            AppLogger.detection.info("SwingStateMachine: cooldown expired → swingDetected")
            return SwingDetection(confidence: confidence, detectionTimestamp: timestamp)

        case .swingDetected, .replayReady:
            return nil
        }
    }
}
```

**Step 4: Run tests**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/SwingStateMachineTests test 2>&1 | tail -10
```

Expected: All 5 tests PASS

**Step 5: Commit**

```bash
git add golf-sync-swing/Services/Detection/SwingStateMachine.swift golf-sync-swingTests/SwingStateMachineTests.swift
git commit -m "feat(detection): add SwingStateMachine with cooldown"
```

---

### Task 9: Create PoseHeuristics (fallback detection strategy)

**Files:**
- Create: `golf-sync-swing/Services/Detection/PoseHeuristics.swift`
- Test: `golf-sync-swingTests/PoseHeuristicsTests.swift`

**Step 1: Write the failing test**

```swift
//
//  PoseHeuristicsTests.swift
//  golf-sync-swingTests
//

import Testing
import Vision
@testable import golf_sync_swing

struct PoseHeuristicsTests {

    @Test("Detects swing from high wrist velocity")
    func detectsSwingFromWristVelocity() {
        let heuristics = PoseHeuristics()

        // Simulate rapid downward wrist movement over 6 frames (200ms)
        var frames: [PoseFrame] = []
        for i in 0..<15 {
            let y: CGFloat
            if i < 5 {
                y = 0.7 // Address position
            } else if i < 11 {
                y = 0.7 - CGFloat(i - 5) * 0.08 // Rapid descent
            } else {
                y = 0.25 + CGFloat(i - 11) * 0.05 // Recovery
            }

            let wrist = PoseFrame.JointPosition(x: 0.5, y: y, confidence: 0.8)
            let hip = PoseFrame.JointPosition(x: 0.5, y: 0.55, confidence: 0.9)
            frames.append(PoseFrame(
                timestamp: TimeInterval(i) * 0.033,
                joints: [.leftWrist: wrist, .leftHip: hip, .rightHip: hip]
            ))
        }

        let event = heuristics.analyze(frames: frames)

        switch event {
        case .swingDetected: break // Expected
        case .noSwing: Issue.record("Expected swing detection")
        }
    }

    @Test("Does not detect swing from slow movement")
    func noDetectionFromSlowMovement() {
        let heuristics = PoseHeuristics()

        // Simulate slow arm raise — not a swing
        let frames = (0..<15).map { i -> PoseFrame in
            let y = 0.5 + CGFloat(i) * 0.01
            let wrist = PoseFrame.JointPosition(x: 0.5, y: y, confidence: 0.8)
            let hip = PoseFrame.JointPosition(x: 0.5, y: 0.55, confidence: 0.9)
            return PoseFrame(
                timestamp: TimeInterval(i) * 0.033,
                joints: [.leftWrist: wrist, .leftHip: hip, .rightHip: hip]
            )
        }

        let event = heuristics.analyze(frames: frames)

        switch event {
        case .swingDetected: Issue.record("Should not detect slow movement as swing")
        case .noSwing: break // Expected
        }
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/PoseHeuristicsTests test 2>&1 | tail -10
```

Expected: FAIL

**Step 3: Implement PoseHeuristics**

```swift
//
//  PoseHeuristics.swift
//  golf-sync-swing
//
//  Fallback swing detection using body pose heuristics.
//  Detects a golf swing by analyzing:
//    1. Wrist velocity relative to hip center (downswing speed)
//    2. Downward trajectory (wrist moves below hip level)
//
//  This is the fallback strategy when the Create ML classifier is unavailable.
//  It uses the same PoseFrame input and produces the same SwingEvent output.
//

import Foundation
import Vision
import os

protocol SwingDetecting: Sendable {
    func analyze(frames: [PoseFrame]) -> SwingEvent
}

struct PoseHeuristics: SwingDetecting {

    /// Minimum wrist velocity (normalized units per second) to consider as swing
    private let velocityThreshold: CGFloat = 0.8

    /// Minimum number of frames showing rapid descent
    private let minimumDescentFrames: Int = 3

    func analyze(frames: [PoseFrame]) -> SwingEvent {
        guard frames.count >= 6 else { return .noSwing }

        let velocities = computeWristVelocities(frames: frames)
        let descentCount = velocities.filter { $0 < -velocityThreshold }.count

        guard descentCount >= minimumDescentFrames else { return .noSwing }

        let peakVelocityIndex = velocities.enumerated()
            .min(by: { $0.element < $1.element })?.offset ?? 0
        let timestamp = frames[min(peakVelocityIndex + 1, frames.count - 1)].timestamp
        let confidence = min(1.0, Double(descentCount) / 6.0)

        AppLogger.detection.info("PoseHeuristics: swing detected (descent=\(descentCount) frames, conf=\(String(format: "%.2f", confidence)))")
        return .swingDetected(confidence: confidence, timestamp: timestamp)
    }

    // MARK: - Velocity Computation

    private func computeWristVelocities(frames: [PoseFrame]) -> [CGFloat] {
        guard frames.count >= 2 else { return [] }

        return (1..<frames.count).map { i in
            let prev = frames[i - 1]
            let curr = frames[i]

            let dt = curr.timestamp - prev.timestamp
            guard dt > 0 else { return 0 }

            let prevY = leadWristY(in: prev)
            let currY = leadWristY(in: curr)
            guard let py = prevY, let cy = currY else { return 0 }

            // Negative = downward (y decreases in Vision coordinates)
            return (cy - py) / dt
        }
    }

    private func leadWristY(in frame: PoseFrame) -> CGFloat? {
        let wrists: [VNHumanBodyPoseObservation.JointName] = [.leftWrist, .rightWrist]
        return wrists.compactMap { frame.joint($0) }
            .filter { $0.confidence > 0.3 }
            .map(\.y)
            .min()
    }
}
```

**Step 4: Run tests**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/PoseHeuristicsTests test 2>&1 | tail -10
```

Expected: All 2 tests PASS

**Step 5: Commit**

```bash
git add golf-sync-swing/Services/Detection/PoseHeuristics.swift golf-sync-swingTests/PoseHeuristicsTests.swift
git commit -m "feat(detection): add PoseHeuristics fallback strategy"
```

---

### Task 10: Create SwingClassifier stub (Create ML wrapper)

The actual Create ML model is trained separately (Phase 4). This task creates the wrapper that will load and use it, with a protocol so the heuristic fallback can substitute.

**Files:**
- Create: `golf-sync-swing/Services/Detection/SwingClassifier.swift`

**Step 1: Create SwingClassifier**

```swift
//
//  SwingClassifier.swift
//  golf-sync-swing
//
//  Wrapper for the Create ML Action Classifier model.
//  Takes a sliding window of PoseFrames and classifies: swing / not_swing.
//
//  The model is trained on GolfDB pose data (2,561 swing + 2,561 not_swing clips).
//  If the model is unavailable, returns nil so the caller can fall back to PoseHeuristics.
//

import CoreML
import Vision
import os

final class SwingClassifier: SwingDetecting, @unchecked Sendable {

    private let model: MLModel?
    private let windowSize: Int

    init(windowSize: Int = 15) {
        self.windowSize = windowSize
        self.model = Self.loadModel()
    }

    // MARK: - SwingDetecting

    func analyze(frames: [PoseFrame]) -> SwingEvent {
        guard let model else {
            AppLogger.detection.debug("SwingClassifier: no model available, skipping")
            return .noSwing
        }

        guard frames.count >= windowSize else { return .noSwing }

        let recentFrames = Array(frames.suffix(windowSize))

        // TODO: Build MLMultiArray from pose data and run prediction
        // For now, delegate to heuristics until model is trained
        AppLogger.detection.debug("SwingClassifier: model loaded but prediction not yet implemented")
        return .noSwing
    }

    // MARK: - Model Loading

    private static func loadModel() -> MLModel? {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        // Look for GolfSwingClassifier.mlmodelc in bundle
        guard let url = Bundle.main.url(forResource: "GolfSwingClassifier", withExtension: "mlmodelc") else {
            AppLogger.detection.info("SwingClassifier: model not found in bundle (expected during development)")
            return nil
        }

        do {
            let model = try MLModel(contentsOf: url, configuration: config)
            AppLogger.detection.info("SwingClassifier: model loaded successfully")
            return model
        } catch {
            AppLogger.detection.error("SwingClassifier: failed to load model: \(error.localizedDescription)")
            return nil
        }
    }

    var isAvailable: Bool { model != nil }
}
```

**Step 2: Build and commit**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
git add golf-sync-swing/Services/Detection/SwingClassifier.swift
git commit -m "feat(detection): add SwingClassifier stub for Create ML Action Classifier"
```

---

### Task 11: Create DetectionOrchestrator (wires pipeline together)

**Files:**
- Create: `golf-sync-swing/Services/Detection/DetectionOrchestrator.swift`

This is the coordinator that connects CameraService's frame callback → PoseDetector → classifier/heuristics → SwingStateMachine → emit SwingClip.

**Step 1: Create DetectionOrchestrator**

```swift
//
//  DetectionOrchestrator.swift
//  golf-sync-swing
//
//  Wires the real-time detection pipeline:
//    CameraService.onFrameCaptured → PoseDetector → SwingClassifier/PoseHeuristics
//    → SwingStateMachine → ImpactDetector → SwingClip
//
//  Processes every frame on a background queue. Emits detected swings
//  via the onSwingDetected callback.
//

import CoreVideo
import Foundation
import os

final class DetectionOrchestrator: @unchecked Sendable {

    // MARK: - Callbacks

    var onSwingDetected: ((SwingClip) -> Void)?

    // MARK: - Collaborators

    private let poseDetector: PoseDetector
    private let classifier: SwingClassifier
    private let heuristics: PoseHeuristics
    private let stateMachine: SwingStateMachine
    private let impactDetector: ImpactDetecting

    // MARK: - Configuration

    private let analysisWindowSize: Int = 15
    private let clipPaddingBefore: TimeInterval = 0.5
    private let clipPaddingAfter: TimeInterval = 0.5

    // MARK: - State

    private var isActive = false
    private let processingQueue = DispatchQueue(
        label: "com.golfsync.detection",
        qos: .userInitiated
    )

    init(
        poseDetector: PoseDetector = PoseDetector(),
        classifier: SwingClassifier = SwingClassifier(),
        heuristics: PoseHeuristics = PoseHeuristics(),
        stateMachine: SwingStateMachine = SwingStateMachine(),
        impactDetector: ImpactDetecting = ImpactDetector()
    ) {
        self.poseDetector = poseDetector
        self.classifier = classifier
        self.heuristics = heuristics
        self.stateMachine = stateMachine
        self.impactDetector = impactDetector
    }

    // MARK: - Lifecycle

    func start() {
        isActive = true
        poseDetector.clearBuffer()
        stateMachine.reset()
        AppLogger.detection.info("DetectionOrchestrator: started")
    }

    func stop() {
        isActive = false
        AppLogger.detection.info("DetectionOrchestrator: stopped")
    }

    // MARK: - Frame Processing

    func processFrame(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        guard isActive else { return }

        processingQueue.async { [weak self] in
            self?.handleFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
    }

    private func handleFrame(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        let _ = poseDetector.processFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        let recentFrames = poseDetector.recentFrames(count: analysisWindowSize)

        guard recentFrames.count >= analysisWindowSize else { return }

        let event = detectSwing(in: recentFrames)

        guard let detection = stateMachine.handle(event: event) else { return }

        let swingFrames = poseDetector.recentFrames(count: 90)
        let impactTime = impactDetector.findImpactTime(in: swingFrames) ?? detection.detectionTimestamp

        let startTime = max(0, impactTime - 1.0 - clipPaddingBefore)
        let endTime = impactTime + 0.5 + clipPaddingAfter

        let clip = SwingClip(
            startTime: startTime,
            impactTime: impactTime,
            endTime: endTime,
            confidence: detection.confidence,
            detectionTime: detection.detectionTimestamp
        )

        stateMachine.transitionToReplay(
            impactTime: impactTime,
            startTime: startTime,
            endTime: endTime
        )

        AppLogger.detection.info("Swing detected: impact=\(String(format: "%.2f", impactTime))s, clip=\(String(format: "%.1f", startTime))-\(String(format: "%.1f", endTime))s")

        DispatchQueue.main.async { [weak self] in
            self?.onSwingDetected?(clip)
        }
    }

    // MARK: - Strategy Selection

    private func detectSwing(in frames: [PoseFrame]) -> SwingEvent {
        // Primary: Create ML classifier
        let classifierResult = classifier.analyze(frames: frames)
        if case .swingDetected = classifierResult {
            return classifierResult
        }

        // Fallback: Pose heuristics
        return heuristics.analyze(frames: frames)
    }
}
```

**Step 2: Build**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add golf-sync-swing/Services/Detection/DetectionOrchestrator.swift
git commit -m "feat(detection): add DetectionOrchestrator — wires pose pipeline together"
```

---

## Phase 3: Integration (Wire detection into recording flow + Photos save)

### Task 12: Create PhotosSaveService

**Files:**
- Create: `golf-sync-swing/Services/PhotosSaveService.swift`

**Step 1: Create PhotosSaveService**

```swift
//
//  PhotosSaveService.swift
//  golf-sync-swing
//
//  Saves trimmed swing clips to the Photos library via PHAssetChangeRequest.
//  No internal database. The Photos app is the library.
//

import AVFoundation
import Photos
import os

protocol PhotosSaving: Sendable {
    func saveClip(from sourceURL: URL, startTime: TimeInterval, endTime: TimeInterval) async throws
    func saveFullRecording(from sourceURL: URL) async throws
    static func requestAuthorization() async -> Bool
}

struct PhotosSaveService: PhotosSaving {

    static func requestAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard status != .authorized else { return true }
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return newStatus == .authorized
    }

    func saveClip(from sourceURL: URL, startTime: TimeInterval, endTime: TimeInterval) async throws {
        let asset = AVURLAsset(url: sourceURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let composition = AVMutableComposition()

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
              let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw PhotosSaveError.exportFailed("No video track found")
        }

        let timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )

        try compositionTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        // Add audio if available
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audioCompositionTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw PhotosSaveError.exportFailed("Cannot create export session")
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mov

        await exporter.export()

        guard exporter.status == .completed else {
            throw PhotosSaveError.exportFailed(exporter.error?.localizedDescription ?? "Unknown error")
        }

        try await saveToPhotos(url: outputURL)
        try? FileManager.default.removeItem(at: outputURL)

        AppLogger.detection.info("Saved trimmed clip to Photos (\(String(format: "%.1f", startTime))-\(String(format: "%.1f", endTime))s)")
    }

    func saveFullRecording(from sourceURL: URL) async throws {
        try await saveToPhotos(url: sourceURL)
        AppLogger.detection.info("Saved full recording to Photos")
    }

    private func saveToPhotos(url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

enum PhotosSaveError: LocalizedError {
    case exportFailed(String)
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .exportFailed(let reason): return "Export failed: \(reason)"
        case .authorizationDenied: return "Photos access denied. Please enable in Settings."
        }
    }
}
```

**Step 2: Build and commit**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
git add golf-sync-swing/Services/PhotosSaveService.swift
git commit -m "feat: add PhotosSaveService — save trimmed clips to Photos"
```

---

### Task 13: Wire detection into RecordingViewModel

**Files:**
- Modify: `golf-sync-swing/ViewModels/RecordingViewModel.swift`

**Step 1: Add DetectionOrchestrator and PhotosSaveService**

Add these properties and wire them into the recording lifecycle:

1. Add `detectionOrchestrator` property
2. Add `photosSaveService` property
3. In `beginRecording()`, call `detectionOrchestrator.start()` and set `cameraService.onFrameCaptured`
4. In `stopRecording()`, call `detectionOrchestrator.stop()`
5. Add `saveToPhotos()` method that iterates `detectedSwings` and saves each clip

The key integration point is `setupCallbacks()` — wire `detectionOrchestrator.onSwingDetected` to append to `detectedSwings`.

Add to the class:

```swift
    private let detectionOrchestrator = DetectionOrchestrator()
    private let photosSaveService = PhotosSaveService()
```

In `init()`, after `setupCallbacks()`:

```swift
    detectionOrchestrator.onSwingDetected = { [weak self] clip in
        Task { @MainActor [weak self] in
            self?.detectedSwings.append(clip)
        }
    }
```

In `beginRecording()`, after `state = .recording`:

```swift
    detectionOrchestrator.start()
    cameraService.onFrameCaptured = { [weak self] pixelBuffer, timestamp in
        self?.detectionOrchestrator.processFrame(
            pixelBuffer: pixelBuffer,
            timestamp: CMTimeGetSeconds(timestamp)
        )
    }
```

Add `import CoreMedia` to imports.

In `stopRecording()`, before `cameraService.stopRecording()`:

```swift
    detectionOrchestrator.stop()
    cameraService.onFrameCaptured = nil
```

Replace `deleteRecording()` save stub with actual Photos save:

```swift
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
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
            detectedSwings.removeAll()
            mainViewShowsReplay = false
            isLoadingReplay = false
            replayingSwingIndex = nil
            state = .idle
        } catch {
            errorMessage = error.localizedDescription
            state = .reviewing
        }
    }
```

**Step 2: Update RecordingControlsView save button**

Change the "Save to Photos" button action from `viewModel.deleteRecording` to:

```swift
Button {
    Task { await viewModel.saveToPhotos() }
} label: {
    Text(viewModel.swingCount > 0 ? "Save (\(viewModel.swingCount))" : "Save")
        // ... same styling
}
```

**Step 3: Build**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add golf-sync-swing/ViewModels/RecordingViewModel.swift golf-sync-swing/Views/Recording/Components/RecordingControlsView.swift
git commit -m "feat: wire detection pipeline and Photos save into recording flow"
```

---

### Task 14: Add Photos usage description to Info.plist

**Files:**
- Modify: `golf-sync-swing/Info.plist` (or add to target settings)

**Step 1: Add NSPhotoLibraryAddUsageDescription**

Check if Info.plist exists:
```bash
find golf-sync-swing -name "Info.plist" -not -path "*/Previews/*"
```

Add to the plist (or add via Xcode build settings):
```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save your swing clips to Photos for viewing and comparison in other apps.</string>
```

**Step 2: Build and commit**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
git add -A
git commit -m "feat: add Photos library usage description"
```

---

### Task 15: Clean up — remove PersonCropper and WristRefinementService

These are from the old SwingNet pipeline. The new pipeline uses PoseDetector + ImpactDetector instead.

**Files to delete:**
- `golf-sync-swing/Services/Detection/PersonCropper.swift`
- `golf-sync-swing/Services/Detection/WristRefinementService.swift`

**Step 1: Delete and build**

```bash
rm -f golf-sync-swing/Services/Detection/PersonCropper.swift
rm -f golf-sync-swing/Services/Detection/WristRefinementService.swift
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 2: Commit**

```bash
git add -A
git commit -m "chore: remove PersonCropper and WristRefinementService (replaced by PoseDetector + ImpactDetector)"
```

---

### Task 16: Run all tests

**Step 1: Run full test suite**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -20
```

Expected: All tests pass (PoseDetectorTests, ImpactDetectorTests, SwingStateMachineTests, PoseHeuristicsTests)

**Step 2: Verify file count**

```bash
find golf-sync-swing -name "*.swift" | wc -l
```

Expected: ~20 files

**Step 3: List remaining files**

```bash
find golf-sync-swing -name "*.swift" | sort
```

Expected structure:
```
golf-sync-swing/golf_sync_swingApp.swift
golf-sync-swing/Extensions/Color+AppTeal.swift
golf-sync-swing/Models/PoseFrame.swift
golf-sync-swing/Models/RecordingTypes.swift
golf-sync-swing/Models/SwingEvent.swift
golf-sync-swing/Services/AppLogger.swift
golf-sync-swing/Services/Camera/CameraError.swift
golf-sync-swing/Services/Camera/CameraNotificationHandler.swift
golf-sync-swing/Services/Camera/CameraPermissionManager.swift
golf-sync-swing/Services/Camera/CaptureSessionConfigurator.swift
golf-sync-swing/Services/Camera/RecordingCoordinator.swift
golf-sync-swing/Services/CameraService.swift
golf-sync-swing/Services/Detection/DetectionOrchestrator.swift
golf-sync-swing/Services/Detection/ImpactDetector.swift
golf-sync-swing/Services/Detection/PoseDetector.swift
golf-sync-swing/Services/Detection/PoseHeuristics.swift
golf-sync-swing/Services/Detection/SwingClassifier.swift
golf-sync-swing/Services/Detection/SwingStateMachine.swift
golf-sync-swing/Services/PhotosSaveService.swift
golf-sync-swing/ViewModels/RecordingViewModel.swift
golf-sync-swing/Views/Recording/CameraPreviewView.swift
golf-sync-swing/Views/Recording/Components/DetectionBorderView.swift
golf-sync-swing/Views/Recording/Components/PositioningGuideOverlay.swift
golf-sync-swing/Views/Recording/Components/RecordingControlsView.swift
golf-sync-swing/Views/Recording/Components/RecordingPiPView.swift
golf-sync-swing/Views/Recording/Components/RecordingTopBar.swift
golf-sync-swing/Views/Recording/CountdownView.swift
golf-sync-swing/Views/Recording/RecordingView.swift
golf-sync-swing/Views/Recording/SwingReplayView.swift
```

---

## Phase 4: Train the Create ML Action Classifier (external to Xcode project)

### Task 17: Extract binary training data from GolfDB

**Files:**
- Modify (or create): `ml-training/extract_binary_dataset.py`

This runs in the `ml-training/venv312/` Python 3.12 environment. It extracts 15-frame clips from GolfDB labeled as `swing` or `not_swing`.

**Step 1: Create extraction script**

```python
#!/usr/bin/env python3
"""
Extract binary swing/not_swing training clips from GolfDB for Create ML Action Classifier.

Output structure:
  training_data_binary/
    swing/          (2,561 clips, 15 frames each)
    not_swing/      (2,561 clips, balanced downsample)

Create ML requires clips as .mov files in labeled directories.
"""

import cv2
import json
import os
import random
import subprocess
import sys
from pathlib import Path

# GolfDB annotation mapping
# Events 0-7: Address, Toe-up, Mid-backswing, Top, Mid-downswing, Impact, Mid-follow-through, Finish
# A "swing" clip = 15 frames centered on any event frame (0-7)
# A "not_swing" clip = 15 frames from gaps between swings

CLIP_FRAMES = 15
FPS = 30
OUTPUT_DIR = Path("training_data_binary")
GOLFDB_DIR = Path("golfdb_repo")
VIDEOS_DIR = Path("golfdb_videos")


def load_annotations():
    with open(GOLFDB_DIR / "data" / "val_split_1.pkl", "rb") as f:
        import pickle
        data = pickle.load(f, encoding="latin1")
    return data


def extract_clips():
    """Extract swing and not_swing clips from GolfDB videos."""
    # Implementation details depend on GolfDB annotation format
    # See ml-training/extract_5class_dataset.py for reference
    print("Extract binary clips from GolfDB — see design doc for full specification")
    print("Swing clips: 15 frames centered on annotated event frames")
    print("Not-swing clips: 15 frames from inter-swing gaps")
    print("Output: training_data_binary/swing/ and training_data_binary/not_swing/")


if __name__ == "__main__":
    extract_clips()
```

**Note:** The full extraction script should be adapted from `ml-training/extract_5class_dataset.py` (which already exists). The key difference is binary labeling: any 15-frame window containing a GolfDB event (0-7) → `swing/`, and windows from gaps → `not_swing/`.

**Step 2: Train in Create ML**

This is done in Create ML app (not scriptable yet for Action Classifier):

1. Open Create ML → New Project → Action Classifier
2. Drag `training_data_binary/` folder as training data
3. Settings:
   - Prediction Window Size: 15
   - Target Frame Rate: 30
   - Augmentations: Horizontal Flip
   - Iterations: 500+
4. Train (estimated ~30 min on M-series Mac)
5. Export → `GolfSwingClassifier.mlmodel`
6. Copy to `golf-sync-swing/` directory (Xcode auto-discovers)

**Step 3: After training, implement SwingClassifier prediction**

Update `SwingClassifier.swift` to build MLMultiArray from PoseFrame data and run the classifier. This depends on the trained model's input format (Create ML Action Classifier expects pose data in a specific format).

---

### Task 18: TDD Tuning Loop Setup

**Files:**
- Create: `golf-sync-swingTests/DetectionTuningTests.swift`

This test suite runs detection on labeled test videos and produces diagnostic JSON reports. See the design doc's "TDD Tuning Loop" section for the full specification.

```swift
//
//  DetectionTuningTests.swift
//  golf-sync-swingTests
//
//  TDD tuning loop: every false positive becomes a test case.
//  You never regress.
//

import Testing
@testable import golf_sync_swing

struct DetectionTuningTests {

    // TODO: Add test cases as false positives are discovered
    // Each test loads a labeled video, runs detection, and asserts
    // correct behavior (no false positives, swings detected within tolerance)

    @Test("Placeholder — tuning tests will be added during TDD loop")
    func placeholder() {
        #expect(true)
    }
}
```

---

## Summary

| Phase | Tasks | What it does |
|-------|-------|-------------|
| **1: Cleanup** | Tasks 1-3 | Delete ~52 files, simplify app entry to RecordingView only |
| **2: Detection** | Tasks 4-11 | Build pose-based detection pipeline (PoseFrame → PoseDetector → SwingClassifier/PoseHeuristics → SwingStateMachine → ImpactDetector) |
| **3: Integration** | Tasks 12-16 | Wire detection into recording, add Photos save, run all tests |
| **4: Training** | Tasks 17-18 | Extract GolfDB data, train Create ML classifier, TDD tuning loop |

**Files created:** ~10 new (PoseFrame, SwingEvent, PoseDetector, ImpactDetector, SwingStateMachine, PoseHeuristics, SwingClassifier, DetectionOrchestrator, PhotosSaveService, extract_binary_dataset.py)

**Files deleted:** ~52 (comparison, paywall, onboarding, SwiftData models, old detection)

**Files modified:** ~5 (app entry, RecordingViewModel, RecordingView, RecordingControlsView, Color+AppTeal)

**Final file count:** ~28 Swift files (down from ~90)
