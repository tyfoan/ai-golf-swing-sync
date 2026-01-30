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
    @State private var viewModel = RecordingViewModel()
    @State private var showingTips = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                // Camera preview
                CameraPreviewView(session: viewModel.cameraService.captureSession)
                    .ignoresSafeArea()

                // Pose overlay
                if viewModel.showPoseOverlay && viewModel.isRecording {
                    PoseOverlayView(pose: viewModel.currentPose)
                        .ignoresSafeArea()
                }

                // Main UI layers
                VStack(spacing: 0) {
                    // Top bar
                    topBar

                    Spacer()

                    // Bottom controls
                    bottomControls
                }

                // PiP view during replay
                if viewModel.isShowingReplay {
                    pipView
                }

                // Countdown overlay
                if viewModel.isCountingDown {
                    CountdownView(count: viewModel.countdownValue) {
                        viewModel.cancel()
                    }
                }

                // Swing detected indicator
                if viewModel.isShowingReplay {
                    swingDetectedOverlay
                }
            }
        }
        .onAppear {
            Task {
                let granted = await viewModel.cameraService.requestPermissions()
                if granted {
                    viewModel.cameraService.setupSession(position: .back, frameRate: 60)
                    viewModel.cameraService.startSession()
                }
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .confirmationDialog(
            "Save Recording",
            isPresented: $viewModel.showSaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save Recording (\(viewModel.swingCount) Swings)") {
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

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Control buttons (only during recording)
            if viewModel.isRecording {
                HStack(spacing: 24) {
                    // Speed selector
                    SpeedButton(speed: viewModel.playbackSpeed)

                    // Favorite button
                    Button(action: {
                        if let index = viewModel.detectedSwings.indices.last {
                            viewModel.toggleFavorite(at: index)
                        }
                    }) {
                        Image(systemName: viewModel.detectedSwings.last?.isFavorite == true ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.gray.opacity(0.5))
                            .clipShape(Circle())
                    }

                    // Pose toggle
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

            // Start Recording / Stop button
            if viewModel.state == .idle {
                startRecordingButton
            } else if viewModel.isRecording {
                stopRecordingButton
            }
        }
        .padding(.bottom, 30)
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

    // MARK: - PiP View

    private var pipView: some View {
        VStack {
            HStack {
                Spacer()

                ZStack(alignment: .topLeading) {
                    CameraPreviewView(session: viewModel.cameraService.captureSession)
                        .frame(width: 120, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )

                    // Recording indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("LIVE")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(8)
                }
            }
            .padding()

            Spacer()
        }
    }

    // MARK: - Swing Detected Overlay

    private var swingDetectedOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 8) {
                Text("Swing Detected!")
                    .font(.headline)
                    .foregroundStyle(.white)

                if let swing = viewModel.currentReplaySwing {
                    Text("Confidence: \(Int(swing.confidence * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 150)
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

// MARK: - Speed Button

struct SpeedButton: View {
    let speed: Float

    var body: some View {
        Button(action: {}) {
            Text(String(format: "%.1fx", speed))
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Color.gray.opacity(0.5))
                .clipShape(Circle())
        }
    }
}

// MARK: - Tips Sheet

struct RecordingTipsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TipCard(
                        number: 1,
                        title: "Camera Placement",
                        description: "Place your phone on a tripod or stable surface, facing your swing. Ensure your full body is visible."
                    )

                    TipCard(
                        number: 2,
                        title: "Lighting",
                        description: "Record in well-lit conditions. Natural daylight works best for pose detection."
                    )

                    TipCard(
                        number: 3,
                        title: "Distance",
                        description: "Stand 8-12 feet from the camera for optimal pose tracking."
                    )
                }
                .padding()
            }
            .navigationTitle("Recording Tips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct TipCard: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.green)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    RecordingView()
        .modelContainer(for: [SwingVideo.self, SwingMarker.self], inMemory: true)
}
