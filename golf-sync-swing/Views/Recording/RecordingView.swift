//
//  RecordingView.swift
//  golf-sync-swing
//
//  Main recording view with camera, pose overlay, and controls
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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                // Main content: either camera preview or swing replay
                mainContentView
                    .ignoresSafeArea()

                // Main UI layers
                VStack(spacing: 0) {
                    // Top bar
                    topBar

                    Spacer()

                    // Swing attempts list (when swings detected)
                    if viewModel.swingCount > 0 && viewModel.isRecording {
                        swingAttemptsList
                    }

                    // Bottom controls
                    bottomControls
                }

                // PiP view during recording (shows alternate view)
                if viewModel.isRecording && viewModel.swingCount > 0 {
                    pipView
                }

                // Countdown overlay
                if viewModel.isCountingDown {
                    CountdownView(count: viewModel.countdownValue) {
                        viewModel.cancel()
                    }
                }

                // Processing swing overlay
                if viewModel.isProcessingSwing {
                    processingSwingOverlay
                }

                // Finalizing video overlay
                if viewModel.isFinalizingVideo {
                    finalizingVideoOverlay
                }

                // Current replay indicator
                if viewModel.mainViewShowsReplay, let swing = viewModel.currentReplaySwing {
                    replayIndicatorOverlay(swing: swing)
                }

                // Interruption overlay
                if viewModel.cameraService.isInterrupted {
                    interruptionOverlay
                }
            }
        }
        .onAppear {
            isTabVisible = true

            Task {
                let granted = await viewModel.cameraService.requestPermissions()
                if granted {
                    if !hasSetupCamera {
                        // First time setup - configure and start session
                        viewModel.cameraService.setupSession(position: .front, frameRate: 30)
                        hasSetupCamera = true
                        // Small delay on first setup to let UI settle
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    // Resume session if not running (quick operation)
                    if !viewModel.cameraService.isSessionRunning && !viewModel.isRecording {
                        viewModel.cameraService.resumeSession()
                    }
                }
            }
        }
        .onDisappear {
            isTabVisible = false

            // Only pause (don't cleanup) when switching tabs
            // This avoids expensive session reconfiguration
            if !viewModel.isRecording {
                viewModel.cameraService.pauseSession()
            }
        }
        .confirmationDialog(
            "Save Recording",
            isPresented: $viewModel.showSaveConfirmation,
            titleVisibility: .visible
        ) {
            Button(viewModel.swingCount > 0 ? "Save Recording (\(viewModel.swingCount) Swings)" : "Save Recording") {
                Task {
                    _ = await viewModel.saveRecording(to: modelContext)
                }
            }

            Button("Delete Recording", role: .destructive) {
                viewModel.deleteRecording()
            }

            Button("Cancel", role: .cancel) {
                viewModel.enterReviewMode()
            }
        }
        .sheet(isPresented: $showingTips) {
            RecordingTipsSheet()
        }
        .alert("Camera Error", isPresented: $showingError) {
            Button("OK") {
                showingError = false
            }
            if viewModel.cameraService.currentError?.errorDescription?.contains("Settings") == true {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } message: {
            Text(viewModel.cameraService.currentError?.errorDescription ?? "An unknown error occurred")
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .onChange(of: viewModel.cameraService.currentError) { _, newError in
            if newError != nil {
                showingError = true
            }
        }
    }

    // MARK: - Scene Phase Handling

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // Pause camera when app goes to background
            if !viewModel.isRecording {
                viewModel.cameraService.pauseSession()
            }
            // Note: If recording, the backgroundTask in CameraService handles it

        case .active:
            // Resume camera when app becomes active, but only if this tab is visible
            if isTabVisible && !viewModel.cameraService.isSessionRunning && !viewModel.isRecording {
                viewModel.cameraService.resumeSession()
            }

        case .inactive:
            // Transitioning - do nothing
            break

        @unknown default:
            break
        }
    }

    // MARK: - Main Content View

    @ViewBuilder
    private var mainContentView: some View {
        if viewModel.mainViewShowsReplay,
           let swing = viewModel.currentReplaySwing,
           let url = viewModel.recordingURL {
            // Show swing replay as main content
            // Use swing.id to force view recreation when switching between swings
            SwingReplayView(
                videoURL: url,
                startTime: swing.startTime,
                endTime: swing.endTime
            )
            .id(swing.id)
        } else {
            // Show live camera preview
            ZStack {
                CameraPreviewView(session: viewModel.cameraService.captureSession)
                    // Force recreate when session is reconfigured
                    .id("main-camera-\(viewModel.cameraService.sessionConfigurationId)")

                // Pose overlay
                if viewModel.showPoseOverlay && viewModel.isRecording {
                    PoseOverlayView(pose: viewModel.currentPose, isMirrored: viewModel.isFrontCamera)
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Close/Cancel button
            if viewModel.isRecording || viewModel.isCountingDown {
                Button(action: viewModel.cancel) {
                    Image(systemName: "xmark")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.green)
                        .clipShape(Circle())
                }
            }

            Spacer()

            // Recording indicator
            if viewModel.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)

                    Text(formatDuration(viewModel.cameraService.recordedDuration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }

            Spacer()

            // Swing count badge
            if viewModel.swingCount > 0 {
                Text("\(viewModel.swingCount)")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.green)
                    .clipShape(Circle())
            }
        }
        .padding()
    }

    // MARK: - Swing Attempts List

    private var swingAttemptsList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(viewModel.detectedSwings.enumerated()), id: \.element.id) { index, swing in
                    SwingAttemptCard(
                        swingNumber: index + 1,
                        confidence: swing.confidence,
                        isFavorite: swing.isFavorite,
                        isSelected: viewModel.replayingSwingIndex == index && viewModel.mainViewShowsReplay
                    )
                    .onTapGesture {
                        viewModel.showSwing(at: index)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Control buttons (only during recording)
            if viewModel.isRecording {
                HStack(spacing: 24) {
                    // Live camera button (when showing replay)
                    if viewModel.mainViewShowsReplay {
                        Button(action: viewModel.showLiveCamera) {
                            Image(systemName: "video.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.blue.opacity(0.7))
                                .clipShape(Circle())
                        }
                    }

                    // Speed selector
                    SpeedButton(speed: viewModel.playbackSpeed)

                    // Favorite button
                    Button(action: {
                        if let index = viewModel.replayingSwingIndex ?? viewModel.detectedSwings.indices.last {
                            viewModel.toggleFavorite(at: index)
                        }
                    }) {
                        let isFavorite = viewModel.currentReplaySwing?.isFavorite ?? viewModel.detectedSwings.last?.isFavorite ?? false
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(isFavorite ? .yellow : .white)
                            .frame(width: 50, height: 50)
                            .background(Color.gray.opacity(0.5))
                            .clipShape(Circle())
                    }

                    // Pose toggle (only when showing live camera, not replay)
                    if !viewModel.mainViewShowsReplay {
                        Button(action: viewModel.togglePoseOverlay) {
                            Image(systemName: "figure.stand")
                                .font(.title2)
                                .foregroundStyle(viewModel.showPoseOverlay ? .green : .white)
                                .frame(width: 50, height: 50)
                                .background(Color.gray.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                }
            }

            // Start Recording / Stop button / Review buttons
            if viewModel.state == .idle {
                startRecordingButton
            } else if viewModel.isRecording {
                stopRecordingButton
            } else if viewModel.isReviewing {
                reviewingButtons
            }
        }
        .padding(.bottom, 100) // Increased padding to clear tab bar
    }

    private var startRecordingButton: some View {
        Button(action: viewModel.startRecording) {
            Text("Start Recording")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.green)
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
                    .fill(Color.red)
                    .frame(width: 30, height: 30)
            }
        }
    }

    private var reviewingButtons: some View {
        HStack(spacing: 20) {
            // Delete button
            Button(action: viewModel.deleteRecording) {
                Text("Delete")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            // Save button
            Button {
                Task {
                    _ = await viewModel.saveRecording(to: modelContext)
                }
            } label: {
                Text(viewModel.swingCount > 0 ? "Save (\(viewModel.swingCount))" : "Save")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - PiP View

    private var pipView: some View {
        VStack {
            HStack {
                Spacer()

                ZStack(alignment: .topLeading) {
                    // Content based on display mode
                    Group {
                        if viewModel.pipDisplayMode == .liveCamera {
                            // Live camera feed
                            ZStack {
                                CameraPreviewView(session: viewModel.cameraService.captureSession)
                                    .id("pip-camera-\(viewModel.cameraService.sessionConfigurationId)")

                                // Pose overlay on PiP
                                if viewModel.showPoseOverlay {
                                    PoseOverlayView(pose: viewModel.currentPose, isMirrored: viewModel.isFrontCamera)
                                }
                            }
                        } else if let lastSwing = viewModel.lastDetectedSwing,
                                  let url = viewModel.recordingURL {
                            // Last swing replay
                            SwingReplayView(
                                videoURL: url,
                                startTime: lastSwing.startTime,
                                endTime: lastSwing.endTime
                            )
                        }
                    }
                    .frame(width: 120, height: 160)

                    // Badge indicating what PiP shows
                    HStack(spacing: 4) {
                        if viewModel.pipDisplayMode == .liveCamera {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("REC")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                            Text("REPLAY")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(viewModel.pipDisplayMode == .liveCamera ? Color.green : Color.orange, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                .onTapGesture {
                    // Tap PiP to swap main and PiP content
                    viewModel.swapMainAndPip()
                }
            }
            .padding()

            Spacer()
        }
    }

    // MARK: - Processing Swing Overlay

    private var processingSwingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Detecting Swing...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Finalizing Video Overlay

    private var finalizingVideoOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Saving Video...")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("\(viewModel.swingCount) swing\(viewModel.swingCount == 1 ? "" : "s") detected")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Replay Indicator Overlay

    private func replayIndicatorOverlay(swing: SwingClip) -> some View {
        VStack {
            Spacer()

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.orange)
                    Text("Swing #\(viewModel.replayingSwingIndex.map { $0 + 1 } ?? viewModel.swingCount)")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                Text("Confidence: \(Int(swing.confidence * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 220) // Above the controls
        }
    }

    // MARK: - Interruption Overlay

    private var interruptionOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.yellow)

                Text("Recording Interrupted")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(viewModel.cameraService.currentError?.errorDescription ?? "Camera session was interrupted")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Resume") {
                    viewModel.cameraService.resumeSession()
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color.green)
                .clipShape(Capsule())
            }
            .padding(32)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration - Double(Int(duration))) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Preview

#Preview {
    RecordingView()
        .modelContainer(for: [SwingVideo.self, SwingMarker.self], inMemory: true)
}

// Note: SwingAttemptCard, SpeedButton, RecordingTipsSheet, TipCard
// are now in Views/Recording/Components/
