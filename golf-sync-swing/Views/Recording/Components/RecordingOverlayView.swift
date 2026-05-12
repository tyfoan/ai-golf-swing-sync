//
//  RecordingOverlayView.swift
//  golf-sync-swing
//
//  State-dependent overlays for the recording view:
//  finalizing video, replay indicator, and camera interruption.
//

import SwiftUI

// MARK: - Finalizing Video Overlay

struct FinalizingVideoOverlay: View {
    let swingCount: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()

            OperationProgressView(
                title: "Saving Video...",
                subtitle: "\(swingCount) swing\(swingCount == 1 ? "" : "s") detected"
            )
            .tint(.white)
            .foregroundStyle(.white)
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Replay Indicator Overlay

struct ReplayIndicatorOverlay: View {
    let swingNumber: Int
    let confidence: Double

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(Color.sand)
                    Text("Swing #\(swingNumber)")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Text("Confidence: \(Int(confidence * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 220)
        }
    }
}

// MARK: - Replay Loading Overlay

struct ReplayLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Loading replay...")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - Interruption Overlay

struct InterruptionOverlay: View {
    let errorDescription: String?
    let onResume: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.yellow)

                Text("Recording Interrupted")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(errorDescription ?? "Camera session was interrupted")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Resume", action: onResume)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.fairwayGreen)
                    .clipShape(Capsule())
            }
            .padding(32)
        }
    }
}
