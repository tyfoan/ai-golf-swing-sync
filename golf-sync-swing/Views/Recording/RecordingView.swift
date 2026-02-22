//
//  RecordingView.swift
//  golf-sync-swing
//
//  Main recording view container. Composes sub-views:
//    RecordingTopBar        - Cancel, timer, swing count
//    RecordingControlsView  - Start/stop/save buttons
//    RecordingPiPView       - Picture-in-picture overlay
//    RecordingOverlayView   - Finalizing, replay indicator, interruption
//

import SwiftUI
import SwiftData
import AVFoundation

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = RecordingViewModel()
    @State private var showingTips = false
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

                    if viewModel.swingCount > 0 && viewModel.isRecording {
                        swingAttemptsList
                    }

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
        .fullScreenCover(item: $viewModel.savedVideo, onDismiss: { viewModel.savedVideo = nil }) { video in
            SingleVideoPlayerView(video: video)
        }
        .sheet(isPresented: $showingTips) { RecordingTipsSheet() }
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

    // MARK: - Swing Attempts

    private var swingAttemptsList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(viewModel.detectedSwings.enumerated()), id: \.element.id) { index, swing in
                    SwingAttemptCard(
                        swingNumber: index + 1,
                        confidence: swing.confidence,
                        isFavorite: swing.isFavorite,
                        isSelected: viewModel.replayingSwingIndex == index
                    )
                    .onTapGesture { viewModel.showSwing(at: index) }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 12)
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

#Preview {
    RecordingView()
        .modelContainer(for: [SwingVideo.self, SwingMarker.self], inMemory: true)
}
