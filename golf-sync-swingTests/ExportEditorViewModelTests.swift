//
//  ExportEditorViewModelTests.swift
//  golf-sync-swingTests
//

import Testing
import CoreGraphics
@testable import golf_sync_swing

struct ExportEditorViewModelTests {

    @Test("Default transforms: video1 unmuted, video2 muted")
    func defaultMuteState() {
        let vm = ExportEditorViewModel.makeForTesting(aspectRatio: .tikTokVertical)

        #expect(vm.transforms[0].isMuted == false)
        #expect(vm.transforms[1].isMuted == true)
    }

    @Test("buildLayoutConfig returns current state")
    func buildLayoutConfigReflectsState() {
        let vm = ExportEditorViewModel.makeForTesting(aspectRatio: .square)

        vm.transforms[0].scale = 1.5
        vm.transforms[1].isMuted = false

        let config = vm.buildLayoutConfig()

        #expect(config.aspectRatio == .square)
        #expect(config.transforms.count == 2)
        #expect(abs(config.transforms[0].scale - 1.5) < 0.001)
        #expect(config.transforms[1].isMuted == false)
    }

    @Test("Toggle mute mutates the right transform only")
    func toggleMuteIsolated() {
        let vm = ExportEditorViewModel.makeForTesting(aspectRatio: .sideBySide)
        let initial1 = vm.transforms[0].isMuted

        vm.toggleMute(at: 1)

        #expect(vm.transforms[0].isMuted == initial1)
        #expect(vm.transforms[1].isMuted == false) // was true by default → toggled to false
    }

    @Test("Player 2 sync seek aligns contact frames with player 1")
    func player2InitialPositionAlignsContact() {
        // s1: start 1.0, contact 2.5 (gap 1.5)
        // s2: start 0.5, contact 1.5 (gap 1.0)
        // Expected: video2 must start 0.5s "earlier" so its contact frame
        // coincides with video1's contact at the same editor wall-clock time.
        // Formula: 0.5 + 1.0 - 1.5 = 0.0
        let s1 = SwingTimeRange(startTime: 1.0, contactTime: 2.5, endTime: 4.0)
        let s2 = SwingTimeRange(startTime: 0.5, contactTime: 1.5, endTime: 3.0)

        let pos = ExportEditorViewModel.player2InitialPosition(s1: s1, s2: s2)

        #expect(abs(pos - 0.0) < 0.001)
    }

    @Test("Player 2 sync seek clamps to zero when formula goes negative")
    func player2InitialPositionClampsToZero() {
        // s1: start 0.0, contact 3.0 (gap 3.0)
        // s2: start 0.5, contact 1.0 (gap 0.5)
        // Formula: 0.5 + 0.5 - 3.0 = -2.0 → clamped to 0
        let s1 = SwingTimeRange(startTime: 0.0, contactTime: 3.0, endTime: 5.0)
        let s2 = SwingTimeRange(startTime: 0.5, contactTime: 1.0, endTime: 2.0)

        let pos = ExportEditorViewModel.player2InitialPosition(s1: s1, s2: s2)

        #expect(pos >= 0)
        #expect(abs(pos - 0.0) < 0.001)
    }
}
