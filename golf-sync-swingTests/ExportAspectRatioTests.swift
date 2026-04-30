//
//  ExportAspectRatioTests.swift
//  golf-sync-swingTests
//

import Testing
import CoreGraphics
@testable import golf_sync_swing

struct ExportAspectRatioTests {

    @Test("Side-by-side is 16:9 horizontal")
    func sideBySideIsLandscape() {
        let preset = ExportAspectRatio.sideBySide
        #expect(preset.exportSize == CGSize(width: 1920, height: 1080))
        #expect(preset.arrangement == .horizontal)
        #expect(abs(preset.ratio - (16.0 / 9.0)) < 0.001)
    }

    @Test("Vertical TikTok is 9:16 vertical")
    func tikTokIsPortrait() {
        let preset = ExportAspectRatio.tikTokVertical
        #expect(preset.exportSize == CGSize(width: 1080, height: 1920))
        #expect(preset.arrangement == .vertical)
    }

    @Test("Square is 1:1 horizontal arrangement by default")
    func squareIsHorizontal() {
        let preset = ExportAspectRatio.square
        #expect(preset.exportSize == CGSize(width: 1080, height: 1080))
        #expect(preset.arrangement == .horizontal)
    }

    @Test("Arrangement derives from aspect: wide → horizontal, tall → vertical")
    func arrangementMatchesAspect() {
        for preset in ExportAspectRatio.allCases {
            if preset.exportSize.width > preset.exportSize.height {
                #expect(preset.arrangement == .horizontal, "Expected horizontal for \(preset.displayName)")
            } else if preset.exportSize.width < preset.exportSize.height {
                #expect(preset.arrangement == .vertical, "Expected vertical for \(preset.displayName)")
            } else {
                #expect(preset.arrangement == .horizontal, "Square defaults to horizontal")
            }
        }
    }

    @Test("Export sizes are even (codec-friendly)")
    func exportSizesEven() {
        for preset in ExportAspectRatio.allCases {
            #expect(Int(preset.exportSize.width) % 2 == 0, "\(preset.displayName) width odd")
            #expect(Int(preset.exportSize.height) % 2 == 0, "\(preset.displayName) height odd")
        }
    }

    @Test("All cases have non-empty display names")
    func displayNamesNotEmpty() {
        for preset in ExportAspectRatio.allCases {
            #expect(!preset.displayName.isEmpty)
        }
    }
}
