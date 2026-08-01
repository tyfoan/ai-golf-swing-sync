//
//  CaptureExperiment.swift
//  golf-sync-swing
//
//  Which parts of the capture graph to build — a bisect harness for bring-up cost.
//

import Foundation

/// Every part of the capture graph is present by default. A DEBUG launch may omit one.
///
/// This exists because of a measurement: on device, app-side bring-up work totals ~50 ms while
/// `session.addInput(videoDevice)` takes 3.4 s and `startRunning()` takes 21.5 s. That time is
/// spent inside the capture stack, not in our code, and the only lever we have over it is WHAT WE
/// ASK THE STACK TO BUILD — three simultaneous consumers (preview layer, video-data output, movie
/// file output), a microphone, and cinematic stabilization are not the same request as a bare
/// preview. Which of them costs the 21 seconds is not answerable from a desk, and guessing one
/// knob per build is four device round-trips.
///
/// So: one build, one launch per hypothesis. Set `GSS_CAMERA_OMIT` in the scheme's environment to
/// a comma-separated list of `microphone`, `movie`, `videoData`, `stabilization`, `multitasking`,
/// and read `startRunning` off the CAMPERF line. `configure.experiment` names what was omitted, so
/// a fast run can never be misread as a fast device.
///
/// Omitting a part disables the feature that depends on it — no `movie` means no recording, no
/// `videoData` means no detection or skeleton. That is the point; these launches are measurements,
/// not sessions. Release builds ignore the variable: `omitted` is empty and every query is true.
struct CaptureExperiment {

    static let current = CaptureExperiment()

    private let omitted: Set<String>

    init() {
        #if DEBUG
        let requested = ProcessInfo.processInfo.environment["GSS_CAMERA_OMIT"] ?? ""
        omitted = Set(
            requested
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        #else
        omitted = []
        #endif
    }

    var includesMicrophone: Bool { includes("microphone") }
    var includesMovieOutput: Bool { includes("movie") }
    var includesVideoDataOutput: Bool { includes("videoData") }
    var includesStabilization: Bool { includes("stabilization") }
    var includesMultitaskingAccess: Bool { includes("multitasking") }

    // Audio-category knobs, one level below `microphone`. If the microphone input turns out to be
    // what costs the 21 seconds, the next question is immediately whether it is the input itself
    // or the category we hand it: `FigAudioSession(AV) err=-19224` brackets the slow `startRunning`
    // and disappears with the microphone, and both of these options are known to complicate route
    // negotiation for a `.playAndRecord` session that a capture session also has a microphone on.
    var includesMixWithOthers: Bool { includes("mixWithOthers") }
    var includesBluetoothAudio: Bool { includes("bluetooth") }

    /// Goes into the timing log next to the numbers it explains.
    var summary: String {
        omitted.isEmpty ? "full" : "omit=\(omitted.sorted().joined(separator: "+"))"
    }

    private func includes(_ part: String) -> Bool { !omitted.contains(part) }
}
