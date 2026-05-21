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
    @Environment(AppRouter.self) private var router
    @State private var viewModel = RecordingViewModel()
    @State private var showingError = false
    @State private var isTabVisible = false
    @State private var showDetectionFlash = false
    @State private var videoAuthorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Namespace private var silhouetteAnimation

    private var hasCameraAccess: Bool { videoAuthorization == .authorized }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.ignoresSafeArea()

                if !hasCameraAccess {
                    CameraPermissionGate(
                        status: videoAuthorization,
                        onPrimaryAction: handlePermissionAction
                    )
                } else {
                    cameraStack
                }
            }
        }
        .onChange(of: viewModel.state) { _, newState in
            guard newState == .saved else { return }
            handleSaveCompleted()
        }
        .onChange(of: viewModel.swingCount) { oldCount, newCount in
            guard newCount > oldCount, viewModel.isRecording else { return }
            withAnimation(.easeOut(duration: 0.15)) { showDetectionFlash = true }
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.easeIn(duration: 0.25)) { showDetectionFlash = false }
            }
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
        .onAppear {
            viewModel.modelContext = modelContext
            isTabVisible = true
            refreshVideoAuthorization()
            if hasCameraAccess { startSessionIfNeeded() }
        }
        .onDisappear { handleDisappear() }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                showingError = false
                viewModel.errorMessage = nil
            }
            if viewModel.cameraService.currentError?.errorDescription?.contains("Settings") == true {
                Button("Open Settings") { openSystemSettings() }
            }
        } message: {
            Text(viewModel.errorMessage ?? viewModel.cameraService.currentError?.errorDescription ?? String(localized: "An unknown error occurred", comment: "Fallback recording-error alert body when neither the ViewModel nor CameraService provided a message"))
        }
        .fullScreenCover(isPresented: Bindable(viewModel).requiresLibraryUpgrade) {
            AppPaywallView(source: .featureGate) {
                viewModel.requiresLibraryUpgrade = false
            }
        }
    }

    private var cameraStack: some View {
        ZStack {
            CameraPreviewView(
                session: viewModel.cameraService.captureSession,
                rotationSubjectProvider: { [weak service = viewModel.cameraService] layer in
                    service?.makePreviewRotationSubject(for: layer)
                }
            )
            .id("main-camera-\(viewModel.cameraService.sessionConfigurationId)")
            .ignoresSafeArea()

            ZStack {
                if viewModel.state == .idle {
                    PositioningGuideOverlay(silhouetteNamespace: silhouetteAnimation)
                        .transition(.opacity)
                }
                if viewModel.isCountingDown {
                    CountdownView(
                        count: viewModel.countdownValue,
                        onCancel: viewModel.cancel,
                        silhouetteNamespace: silhouetteAnimation
                    )
                    .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: viewModel.isCountingDown)

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

            if viewModel.isFinalizingVideo || viewModel.isSaving {
                FinalizingVideoOverlay(swingCount: viewModel.swingCount)
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

    // MARK: - Permission

    private func refreshVideoAuthorization() {
        videoAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func handlePermissionAction() {
        switch videoAuthorization {
        case .notDetermined:
            Task {
                _ = await viewModel.cameraService.requestPermissions()
                refreshVideoAuthorization()
                if hasCameraAccess { startSessionIfNeeded() }
            }
        case .denied, .restricted:
            openSystemSettings()
        default:
            break
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Lifecycle

    private func startSessionIfNeeded() {
        Task {
            let granted = await viewModel.cameraService.requestPermissions()
            refreshVideoAuthorization()
            guard granted else { return }
            if !viewModel.cameraService.isSessionConfiguredForCurrentParams {
                viewModel.cameraService.setupSession(position: .front, frameRate: 30)
                try? await Task.sleep(for: .milliseconds(100))
            }
            if !viewModel.cameraService.isSessionRunning && !viewModel.isRecording {
                viewModel.cameraService.resumeSession()
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
            refreshVideoAuthorization()
            if hasCameraAccess && isTabVisible && !viewModel.cameraService.isSessionRunning && !viewModel.isRecording {
                viewModel.cameraService.resumeSession()
            }
        case .inactive: break
        @unknown default: break
        }
    }

    private func handleSaveCompleted() {
        let outcome = viewModel.saveOutcome
        viewModel.dismissSavedState()
        if let outcome { router.openInHistory(videoID: outcome.videoID) }
    }
}

#Preview {
    RecordingView()
        .environment(AppRouter())
}
