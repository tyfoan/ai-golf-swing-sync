//
//  RecordingView.swift
//  golf-sync-swing
//
//  Main recording view container. Composes sub-views:
//    RecordingTopBar        - Cancel, timer, swing count
//    RecordingControlsView  - Start/stop/save buttons
//

import SwiftUI
import SwiftData
import AVFoundation

struct RecordingView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = RecordingViewModel()
    @State private var showingError = false
    @State private var hasSetupCamera = false
    @State private var isTabVisible = false
    @State private var showDetectionFlash = false

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.ignoresSafeArea()

                CameraPreviewView(session: viewModel.cameraService.captureSession)
                    .id("main-camera-\(viewModel.cameraService.sessionConfigurationId)")
                    .ignoresSafeArea()

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

                if viewModel.isCountingDown {
                    CountdownView(count: viewModel.countdownValue) { viewModel.cancel() }
                }

                if viewModel.isFinalizingVideo || viewModel.isSaving {
                    FinalizingVideoOverlay(swingCount: viewModel.swingCount)
                }

                if viewModel.state == .saved {
                    SavedSuccessOverlay()
                        .transition(.opacity.combined(with: .scale))
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.state)
                }

                if viewModel.cameraService.isInterrupted {
                    InterruptionOverlay(
                        errorDescription: viewModel.cameraService.currentError?.errorDescription,
                        onResume: viewModel.cameraService.resumeSession
                    )
                }

                if showDetectionFlash {
                    Color.fairwayGreen.opacity(0.35)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: viewModel.swingCount) { oldCount, newCount in
            guard newCount > oldCount, viewModel.isRecording else { return }
            withAnimation(.easeOut(duration: 0.15)) { showDetectionFlash = true }
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.easeIn(duration: 0.25)) { showDetectionFlash = false }
            }
        }
        .onAppear {
            viewModel.modelContext = modelContext
            handleAppear()
        }
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
        .fullScreenCover(isPresented: Bindable(viewModel).requiresLibraryUpgrade) {
            AppPaywallView(source: .featureGate) {
                viewModel.requiresLibraryUpgrade = false
            }
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

// MARK: - Saved Success Overlay

private struct SavedSuccessOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Saved to Photos")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

#Preview {
    RecordingView()
}
