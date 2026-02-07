//
//  VideoFrameIterator.swift
//  golf-sync-swing
//
//  Iterates through video frames at a target FPS, calling a process closure
//  for each frame. Handles AVAssetReader setup, time range clamping,
//  and progress reporting.
//

import AVFoundation
import Foundation

struct VideoFrameIterator {

    func forEachFrame(
        at url: URL,
        timeRangeSeconds: ClosedRange<TimeInterval>?,
        targetFPS: Double,
        progress: @escaping (Float) -> Void,
        process: (CVPixelBuffer, TimeInterval) -> Bool
    ) async throws {
        let asset = AVURLAsset(url: url)
        let durationSeconds = try await asset.load(.duration).seconds
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw SyncEngineError.analysisFailure("No video track")
        }

        let reader = try AVAssetReader(asset: asset)

        let clampedRange: ClosedRange<TimeInterval>? = timeRangeSeconds.flatMap { range in
            let start = max(0, range.lowerBound)
            let end = min(durationSeconds, range.upperBound)
            guard end > start else { return nil }
            return start...end
        }

        if let range = clampedRange {
            let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
            let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
            reader.timeRange = CMTimeRange(start: start, duration: CMTimeSubtract(end, start))
        }

        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]

        let output = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: settings)
        output.videoComposition = AVMutableVideoComposition(propertiesOf: asset)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? SyncEngineError.analysisFailure("Failed to start video reader")
        }

        let progressStart = clampedRange?.lowerBound ?? 0
        let progressEnd = clampedRange?.upperBound ?? durationSeconds
        let progressSpan = max(0.001, progressEnd - progressStart)
        let minFrameInterval = 1.0 / max(1.0, targetFPS)
        var lastProcessedTimestamp = -Double.greatestFiniteMagnitude

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            if timestamp - lastProcessedTimestamp < minFrameInterval { continue }
            lastProcessedTimestamp = timestamp

            let clampedTime = max(progressStart, min(progressEnd, timestamp))
            progress(Float((clampedTime - progressStart) / progressSpan))

            if process(pixelBuffer, timestamp) {
                reader.cancelReading()
                break
            }
        }

        if reader.status == .failed {
            throw reader.error ?? SyncEngineError.analysisFailure("Video reader failed")
        }

        progress(1.0)
    }
}
