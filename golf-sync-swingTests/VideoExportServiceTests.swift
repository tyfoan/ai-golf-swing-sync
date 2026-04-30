//
//  VideoExportServiceTests.swift
//  golf-sync-swingTests
//

import Testing
@testable import golf_sync_swing

struct VideoExportServiceTests {

    @Test("Without trim, the original (absolute-time) syncOffset is preserved")
    func passesThroughWhenNotTrimming() {
        let result = VideoExportService.effectiveSyncOffset(
            originalSyncOffset: 5.5,
            swingTrim: nil
        )
        #expect(abs(result - 5.5) < 0.001)
    }

    @Test("With trim, syncOffset is converted to slice-relative contact-difference")
    func recomputesWhenTrimming() {
        // s1: start=10, contact=11.5 → slice contact = 1.5
        // s2: start=5,  contact=6.0  → slice contact = 1.0
        // Slice-relative offset = 1.5 - 1.0 = 0.5
        let s1 = SwingTimeRange(startTime: 10.0, contactTime: 11.5, endTime: 13.0)
        let s2 = SwingTimeRange(startTime: 5.0,  contactTime: 6.0,  endTime: 8.0)

        let result = VideoExportService.effectiveSyncOffset(
            originalSyncOffset: 5.5,        // absolute (would be wrong after trim)
            swingTrim: (s1, s2)
        )

        #expect(abs(result - 0.5) < 0.001)
    }

    @Test("With trim and identical contact gaps, slice-relative offset is zero")
    func zeroOffsetWhenContactGapsMatch() {
        // Both swings have contact 1s past their start → no slice-relative offset
        let s1 = SwingTimeRange(startTime: 10.0, contactTime: 11.0, endTime: 13.0)
        let s2 = SwingTimeRange(startTime: 5.0,  contactTime: 6.0,  endTime: 8.0)

        let result = VideoExportService.effectiveSyncOffset(
            originalSyncOffset: 5.0,
            swingTrim: (s1, s2)
        )

        #expect(abs(result - 0.0) < 0.001)
    }
}
