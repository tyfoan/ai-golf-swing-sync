//
//  CrossCorrelationRefiner.swift
//  golf-sync-swing
//
//  Refines sync offset using velocity profile cross-correlation
//  for sub-frame alignment accuracy.
//

import Foundation

struct CrossCorrelationRefiner {

    func refine(
        baseResult: SyncResult,
        profile1: [VelocityPoint],
        profile2: [VelocityPoint]
    ) -> SyncResult {
        guard profile1.count >= 20, profile2.count >= 20 else {
            return baseResult
        }

        guard let impact1 = profile1.first(where: { abs($0.timestamp - (profile1.last?.timestamp ?? 0) * 0.6) < 0.5 }),
              let impact2 = profile2.first(where: { abs($0.timestamp - (profile2.last?.timestamp ?? 0) * 0.6) < 0.5 }) else {
            return baseResult
        }

        let window1 = profile1.filter {
            $0.timestamp >= impact1.timestamp - 0.5 && $0.timestamp <= impact1.timestamp + 0.5
        }
        let window2 = profile2.filter {
            $0.timestamp >= impact2.timestamp - 0.5 && $0.timestamp <= impact2.timestamp + 0.5
        }

        guard window1.count >= 10, window2.count >= 10 else {
            return baseResult
        }

        let velocities1 = normalizeArray(window1.map { $0.velocity })
        let velocities2 = normalizeArray(window2.map { $0.velocity })
        let correlation = crossCorrelation(signal1: velocities1, signal2: velocities2)

        guard let peakIndex = correlation.enumerated().max(by: { $0.element < $1.element })?.offset else {
            return baseResult
        }

        let centerIndex = correlation.count / 2
        let frameOffset = peakIndex - centerIndex
        let avgFrameDuration = (window1.last!.timestamp - window1.first!.timestamp) / Double(window1.count - 1)
        let refinementOffset = Double(frameOffset) * avgFrameDuration

        let peakCorrelation = correlation[peakIndex]
        guard abs(refinementOffset) < 0.1 && peakCorrelation > 0.7 else {
            return baseResult
        }

        return SyncResult(
            offset: baseResult.offset + refinementOffset,
            confidence: min(1.0, baseResult.confidence + (peakCorrelation - 0.7) * 0.2),
            description: baseResult.description + " (cross-correlation refined)",
            primarySyncPoint: baseResult.primarySyncPoint,
            secondaryOffset: baseResult.secondaryOffset,
            tempoMatch: baseResult.tempoMatch,
            video2PlaybackSpeed: baseResult.video2PlaybackSpeed,
            video1DownswingDuration: baseResult.video1DownswingDuration,
            video2DownswingDuration: baseResult.video2DownswingDuration
        )
    }

    // MARK: - Private

    private func normalizeArray(_ array: [Double]) -> [Double] {
        guard !array.isEmpty else { return array }
        let mean = array.reduce(0, +) / Double(array.count)
        let variance = array.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(array.count)
        let stdDev = sqrt(variance)
        guard stdDev > 0.001 else { return array.map { _ in 0 } }
        return array.map { ($0 - mean) / stdDev }
    }

    private func crossCorrelation(signal1: [Double], signal2: [Double]) -> [Double] {
        let n1 = signal1.count
        let n2 = signal2.count
        let resultLength = n1 + n2 - 1
        var result = [Double](repeating: 0, count: resultLength)

        for lag in 0..<resultLength {
            var sum: Double = 0
            var count: Double = 0
            for i in 0..<n1 {
                let j = i + lag - n1 + 1
                if j >= 0 && j < n2 {
                    sum += signal1[i] * signal2[j]
                    count += 1
                }
            }
            result[lag] = count > 0 ? sum / count : 0
        }

        return result
    }
}
