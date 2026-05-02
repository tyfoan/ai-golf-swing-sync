//
//  SingleVideoExportTests.swift
//  golf-sync-swingTests
//

import Testing
import Foundation
import AVFoundation
@testable import golf_sync_swing

struct SingleVideoExportTests {

    @Test("Empty swings list still routes to a callback (full-video fallback)", .timeLimit(.minutes(1)))
    func emptySwingsFallsBack() async throws {
        // We cannot run an actual export in unit tests without a fixture video.
        // Instead, verify the input handling routes a callback.
        // The actual export pipeline is verified manually on device — see plan Task 16.
        let url = URL(fileURLWithPath: "/dev/null")
        await withCheckedContinuation { continuation in
            VideoExportService.exportSingleVideo(
                videoURL: url, swings: nil,
                progress: { _ in },
                completion: { result in
                    if case .failure(let err) = result {
                        // /dev/null is not a video — we expect ExportError, not crash
                        #expect(err.errorDescription != nil)
                    }
                    continuation.resume()
                }
            )
        }
    }
}
