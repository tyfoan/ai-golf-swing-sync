//
//  CaptureChromeView.swift
//  golf-sync-swing
//
//  The Camera tab's controls layer: top bar, replay indicator, skeleton toggle,
//  picture-in-picture tile, bottom controls — stacked over the live preview and driven
//  entirely by `RecordingViewModel`.
//
//  BOTH SIDES OF THE TILE ARE IMAGES. Whichever content it holds — the looping replay, or the
//  live camera when the replay has taken the main screen — it draws JPEGs the ring buffer kept
//  in memory. It must never go back to being a second `CameraPreviewView`, which showed the
//  same picture as the screen behind it and blacked out the main preview.
//
//  Chrome only. The lifecycle handlers (session bring-up, tab exits, scene phase) stayed
//  behind in `RecordingView`: they belong to whoever owns the screen, not to the buttons
//  drawn on it.
//

import SwiftUI

struct CaptureChromeView: View {
    @Bindable var viewModel: RecordingViewModel

    /// Injected rather than read off the camera, matching `RecordingControlsView`: the tab
    /// already knows, and the only thing the chrome does with it is decide whether Start
    /// can be pressed yet.
    let isCameraReady: Bool

    var body: some View {
        VStack(spacing: 0) {
            RecordingTopBar(
                state: viewModel.state,
                isRecording: viewModel.isRecording,
                swingCount: viewModel.swingCount,
                recordedDuration: viewModel.cameraService.recordedDuration,
                onCancel: viewModel.discardTake
            )

            overlayRow

            Spacer()

            RecordingControlsView(viewModel: viewModel, isCameraReady: isCameraReady)
        }
    }

    /// The row under the top bar: what the main screen is showing on the left, the controls
    /// that act on it on the right. Both are secondary to the golfer in the middle of the
    /// frame, so both hug an edge and neither ever crosses the centre.
    private var overlayRow: some View {
        HStack(alignment: .top, spacing: 12) {
            replayIndicator
            Spacer(minLength: 0)
            trailingRail
        }
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.swingReplay?.id)
        // A second animation, keyed on the swap rather than on the swing: it is what the
        // replay indicator's transition reads its timing from, and it matches the crossfade
        // `RecordingView.replayCover` uses so the pill and the picture arrive together. The
        // tile's own CONTENT is deliberately outside both — swapping is meant to feel instant.
        .animation(.easeInOut(duration: 0.2), value: viewModel.isReplayOnMain)
    }

    /// The right-hand column. Stacked rather than floating the tile over the toggle, as the
    /// deleted PiP did, so neither can ever cover the other. The toggle stays mounted in both
    /// display modes — see `skeletonToggle` — so the tile never jumps when the surfaces swap.
    private var trailingRail: some View {
        VStack(alignment: .trailing, spacing: 12) {
            skeletonToggle
            pipTile
        }
    }

    /// Hidden while idle: the positioning guide owns that screen, and a toggle buried under
    /// its scrim reads as a rendering bug.
    ///
    /// Deliberately NOT hidden while the replay covers the main screen, even though the
    /// skeleton is suppressed there. It still expresses the user's choice, it takes effect the
    /// instant they swap back, and pulling it out of the rail would slide the tile up and down
    /// on every tap.
    @ViewBuilder
    private var skeletonToggle: some View {
        if viewModel.state != .idle {
            SkeletonToggleButton(isActive: $viewModel.isSkeletonEnabled)
        }
    }

    /// The tile, and the swap that lives on it. Mounted exactly when there are two things to
    /// show: a swing whose frames the ring actually yielded, during the take that detected it.
    /// That window is also the only one in which the ring is armed, which is what lets the
    /// tile hold the LIVE camera in the other mode.
    @ViewBuilder
    private var pipTile: some View {
        if let replay = viewModel.activeReplay {
            CapturePiPTile(
                badge: viewModel.displayMode.tileBadge(swingNumber: replay.number),
                accessibilityDescription: String(localized: "Swap the small tile and the main view", comment: "VoiceOver label for the capture screen's picture-in-picture tile, which is a button that swaps the live camera and the swing replay between the tile and the full screen"),
                onSwap: viewModel.swapDisplaySurfaces
            ) {
                pipContent(replay)
            }
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }

    /// Whatever is not on the main screen. Exactly one of the two is the camera, and in
    /// neither case is it a preview layer: the live branch draws the newest ring frame.
    @ViewBuilder
    private func pipContent(_ replay: SwingReplay) -> some View {
        switch viewModel.displayMode {
        case .swingOnMain:
            LiveRingFrameView(
                buffer: viewModel.cameraService.swingFrameBuffer,
                isMirrored: isPreviewMirrored
            )
        case .cameraOnMain:
            SwingReplayPlayerView(replay: replay, isMirrored: isPreviewMirrored)
        }
    }

    /// Says out loud that the full screen is a replay and not the camera. Without it the only
    /// evidence is the tile's "LIVE" badge, which asks the golfer to reason backwards from a
    /// thumbnail about what the big picture is.
    @ViewBuilder
    private var replayIndicator: some View {
        if viewModel.isReplayOnMain, let replay = viewModel.activeReplay {
            Label(
                String(localized: "LAST SWING \(replay.number)", comment: "Pill on the capture screen when the main surface is replaying the most recently detected swing instead of showing the live camera; the number counts swings in the current take"),
                systemImage: "arrow.counterclockwise"
            )
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// The same parity the skeleton overlay flips by: both tile contents come from the
    /// video-data output, the preview under them may be mirrored, and only this XOR knows
    /// whether the two disagree.
    private var isPreviewMirrored: Bool {
        viewModel.cameraService.poseOverlayGeometry?.isMirrored ?? false
    }
}
