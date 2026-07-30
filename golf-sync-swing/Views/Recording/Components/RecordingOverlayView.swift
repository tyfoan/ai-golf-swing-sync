//
//  RecordingOverlayView.swift
//  golf-sync-swing
//
//  State-dependent overlays for the recording view:
//  finalizing video, review notice, and camera interruption.
//

import SwiftUI

// MARK: - Finalizing Video Overlay

struct FinalizingVideoOverlay: View {
    /// Which half of the finalize → save hand-off is on screen. Both used to claim "Saving
    /// Video...", a promise finalize cannot make: a take with no detected swing is handed
    /// back for review and one over the library limit lands on a paywall. Promising a save
    /// and then deleting the clip is exactly what made this screen feel broken.
    enum Phase {
        case finalizing
        case saving
    }

    let phase: Phase
    let swingCount: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()

            OperationProgressView(title: title, subtitle: subtitle)
                .tint(.white)
                .foregroundStyle(.white)
                .padding(32)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var title: String {
        switch phase {
        case .finalizing:
            return String(localized: "Finishing Recording...", comment: "Overlay title shown while a stopped recording is still being written to disk, before the app knows whether it will be saved or handed back for review")
        case .saving:
            return String(localized: "Saving Video...", comment: "Overlay title shown while a finished recording is being copied into the app's own library")
        }
    }

    /// Detection has already stopped by the time this overlay appears, so the count is
    /// final — an empty one can be stated as fact rather than hedged.
    private var subtitle: String {
        guard swingCount > 0 else { return emptyCountSubtitle }
        return String(localized: "\(swingCount) swings detected", comment: "Subtitle on the saving overlay — translators should add a one/other plural variation")
    }

    /// Shares its key with the review panel's title on purpose: the same sentence, one
    /// beat apart, reads as one continuous answer rather than two verdicts.
    private var emptyCountSubtitle: String {
        switch phase {
        case .finalizing:
            return String(localized: "No swing detected", comment: "Shown when a recording finished without a detected swing — as the title of the capture review panel and as the subtitle of the finishing-recording overlay")
        case .saving:
            return String(localized: "Saving the full recording", comment: "Subtitle on the saving overlay when no swing was detected and the entire clip is being saved")
        }
    }
}

// MARK: - Review Notice Overlay

/// Shown while the user decides what to do with a finished take. The capture session is
/// paused for review, so the preview behind this is black — without the panel the screen is
/// a void with two unexplained buttons under it. Hit testing is off precisely so those
/// buttons, which sit *below* this layer in the ZStack, stay tappable.
struct ReviewNoticeOverlay: View {
    let notice: ReviewNotice

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.golf")
                .font(.system(size: 44))
                .foregroundStyle(Color.sand)

            Text(notice.title)
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text(notice.message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 32)
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
