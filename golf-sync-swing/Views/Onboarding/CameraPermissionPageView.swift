//
//  CameraPermissionPageView.swift
//  golf-sync-swing
//
//  Final step of onboarding (after paywall). Requests camera +
//  microphone permission. The capture session itself comes up on
//  demand when the Camera tab appears.
//

import AVFoundation
import SwiftUI

struct CameraPermissionPageView: View {

    let onContinue: () -> Void

    @State private var permissionResolved: Bool
    @State private var isRequesting = false

    init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
        self._permissionResolved = State(initialValue: !Self.permissionPending)
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Spacer()
                iconSection
                textSection
                Spacer()
                actionButton
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Background

    private var background: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                .onboardingDark,      .onboardingDeepGreen, .onboardingDark,
                .onboardingDeepGreen, .onboardingMidGreen,  .onboardingDeepGreen,
                .onboardingDark,      .onboardingDeepGreen, .onboardingDark
            ]
        )
        .ignoresSafeArea()
    }

    // MARK: - Icon

    private var iconSection: some View {
        ZStack {
            Circle()
                .fill(Color.onboardingGold.opacity(0.15))
                .frame(width: 160, height: 160)
            Image(systemName: "video.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Color.onboardingGold)
        }
        .padding(.bottom, 32)
    }

    // MARK: - Text

    private var textSection: some View {
        VStack(spacing: 16) {
            Text("Record Your Swings")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .tracking(-0.6)

            Text("We need camera and microphone access to capture and analyze your golf swings.")
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Button

    private var actionButton: some View {
        Button(action: handleTap) {
            Text(buttonTitle)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.onboardingRichGreen, Color.fairwayGreen],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .shadow(color: Color.fairwayGreen.opacity(0.4), radius: 12, y: 4)
        }
        .disabled(isRequesting)
        .padding(.bottom, 48)
    }

    private var buttonTitle: String {
        if isRequesting {
            return String(
                localized: "Requesting…",
                comment: "Button label shown on the onboarding camera permission page while the iOS system permission alert is presented"
            )
        }
        return String(
            localized: "Continue",
            comment: "Button on the onboarding camera permission page that advances to the main app after permission has been resolved"
        )
    }

    // MARK: - Actions

    private func handleTap() {
        if permissionResolved {
            onContinue()
            return
        }
        Task { await requestPermission() }
    }

    /// Permission only — deliberately NO session pre-warm. Pre-warming here left the
    /// camera running (green privacy indicator) behind screens that show no preview, and
    /// raced `RecordingView`'s own bring-up: the tap on Start Recording then blocked the
    /// main thread against the still-configuring session — the first-cold-launch freeze.
    /// The Camera tab brings the session up on appear instead.
    @MainActor
    private func requestPermission() async {
        isRequesting = true
        _ = await CameraService.shared.requestPermissions()
        permissionResolved = true
        isRequesting = false
    }

    // MARK: - Permission Status

    private static var permissionPending: Bool {
        let video = AVCaptureDevice.authorizationStatus(for: .video)
        let audio = AVCaptureDevice.authorizationStatus(for: .audio)
        return video == .notDetermined || audio == .notDetermined
    }
}

#Preview {
    CameraPermissionPageView(onContinue: { })
}
