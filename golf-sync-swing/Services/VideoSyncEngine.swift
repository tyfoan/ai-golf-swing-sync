//
//  VideoSyncEngine.swift
//  golf-sync-swing
//
//  Placeholder — auto-detection has been removed.
//  Manual sync via SwingTimeRange is handled by ComparisonViewModel.
//

import Foundation

final class VideoSyncEngine {

    func analyzeAllSwings(
        for video: SwingVideo,
        progress: @escaping (Float) -> Void
    ) async throws -> [SwingDetectionResult] {
        progress(1.0)
        return []
    }
}
