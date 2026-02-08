//
//  SwingAutoDetectionRunner.swift
//  golf-sync-swing
//
//  Runs auto-detection on a video, updates model context with results.
//

import Foundation
import SwiftData

@Observable
final class SwingAutoDetectionRunner {
    private(set) var isAnalyzing = false
    private(set) var progress: Float = 0
    private(set) var status: String = ""

    private let syncEngine = VideoSyncEngine()

    func analyze(video: SwingVideo, context: ModelContext) async -> [SwingMarker] {
        await MainActor.run {
            isAnalyzing = true
            progress = 0.02
            status = "Detecting swings..."
        }

        do {
            let results = try await syncEngine.analyzeAllSwings(
                for: video
            ) { [weak self] p in
                // Ensure visible progress even on first frames (2%-100%)
                let adjusted = 0.02 + p * 0.98
                Task { @MainActor in self?.progress = adjusted }
            }
            return await applyResults(results, video: video, context: context)
        } catch {
            await MainActor.run { isAnalyzing = false }
            return []
        }
    }

    @MainActor
    private func applyResults(
        _ results: [SwingDetectionResult],
        video: SwingVideo,
        context: ModelContext
    ) -> [SwingMarker] {
        removeAutoDetected(from: video, context: context)
        let newSwings = insertDetected(results, into: video, context: context)
        isAnalyzing = false
        return newSwings
    }

    private func removeAutoDetected(from video: SwingVideo, context: ModelContext) {
        let autoDetected = video.swings.filter { $0.isAutoDetected }
        for swing in autoDetected {
            video.swings.removeAll { $0.id == swing.id }
            context.delete(swing)
        }
    }

    private func insertDetected(
        _ results: [SwingDetectionResult],
        into video: SwingVideo,
        context: ModelContext
    ) -> [SwingMarker] {
        var inserted: [SwingMarker] = []
        for result in results where result.hasValidDetection {
            let swing = SwingMarker(from: result)
            swing.video = video
            video.swings.append(swing)
            context.insert(swing)
            inserted.append(swing)
        }
        return inserted
    }
}
