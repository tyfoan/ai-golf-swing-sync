//
//  SwingSegmenter.swift
//  golf-sync-swing
//
//  Segments a probability matrix into individual swing regions and extracts
//  event timestamps per segment. Uses two complementary strategies:
//
//  1. Valley-based: P(no-event) drops below threshold for sustained periods
//  2. Peak-based: Impact probability peaks above minimum confidence
//
//  This dual approach handles both pre-segmented single-swing clips (where
//  P(no-event) clearly valleys) and multi-swing compilation videos (where
//  peaks in event columns are more reliable than no-event valleys).
//

import Foundation
import os

// MARK: - Protocol

protocol SwingSegmenting: Sendable {
    func segment(probabilities: [[Float]], timestamps: [TimeInterval]) -> [SwingDetectionResult]
}

// MARK: - Implementation

struct SwingSegmenter: SwingSegmenting {

    private static let noEventIndex = 8
    private static let minSwingFrames = 30
    private static let noEventThreshold: Float = 0.5
    private static let smoothingWindow = 5
    private static let peakMinConfidence: Float = 0.15
    private static let peakMinSeparationFrames = 45

    // MARK: - Public

    func segment(probabilities: [[Float]], timestamps: [TimeInterval]) -> [SwingDetectionResult] {
        let valleyResults = segmentByValleys(probabilities: probabilities, timestamps: timestamps)
        guard valleyResults.isEmpty else { return valleyResults }

        let peakResults = segmentByPeaks(probabilities: probabilities, timestamps: timestamps)
        guard peakResults.isEmpty else { return peakResults }

        return singleSwingFallback(probabilities: probabilities, timestamps: timestamps)
    }

    // MARK: - Strategy 1: No-Event Valley Segmentation

    private func segmentByValleys(probabilities: [[Float]], timestamps: [TimeInterval]) -> [SwingDetectionResult] {
        let ranges = findValleyRanges(probabilities: probabilities)
        guard !ranges.isEmpty else { return [] }

        return ranges.compactMap { range in
            let result = extractEvents(
                probabilities: Array(probabilities[range]),
                timestamps: Array(timestamps[range])
            )
            return result.hasValidDetection ? result : nil
        }
    }

    private func findValleyRanges(probabilities: [[Float]]) -> [Range<Int>] {
        guard probabilities.count > Self.minSwingFrames else { return [] }

        let noEventProbs = probabilities.map { $0[Self.noEventIndex] }
        let smoothed = medianSmoothed(noEventProbs)
        return contiguousRanges(below: Self.noEventThreshold, in: smoothed)
    }

    // MARK: - Strategy 2: Impact Peak Segmentation

    private func segmentByPeaks(probabilities: [[Float]], timestamps: [TimeInterval]) -> [SwingDetectionResult] {
        let peaks = findImpactPeaks(probabilities: probabilities)
        guard !peaks.isEmpty else { return [] }

        return peaks.compactMap { peakFrame in
            let windowStart = max(0, peakFrame - Self.minSwingFrames)
            let windowEnd = min(probabilities.count, peakFrame + Self.minSwingFrames)
            let result = extractEvents(
                probabilities: Array(probabilities[windowStart..<windowEnd]),
                timestamps: Array(timestamps[windowStart..<windowEnd])
            )
            return result.hasValidDetection ? result : nil
        }
    }

    private func findImpactPeaks(probabilities: [[Float]]) -> [Int] {
        let impactProbs = probabilities.map { $0[SwingNetEvent.impact.rawValue] }
        let smoothed = medianSmoothed(impactProbs)
        return findPeaks(in: smoothed, minHeight: Self.peakMinConfidence, minSeparation: Self.peakMinSeparationFrames)
    }

    private func findPeaks(in values: [Float], minHeight: Float, minSeparation: Int) -> [Int] {
        var peaks: [Int] = []

        for i in 1..<(values.count - 1) {
            let isPeak = values[i] > values[i - 1] && values[i] > values[i + 1]
            let isHighEnough = values[i] >= minHeight
            let isFarEnough = peaks.last.map { i - $0 >= minSeparation } ?? true

            guard isPeak && isHighEnough && isFarEnough else { continue }
            peaks.append(i)
        }

        return peaks
    }

    // MARK: - Single Swing Fallback

    private func singleSwingFallback(probabilities: [[Float]], timestamps: [TimeInterval]) -> [SwingDetectionResult] {
        let result = extractEvents(probabilities: probabilities, timestamps: timestamps)
        return result.hasValidDetection ? [result] : []
    }

    // MARK: - Event Extraction

    private func extractEvents(probabilities: [[Float]], timestamps: [TimeInterval]) -> SwingDetectionResult {
        guard probabilities.count == timestamps.count, !probabilities.isEmpty else {
            return SwingDetectionResult(impactTime: nil, impactConfidence: 0, startTime: nil, endTime: nil)
        }

        let eventFrames = findEventFrames(probabilities: probabilities)
        let impactFrame = eventFrames[SwingNetEvent.impact.rawValue]
        let impactConfidence = Double(probabilities[impactFrame][SwingNetEvent.impact.rawValue])
        let impactTime = timestamps[impactFrame]

        let startTime = timestamps[eventFrames[SwingNetEvent.address.rawValue]]
        let endTime = timestamps[eventFrames[SwingNetEvent.finish.rawValue]]

        AppLogger.detection.info(
            "SwingNet: impact=\(impactFrame) (\(String(format: "%.2f", impactTime))s) conf=\(String(format: "%.3f", impactConfidence))"
        )

        return SwingDetectionResult(
            impactTime: impactTime,
            impactConfidence: impactConfidence,
            startTime: startTime,
            endTime: endTime
        )
    }

    private func findEventFrames(probabilities: [[Float]]) -> [Int] {
        (0..<8).map { eventIdx in
            probabilities.indices.max(by: {
                probabilities[$0][eventIdx] < probabilities[$1][eventIdx]
            }) ?? 0
        }
    }

    // MARK: - Signal Processing

    private func medianSmoothed(_ values: [Float]) -> [Float] {
        let half = Self.smoothingWindow / 2
        return values.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(values.count - 1, i + half)
            var window = Array(values[lo...hi])
            window.sort()
            return window[window.count / 2]
        }
    }

    private func contiguousRanges(below threshold: Float, in values: [Float]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var segmentStart: Int?

        for (i, value) in values.enumerated() {
            switch (segmentStart, value < threshold) {
            case (nil, true):
                segmentStart = i
            case (let start?, false):
                appendIfLongEnough(start: start, end: i, to: &ranges)
                segmentStart = nil
            default:
                break
            }
        }

        if let start = segmentStart {
            appendIfLongEnough(start: start, end: values.count, to: &ranges)
        }

        return ranges
    }

    private func appendIfLongEnough(start: Int, end: Int, to ranges: inout [Range<Int>]) {
        guard end - start >= Self.minSwingFrames else { return }
        ranges.append(start..<end)
    }
}
