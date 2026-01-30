//
//  VideoStorageService.swift
//  golf-sync-swing
//

import Foundation
import AVFoundation
import SwiftData

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

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    /// Get video metadata (duration, fps)
    func getVideoMetadata(from url: URL) async -> (duration: TimeInterval, fps: Double) {
        let asset = AVAsset(url: url)

        var duration: TimeInterval = 0
        var fps: Double = 30.0

        do {
            let durationValue = try await asset.load(.duration)
            duration = CMTimeGetSeconds(durationValue)

            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                fps = Double(nominalFrameRate)
            }
        } catch {
            print("Error loading video metadata: \(error)")
        }

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
