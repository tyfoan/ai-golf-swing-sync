//
//  CameraPermissionPageView.swift
//  golf-sync-swing
//
//  Final step of onboarding (after paywall). Requests camera +
//  microphone permission and pre-warms the AVCaptureSession so
//  the Recording tab opens with a live preview immediately.
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
        return permissionResolved
            ? String(
                localized: "Continue",
                comment: "Button on the onboarding camera permission page that advances to the main app after permission has been resolved"
            )
            : String(
                localized: "Allow Camera Access",
                comment: "Primary CTA on the onboarding camera permission page that triggers the iOS camera and microphone permission prompts"
            )
    }

    // MARK: - Actions

    private func handleTap() {
        if permissionResolved {
            onContinue()
            return
        }
        Task { await requestAndPrewarm() }
    }

    @MainActor
    private func requestAndPrewarm() async {
        isRequesting = true
        let granted = await CameraService.shared.requestPermissions()
        if granted {
            CameraService.shared.setupSession(position: .front, frameRate: 30)
            try? await Task.sleep(for: .milliseconds(300))
            CameraService.shared.resumeSession()
        }
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
