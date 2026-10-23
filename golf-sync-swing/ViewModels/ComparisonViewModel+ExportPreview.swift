//
//  ComparisonViewModel+ExportPreview.swift
//  golf-sync-swing
//
//  What the export editor asks of the comparison it was opened from. The editor
//  previews on the comparison's own player — the frames the stage already shows, so it
//  needs no decoders of its own — and asks here which track sits where, which swings
//  have sound to mute, and where a sequential swing's turn begins.
//

import AVFoundation

extension ComparisonViewModel {
    /// The composition track at each on-screen position, top or left (or first to play)
    /// first. A sequential timeline is already built in playing order.
    var trackOrder: [Int] {
        guard isSwapped, !comparisonMode.playsSequentially else { return [0, 1] }
        return [1, 0]
    }

    func hasSound(atPosition position: Int) -> Bool {
        composition?.audio.hasSound(track: trackOrder[position]) ?? false
    }

    /// Plays the editor's per-position mute choices through the shared player. A
    /// two-way order is its own inverse, so it also maps positions back to tracks.
    func previewAudio(mutedAtPosition muted: [Bool]) {
        guard let composition else { return }
        composition.playerItem.audioMix = composition.audio.mix(muted: trackOrder.map { muted[$0] })
    }

    func restoreDefaultAudio() {
        guard let composition else { return }
        composition.playerItem.audioMix = composition.audio.defaultMix
    }

    /// Jumps a sequential timeline to the start of a swing's turn.
    func showSequentialSegment(_ segment: Int) {
        guard let split = composition?.sequentialSplit else { return }
        seek(to: [0, split][segment])
    }
}
