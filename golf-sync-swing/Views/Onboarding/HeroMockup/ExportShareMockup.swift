//
//  ExportShareMockup.swift
//  golf-sync-swing
//
//  Hero animation for onboarding screen 3: four clips stitch into one reel,
//  which then dissolves into a side-by-side that pulses against the gold
//  impact line — the two things a user can actually export and share.
//

import SwiftUI

struct ExportShareMockup: View {

    /// With Reduce Motion on, the composed end state is drawn once and no
    /// animator is instantiated at all — so there is no clock to leave running.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Metrics.stackSpacing) {
            stage
            chip
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private var stage: some View {
        if reduceMotion {
            scene(.composed)
        } else {
            animatedStage
        }
    }

    /// One clock, many tracks.
    ///
    /// The two beats have to stay locked to each other for as long as the page
    /// is up. A stack of `.repeatForever` animations cannot do that: each one
    /// keeps its own start date and its own duration, so a 1.15s sweep and a
    /// 0.3s dissolve drift apart a little on every cycle until the "aligned at
    /// impact" pulse lands on nothing. `KeyframeAnimator` samples every channel
    /// from a single 3.0s timeline instead, so the beats are in phase by
    /// construction rather than by arithmetic — and it lives and dies with this
    /// view, leaving no timer behind the rest of onboarding.
    private var animatedStage: some View {
        KeyframeAnimator(initialValue: Phase(), repeating: true) { phase in
            scene(phase)
        } keyframes: { _ in
            KeyframeTrack(\Phase.stitch) { stitchKeyframes }
            KeyframeTrack(\Phase.playhead) { playheadKeyframes }
            KeyframeTrack(\Phase.reelOpacity) { reelKeyframes }
            KeyframeTrack(\Phase.paneOpacity) { paneKeyframes }
            KeyframeTrack(\Phase.pulse) { pulseKeyframes }
        }
    }

    private func scene(_ phase: Phase) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.stageCorner)
                .fill(Color.onboardingMidGreen.opacity(0.4))
            reel(phase)
            comparison(phase)
        }
        .frame(height: Metrics.stageHeight)
    }

    // MARK: - Beat 1: the reel

    private func reel(_ phase: Phase) -> some View {
        HStack(spacing: gap(phase.stitch)) {
            ForEach(Metrics.clipTilts.indices, id: \.self) { index in
                clipCard(tilt: Metrics.clipTilts[index] * (1 - phase.stitch))
            }
        }
        .overlay(alignment: .leading) { playhead(phase) }
        .opacity(phase.reelOpacity)
    }

    private func clipCard(tilt: Double) -> some View {
        RoundedRectangle(cornerRadius: Metrics.clipCorner)
            .fill(Color.onboardingMidGreen)
            .frame(width: Metrics.clipWidth, height: Metrics.clipHeight)
            .overlay(
                Image(systemName: "figure.golf")
                    .font(.system(size: Metrics.clipIconSize))
                    .foregroundStyle(Color.onboardingGold.opacity(0.7))
            )
            .rotationEffect(.degrees(tilt))
    }

    private func playhead(_ phase: Phase) -> some View {
        Capsule()
            .fill(Color.onboardingGold)
            .frame(width: Metrics.playheadWidth, height: Metrics.playheadHeight)
            .offset(x: stripWidth(phase.stitch) * CGFloat(phase.playhead) - Metrics.playheadWidth / 2)
    }

    /// The gaps are what collapse; the cards keep their width. Strip width is
    /// therefore a function of the stitch, and the playhead sweeps that width.
    private func gap(_ stitch: Double) -> CGFloat {
        let slack = Metrics.clipGapApart - Metrics.clipGapJoined
        return Metrics.clipGapJoined + slack * CGFloat(1 - stitch)
    }

    private func stripWidth(_ stitch: Double) -> CGFloat {
        let clips = CGFloat(Metrics.clipTilts.count)
        return clips * Metrics.clipWidth + (clips - 1) * gap(stitch)
    }

    // MARK: - Beat 2: the side-by-side

    private func comparison(_ phase: Phase) -> some View {
        HStack(spacing: 0) {
            pane(label: Self.youLabel, pulse: phase.pulse, anchor: .trailing)
            pane(label: Self.proLabel, pulse: phase.pulse, anchor: .leading)
        }
        .overlay(divider)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.stageCorner))
        .opacity(phase.paneOpacity)
    }

    /// Anchored on its inner edge, so the pane swells *outwards* and the
    /// divider never moves: the two swings stay pinned to the same instant.
    private func pane(label: String, pulse: CGFloat, anchor: UnitPoint) -> some View {
        ZStack {
            Color.onboardingMidGreen
            VStack(spacing: Metrics.paneLabelGap) {
                Image(systemName: "figure.golf")
                    .font(.system(size: Metrics.paneIconSize))
                    .foregroundStyle(Color.onboardingGold.opacity(0.7))
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(pulse, anchor: anchor)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.onboardingGold)
            .frame(width: Metrics.dividerWidth)
    }

    // MARK: - Chip

    /// The onboarding chip, unchanged: same font, paddings, fill and stroke as
    /// `KillerSyncMockup.timeChip` on page 1. The numbers stay inline rather
    /// than moving to `Metrics` for exactly that reason — they are a quotation,
    /// and a reader has to be able to diff them against the original by eye.
    /// "HD" is a universal token: it is already "HD" in all twelve locales.
    private var chip: some View {
        HStack {
            Spacer()
            Text("HD")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.onboardingGold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.onboardingGold.opacity(0.15), in: Capsule())
                .overlay(Capsule().stroke(Color.onboardingGold.opacity(0.4), lineWidth: 1))
        }
    }

    private static let youLabel = String(
        localized: "YOU",
        comment: "Onboarding page 3 hero: label on the user's own swing in the side-by-side"
    )

    private static let proLabel = String(
        localized: "PRO",
        comment: "Onboarding page 3 hero: label on the pro's swing in the side-by-side"
    )
}

// MARK: - Timeline

extension ExportShareMockup {

    /// Every channel of one frame of the loop. Defaults are the state the loop
    /// starts and ends on, which is what makes the cycle seamless.
    private struct Phase {
        var stitch: Double = 0
        var playhead: Double = 0
        var reelOpacity: Double = 1
        var paneOpacity: Double = 0
        var pulse: CGFloat = 1

        /// What Reduce Motion draws: the clips composed, the comparison up.
        static let composed = Phase(stitch: 1, playhead: 1, reelOpacity: 0, paneOpacity: 1)
    }

    /// Instants on the 3.0s clock, not durations. Every keyframe below takes
    /// its duration as the difference between two of these, so the schedule
    /// reads as a timeline and each track provably sums to `Beat.period`.
    private enum Beat {
        static let period: TimeInterval = 3.0
        static let stitched: TimeInterval = 1.20
        static let sweepStart: TimeInterval = 0.20
        static let sweepEnd: TimeInterval = 1.35
        static let dissolveStart: TimeInterval = 1.35
        static let dissolveEnd: TimeInterval = 1.65
        static let pulseStart: TimeInterval = 1.70
        static let pulsePeak: TimeInterval = 2.05
        static let pulseEnd: TimeInterval = 2.50
        static let loopStart: TimeInterval = 2.70
    }

    @KeyframeTrackContentBuilder<Double>
    private var stitchKeyframes: some KeyframeTrackContent<Double> {
        CubicKeyframe(1, duration: Beat.stitched)
        LinearKeyframe(1, duration: Beat.loopStart - Beat.stitched)
        // Rewound under the crossfade: at 2.70s the reel is still fully faded
        // out, so the jump back to four loose clips is never seen.
        MoveKeyframe(0)
        LinearKeyframe(0, duration: Beat.period - Beat.loopStart)
    }

    @KeyframeTrackContentBuilder<Double>
    private var playheadKeyframes: some KeyframeTrackContent<Double> {
        LinearKeyframe(0, duration: Beat.sweepStart)
        LinearKeyframe(1, duration: Beat.sweepEnd - Beat.sweepStart)
        LinearKeyframe(1, duration: Beat.loopStart - Beat.sweepEnd)
        MoveKeyframe(0)
        LinearKeyframe(0, duration: Beat.period - Beat.loopStart)
    }

    @KeyframeTrackContentBuilder<Double>
    private var reelKeyframes: some KeyframeTrackContent<Double> {
        LinearKeyframe(1, duration: Beat.dissolveStart)
        LinearKeyframe(0, duration: Beat.dissolveEnd - Beat.dissolveStart)
        LinearKeyframe(0, duration: Beat.loopStart - Beat.dissolveEnd)
        LinearKeyframe(1, duration: Beat.period - Beat.loopStart)
    }

    @KeyframeTrackContentBuilder<Double>
    private var paneKeyframes: some KeyframeTrackContent<Double> {
        LinearKeyframe(0, duration: Beat.dissolveStart)
        LinearKeyframe(1, duration: Beat.dissolveEnd - Beat.dissolveStart)
        LinearKeyframe(1, duration: Beat.loopStart - Beat.dissolveEnd)
        LinearKeyframe(0, duration: Beat.period - Beat.loopStart)
    }

    /// One pulse, landing after the panes are fully up rather than during the
    /// dissolve — the beat has to read as a claim, not as a fade.
    @KeyframeTrackContentBuilder<CGFloat>
    private var pulseKeyframes: some KeyframeTrackContent<CGFloat> {
        LinearKeyframe(1, duration: Beat.pulseStart)
        CubicKeyframe(Metrics.pulseScale, duration: Beat.pulsePeak - Beat.pulseStart)
        CubicKeyframe(1, duration: Beat.pulseEnd - Beat.pulsePeak)
        LinearKeyframe(1, duration: Beat.period - Beat.pulseEnd)
    }
}

// MARK: - Metrics

extension ExportShareMockup {

    private enum Metrics {
        static let stackSpacing: CGFloat = 16
        static let stageHeight: CGFloat = 200
        static let stageCorner: CGFloat = 12

        /// Four clips, tilted alternately, that straighten as they join.
        static let clipTilts: [Double] = [-3, 3, -3, 3]
        static let clipWidth: CGFloat = 42
        static let clipHeight: CGFloat = 92
        static let clipCorner: CGFloat = 6
        static let clipIconSize: CGFloat = 18
        static let clipGapApart: CGFloat = 12
        static let clipGapJoined: CGFloat = 2

        static let playheadWidth: CGFloat = 2
        /// Overhangs the strip a little, the way a scrubber head does.
        static let playheadHeight: CGFloat = 100

        static let dividerWidth: CGFloat = 1.5
        static let paneIconSize: CGFloat = 48
        static let paneLabelGap: CGFloat = 10
        static let pulseScale: CGFloat = 1.04
    }
}
