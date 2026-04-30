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
}
