//
//  CountdownView.swift
//  golf-sync-swing
//
//  Countdown overlay before recording starts
//

import SwiftUI

struct CountdownView: View {
    let count: Int
    let onCancel: () -> Void
    var silhouetteNamespace: Namespace.ID? = nil
    /// The countdown does not tick until the capture session is actually running, so on a
    /// cold bring-up the digit sits at 5 over a black screen for a few seconds. This flag
    /// surfaces why: while false, a "Getting the camera ready…" caption shows under the digit.
    var isCameraReady: Bool = true

    @State private var scale: CGFloat = 1.5
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            SilhouetteCutout(stance: .downTheLine, silhouetteNamespace: silhouetteNamespace)

            VStack(spacing: 14) {
                countdownDigit
                if !isCameraReady {
                    cameraPreparingCaption
                }
                Spacer()
                cancelButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
        .onChange(of: count) { _, _ in presentDigit() }
        .onChange(of: isCameraReady) { _, _ in presentDigit() }
        .onAppear { presentDigit() }
    }

    private var cameraPreparingCaption: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
            Text(String(localized: "Getting the camera ready…", comment: "Caption under the recording countdown while the capture session is still starting up"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .transition(.opacity)
    }

    private var countdownDigit: some View {
        Text("\(count)")
            .font(.system(size: 96, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 4)
            .scaleEffect(scale)
            .opacity(opacity)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text("CANCEL")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
        }
    }

    /// The tick animation ends at opacity 0, which is right for a digit about to be replaced
    /// by the next one — and wrong while the camera is still starting, because the count
    /// does not tick then. The digit simply vanished within a second and never came back,
    /// leaving a black screen with nothing on it. Hold it lit instead until the camera is
    /// ready, then let it pulse per tick.
    private func presentDigit() {
        guard isCameraReady else {
            withAnimation(.easeOut(duration: 0.25)) {
                scale = 1.0
                opacity = 1.0
            }
            return
        }
        animateCountdown()
    }

    private func animateCountdown() {
        scale = 1.5
        opacity = 0
        withAnimation(.easeOut(duration: 0.3)) {
            scale = 1.0
            opacity = 1.0
        }
        withAnimation(.easeIn(duration: 0.3).delay(0.5)) {
            scale = 0.8
            opacity = 0
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
        CountdownView(count: 3, onCancel: {})
    }
}
