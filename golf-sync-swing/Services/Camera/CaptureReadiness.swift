//
//  CaptureReadiness.swift
//  golf-sync-swing
//
//  How much of the capture graph a bring-up must deliver.
//

import Foundation

/// The phased bring-up's contract.
///
/// `.preview` is the minimal graph — video input plus video-data output, no audio anywhere.
/// It exists because of a measurement: on device, the full graph's cold `startRunning` took
/// 15.5–21.5 s while the audio route negotiated (`FigAudioSession err=-19224` bracketing the
/// wait), and none of that work produces a pixel. The Camera tab asks for this.
///
/// `.recording` additionally installs the recording half — the activated `.playAndRecord`
/// audio session, the microphone input, and the movie file output — whose cost the record
/// countdown hides behind its own five seconds. The countdown asks for this.
enum CaptureReadiness {
    case preview
    case recording

    var probeLabel: String {
        switch self {
        case .preview: return "preview"
        case .recording: return "recording"
        }
    }
}
