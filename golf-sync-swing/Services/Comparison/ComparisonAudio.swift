//
//  ComparisonAudio.swift
//  golf-sync-swing
//
//  The comparison composition's sound, kept by swing: at most one audio track per video
//  track, and none at all for a silent clip (every bundled pro swing is silent). A mix
//  that mutes one swing therefore never has to guess which audio track is whose.
//

import AVFoundation

struct ComparisonAudio {
    /// Indexed like the composition's video tracks; nil where that swing has no sound.
    let tracks: [AVCompositionTrack?]

    func hasSound(track index: Int) -> Bool {
        tracks.indices.contains(index) && tracks[index] != nil
    }

    /// Plays the tracks whose `muted` entry is false. `muted` is indexed like `tracks`.
    func mix(muted: [Bool]) -> AVAudioMix {
        let mix = AVMutableAudioMix()
        mix.inputParameters = zip(tracks, muted).compactMap { track, isMuted in
            track.map { Self.parameters(for: $0, volume: isMuted ? 0 : 1) }
        }
        return mix
    }

    /// Playback's default: one clean impact — the first swing that has sound, alone.
    var defaultMix: AVAudioMix {
        let audible = tracks.firstIndex { $0 != nil }
        return mix(muted: tracks.indices.map { $0 != audible })
    }

    private static func parameters(for track: AVCompositionTrack, volume: Float) -> AVAudioMixInputParameters {
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.setVolume(volume, at: .zero)
        return parameters
    }
}
