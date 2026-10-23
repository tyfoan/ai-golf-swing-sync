//
//  ComparisonBuildFailureLog.swift
//  golf-sync-swing
//
//  Writes down why a comparison could not be built.
//
//  The user reads the same sentence whichever way the build failed — there is nothing
//  they can do about an AVFoundation insertion error — but the REASON has to survive
//  somewhere. A bare nil is what made "comparison is broken" a report with no possible
//  follow-up: the log line and the DEBUG timeline name the failing side and say whether
//  the file, the movie, or the marker was at fault.
//

import Foundation
import os

struct ComparisonBuildFailureLog {
    let video1: SwingVideo
    let video2: SwingVideo
    let swing1: SwingTimeRange
    let swing2: SwingTimeRange

    /// The one sentence the comparison screen shows, whatever the reason.
    static var userMessage: String {
        String(localized: "Couldn't load these videos. They may have been moved or deleted.", comment: "Error shown on the comparison screen when the two swing videos fail to load for playback")
    }

    func record(_ failure: ComparisonBuildFailure, mode: ComparisonMode) {
        let detail = failure.diagnosticDetail ?? "none"
        // `.public`: the point of a reason is reading it off a device log, and an
        // interpolated string is redacted to <private> by default.
        AppLogger.sync.error("ComparisonViewModel: build failed reason=\(failure.probeReason, privacy: .public) detail=\(detail, privacy: .public)")
        #if DEBUG
        DeviceProbe.event("comparison_build_failed", probeFields(failure, detail: detail, mode: mode), ui: true)
        #endif
    }

    #if DEBUG
    private func probeFields(_ failure: ComparisonBuildFailure, detail: String, mode: ComparisonMode) -> [String: String] {
        [
            "reason": failure.probeReason,
            "detail": detail,
            "mode": mode.rawValue,
            // The two inputs the reason has to be read against: whether each file is still
            // there, and what its marker asked for.
            "file1_exists": String(video1.fileExists),
            "file2_exists": String(video2.fileExists),
            "swing1_s": Self.rangeLabel(swing1),
            "swing2_s": Self.rangeLabel(swing2)
        ]
    }

    private static func rangeLabel(_ range: SwingTimeRange) -> String {
        String(format: "%.2f/%.2f/%.2f", range.startTime, range.contactTime, range.endTime)
    }
    #endif
}
