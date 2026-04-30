//
//  ExportLayoutRendererTests.swift
//  golf-sync-swingTests
//

import Testing
import CoreGraphics
@testable import golf_sync_swing

struct ExportLayoutRendererTests {

    @Test("Identity transform: 1080x1920 video aspect-fit into 1080x960 cell yields contain")
    func identityAspectFit() {
        let videoSize = CGSize(width: 1080, height: 1920)
        let cellRect = CGRect(x: 0, y: 0, width: 1080, height: 960)
        let identity = VideoTransform()

        let t = ExportLayoutRenderer.transform(
            videoSize: videoSize,
            preferredTransform: .identity,
            cellRect: cellRect,
            userTransform: identity
        )

        // Aspect-fit scale = min(1080/1080, 960/1920) = 0.5
        #expect(abs(t.a - 0.5) < 0.001)
        #expect(abs(t.d - 0.5) < 0.001)

        // Center the scaled video (540×960) in the cell (1080×960):
        // x: (1080-540)/2 = 270; y: 0
        #expect(abs(t.tx - 270) < 0.5)
        #expect(abs(t.ty - 0) < 0.5)
    }

    @Test("User scale 2x doubles the effective scale of the transform")
    func userScaleMultipliesAspectFit() {
        let videoSize = CGSize(width: 1080, height: 1920)
        let cellRect = CGRect(x: 0, y: 0, width: 1080, height: 960)

        var user = VideoTransform()
        user.scale = 2.0
        user.containerSize = CGSize(width: 200, height: 178)

        let t = ExportLayoutRenderer.transform(
            videoSize: videoSize,
            preferredTransform: .identity,
            cellRect: cellRect,
            userTransform: user
        )

        // Aspect-fit (0.5) × user scale (2.0) = 1.0
        #expect(abs(t.a - 1.0) < 0.001)
        #expect(abs(t.d - 1.0) < 0.001)
    }

    @Test("User pan offset translates content within the cell")
    func userPanOffsetTranslates() {
        let videoSize = CGSize(width: 1080, height: 1920)
        let cellRect = CGRect(x: 0, y: 0, width: 1080, height: 960)

        var user = VideoTransform()
        user.offset = CGPoint(x: 50, y: 0) // 50pt right in preview
        user.containerSize = CGSize(width: 200, height: 178)

        let t = ExportLayoutRenderer.transform(
            videoSize: videoSize,
            preferredTransform: .identity,
            cellRect: cellRect,
            userTransform: user
        )

        // 50pt of 200pt preview = 25%, applied to 1080pt cell → 270pt right.
        // Identity baseline tx was 270 (centered); pan adds 270 → 540.
        #expect(abs(t.tx - 540) < 1.0)
    }

    @Test("Cell offset within render canvas is honored")
    func cellOriginIsRespected() {
        let videoSize = CGSize(width: 1080, height: 1920)
        // Bottom half of vertical TikTok layout
        let cellRect = CGRect(x: 0, y: 960, width: 1080, height: 960)
        let identity = VideoTransform()

        let t = ExportLayoutRenderer.transform(
            videoSize: videoSize,
            preferredTransform: .identity,
            cellRect: cellRect,
            userTransform: identity
        )

        // Vertical center of bottom cell = 960 + 480 = 1440. Aspect-fit centered there.
        // Y-translate should land scaled video centered in the bottom cell.
        // Scaled video height = 960; top of video at y=960; ty = 960.
        #expect(abs(t.ty - 960) < 1.0)
    }
}
