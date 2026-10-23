//
//  ExportEditorViewModel.swift
//  golf-sync-swing
//
//  The editor's state — aspect ratio, per-swing framing and sound — previewed on the
//  comparison's own player. The editor owns no players: its tiles cut the swings out of
//  the frames the comparison stage already shows, impact-aligned and decoded once.
//
//  Creating one has no side effects (SwiftUI may build several and keep the first);
//  `attach()` and `detach()` touch the shared player, from the view's appear/disappear.
//

import CoreGraphics
import Foundation
import Observation

@Observable
final class ExportEditorViewModel {

    var aspectRatio: ExportAspectRatio
    let mode: ComparisonMode
    let comparison: ComparisonViewModel
    /// Whose swing is which, by position — names for the sound toggles and the picker.
    let labels: [PaneLabel]
    var stackedOpacity: CGFloat
    /// In the overlaid modes, the position of the one swing being framed.
    var framedPosition = 0 {
        didSet { showFramedSwing() }
    }
    /// Framing gestures write here on every frame; only a mute toggle touches the mix.
    var transforms: [VideoTransform] {
        didSet {
            guard transforms.map(\.isMuted) != oldValue.map(\.isMuted) else { return }
            previewAudio()
        }
    }

    init(comparison: ComparisonViewModel, labels: [PaneLabel]) {
        self.comparison = comparison
        self.labels = labels
        self.mode = comparison.comparisonMode
        self.aspectRatio = comparison.comparisonMode.defaultExportAspect
        self.stackedOpacity = comparison.stackedOpacity
        self.transforms = Self.defaultTransforms(heard: Self.firstAudiblePosition(in: comparison))
    }

    /// One clean impact, as in playback: the first swing that has any sound is heard,
    /// the other muted — so a silent pro swing on top never leaves the export silent.
    private static func defaultTransforms(heard: Int) -> [VideoTransform] {
        [0, 1].map { position in
            var transform = VideoTransform()
            transform.isMuted = position != heard
            return transform
        }
    }

    private static func firstAudiblePosition(in comparison: ComparisonViewModel) -> Int {
        [0, 1].first(where: comparison.hasSound(atPosition:)) ?? 0
    }

    // MARK: - Layout

    /// How the canvas is split for the current aspect ratio and the two swings' shapes.
    var arrangement: VideoArrangement {
        ExportArrangementAdvisor(aspects: positionAspects)
            .arrangement(for: mode.exportArrangement, canvas: aspectRatio.exportSize)
    }

    /// Overlaid modes frame one swing at a time; split ones frame both at once.
    var framesOneSwingAtATime: Bool {
        arrangement == .overlaid
    }

    /// The swings on the canvas: both, except in sequential, which shows the one framed.
    var visiblePositions: [Int] {
        mode.playsSequentially ? [framedPosition] : [0, 1]
    }

    func isFramable(_ position: Int) -> Bool {
        !framesOneSwingAtATime || position == framedPosition
    }

    private var positionAspects: [CGFloat] {
        guard let atlas = comparison.atlas else { return [1, 1] }
        return comparison.trackOrder.map { atlas.aspectRatio(ofTrack: $0) }
    }

    func buildLayoutConfig() -> VideoLayoutConfig {
        VideoLayoutConfig(
            aspectRatio: aspectRatio,
            mode: mode,
            arrangement: arrangement,
            stackedOpacity: mode == .stacked ? stackedOpacity : nil,
            transforms: transforms
        )
    }

    // MARK: - Shared Player

    func attach() {
        previewAudio()
        showFramedSwing()
        comparison.play()
    }

    func detach() {
        comparison.pause()
        comparison.restoreDefaultAudio()
    }

    func hasSound(atPosition position: Int) -> Bool {
        comparison.hasSound(atPosition: position)
    }

    private func previewAudio() {
        comparison.previewAudio(mutedAtPosition: transforms.map(\.isMuted))
    }

    /// A sequential timeline plays one swing at a time; picking a swing to frame jumps
    /// to its turn so it is moving, not frozen.
    private func showFramedSwing() {
        guard mode.playsSequentially else { return }
        comparison.showSequentialSegment(comparison.trackOrder[framedPosition])
    }
}
