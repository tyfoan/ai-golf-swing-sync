//
//  VideoStorageService.swift
//  golf-sync-swing
//

import Foundation
import AVFoundation
import SwiftData
import os

final class VideoStorageService {
    static let shared = VideoStorageService()
    private init() {}

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var videosDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("Videos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// Copy video from source URL to app's Documents directory
    func copyVideoToStorage(from sourceURL: URL) throws -> URL {
        let uniqueID = UUID().uuidString
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destinationURL = videosDirectory.appendingPathComponent("\(uniqueID).\(fileExtension)")

        // Get source file size for verification
        let sourceAttributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let sourceSize = sourceAttributes[.size] as? Int64 ?? 0
        AppLogger.storage.debug("Source video size: \(sourceSize) bytes (\(Double(sourceSize) / 1_000_000) MB)")

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        // Verify destination file size matches
        let destAttributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let destSize = destAttributes[.size] as? Int64 ?? 0
        AppLogger.storage.debug("Copied video size: \(destSize) bytes")

        guard sourceSize == destSize else {
            throw NSError(
                domain: "VideoStorageService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Video copy incomplete: source \(sourceSize) bytes, destination \(destSize) bytes"]
            )
        }

        return destinationURL
    }

    /// Get video metadata (duration, fps)
    func getVideoMetadata(from url: URL) async -> (duration: TimeInterval, fps: Double) {
        let asset = AVURLAsset(url: url)

        var duration: TimeInterval = 0
        var fps: Double = 30.0

        do {
            // Load asset duration
            let durationValue = try await asset.load(.duration)
            let assetDuration = CMTimeGetSeconds(durationValue)
            AppLogger.storage.debug("Asset duration: \(assetDuration)s (flags: \(durationValue.flags.rawValue))")

            // Also check video track duration as fallback
            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                fps = Double(nominalFrameRate)

                // Get track duration as well
                let trackTimeRange = try await videoTrack.load(.timeRange)
                let trackDuration = CMTimeGetSeconds(trackTimeRange.duration)
                AppLogger.storage.debug("Video track duration: \(trackDuration)s, fps: \(fps)")

                // Use the longer of asset or track duration (sometimes asset is wrong)
                duration = max(assetDuration, trackDuration)

                // If duration still seems wrong (very short for file size), estimate from file
                if duration < 5 {
                    // Rough estimate: 66MB at 30fps 1080p ≈ 84 seconds
                    // Average bitrate for 1080p30 is ~8Mbps = 1MB/s
                    if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                        let estimatedDuration = Double(fileSize) / 1_000_000 // ~1MB per second
                        AppLogger.storage.warning("Duration seems wrong, estimated from file size: \(estimatedDuration)s")
                        // Don't override, just log for debugging
                    }
                }
            } else {
                duration = assetDuration
            }

            // Ensure duration is valid
            if duration.isNaN || duration.isInfinite || duration <= 0 {
                AppLogger.storage.warning("Invalid duration detected: \(duration)")
                duration = 0
            }
        } catch {
            AppLogger.storage.error("Error loading video metadata: \(error.localizedDescription)")
        }

        AppLogger.storage.debug("Final metadata: duration=\(duration)s, fps=\(fps)")
        return (duration, fps)
    }

    /// Delete video file from storage
    func deleteVideo(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Create SwingVideo model from local URL
    func createSwingVideo(from localURL: URL) async -> SwingVideo {
        let metadata = await getVideoMetadata(from: localURL)
        let thumbnailData = ThumbnailService.shared.generateThumbnail(for: localURL)

        return SwingVideo(
            localURL: localURL,
            duration: metadata.duration,
            fps: metadata.fps,
            thumbnailData: thumbnailData
        )
    }
}
