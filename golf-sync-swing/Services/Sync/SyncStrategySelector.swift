//
//  SyncStrategySelector.swift
//  golf-sync-swing
//
//  Selects the best sync strategy based on available sync points
//  (impact, backswing) and their agreement/disagreement.
//

import Foundation

struct SyncStrategySelector {

    func selectBestSync(
        impactOffset: (offset: TimeInterval?, confidence: Double),
        backswingOffset: (offset: TimeInterval?, confidence: Double),
        tempo: TempoAnalysis
    ) -> SyncResult {
        // Case 1: Both sync points available
        if let impact = impactOffset.offset,
           let backswing = backswingOffset.offset {
            return selectWithBothPoints(
                impact: impact, impactConfidence: impactOffset.confidence,
                backswing: backswing, backswingConfidence: backswingOffset.confidence,
                tempo: tempo
            )
        }

        // Case 2: Only impact
        if let impact = impactOffset.offset {
            return SyncResult(
                offset: impact,
                confidence: impactOffset.confidence,
                description: impactOffset.confidence >= 0.7 ? "Synced at ball impact" : "Synced at impact (medium confidence)",
                primarySyncPoint: .impact,
                secondaryOffset: nil,
                tempoMatch: tempo.match,
                video2PlaybackSpeed: tempo.speedAdjustment,
                video1DownswingDuration: tempo.duration1,
                video2DownswingDuration: tempo.duration2
            )
        }

        // Case 3: Only backswing
        if let backswing = backswingOffset.offset {
            return SyncResult(
                offset: backswing,
                confidence: backswingOffset.confidence * 0.8,
                description: "Synced at top of backswing (no impact detected)",
                primarySyncPoint: .topOfBackswing,
                secondaryOffset: nil,
                tempoMatch: tempo.match,
                video2PlaybackSpeed: tempo.speedAdjustment,
                video1DownswingDuration: tempo.duration1,
                video2DownswingDuration: tempo.duration2
            )
        }

        // Case 4: Nothing detected
        return SyncResult(
            offset: 0, confidence: 0,
            description: "Could not detect sync points - manual alignment required",
            primarySyncPoint: .impact, secondaryOffset: nil, tempoMatch: nil,
            video2PlaybackSpeed: 1.0
        )
    }

    // MARK: - Private

    private func selectWithBothPoints(
        impact: TimeInterval, impactConfidence: Double,
        backswing: TimeInterval, backswingConfidence: Double,
        tempo: TempoAnalysis
    ) -> SyncResult {
        let offsetDiff = abs(impact - backswing)

        if offsetDiff < 0.15 {
            return SyncResult(
                offset: impact,
                confidence: min(1.0, (impactConfidence + backswingConfidence) / 2 + 0.1),
                description: "High confidence sync - impact and backswing aligned",
                primarySyncPoint: .impact, secondaryOffset: backswing,
                tempoMatch: tempo.match, video2PlaybackSpeed: tempo.speedAdjustment,
                video1DownswingDuration: tempo.duration1, video2DownswingDuration: tempo.duration2
            )
        }

        if offsetDiff < 0.3 {
            let weightedOffset = (impact * impactConfidence + backswing * backswingConfidence) / (impactConfidence + backswingConfidence)
            return SyncResult(
                offset: weightedOffset,
                confidence: (impactConfidence + backswingConfidence) / 2 * 0.85,
                description: "Medium confidence - slight tempo difference between swings",
                primarySyncPoint: .impact, secondaryOffset: backswing,
                tempoMatch: tempo.match, video2PlaybackSpeed: tempo.speedAdjustment,
                video1DownswingDuration: tempo.duration1, video2DownswingDuration: tempo.duration2
            )
        }

        return SyncResult(
            offset: impact,
            confidence: impactConfidence * 0.7,
            description: "Different tempos - synced at impact with speed adjustment",
            primarySyncPoint: .impact, secondaryOffset: backswing,
            tempoMatch: tempo.match, video2PlaybackSpeed: tempo.speedAdjustment,
            video1DownswingDuration: tempo.duration1, video2DownswingDuration: tempo.duration2
        )
    }
}
