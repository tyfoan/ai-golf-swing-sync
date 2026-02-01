//
//  SwingVideo.swift
//  golf-sync-swing
//

import Foundation
import SwiftData

@Model
final class SwingVideo {
    var id: UUID = UUID()
    var localURLString: String
    var createdAt: Date = Date()
    var duration: TimeInterval
    var fps: Double
    var thumbnailData: Data?

    // Auto-detection status
    var hasBeenAnalyzed: Bool = false
    var analysisDate: Date?

    @Relationship(deleteRule: .cascade) var swings: [SwingMarker] = []

    // MARK: - URL Access

    /// The URL for the video file
    var localURL: URL {
        URL(fileURLWithPath: localURLString)
    }

    /// Whether the video file exists on disk
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: localURLString)
    }

    /// Safe URL access - returns nil if file doesn't exist
    var validLocalURL: URL? {
        guard fileExists else { return nil }
        return localURL
    }

    /// File size in bytes, or nil if file doesn't exist
    var fileSize: Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: localURLString),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        return size
    }

    /// Human-readable file size (e.g., "12.5 MB")
    var formattedFileSize: String? {
        guard let bytes = fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Init

    init(localURL: URL, duration: TimeInterval, fps: Double, thumbnailData: Data? = nil) {
        self.localURLString = localURL.path
        self.duration = duration
        self.fps = fps
        self.thumbnailData = thumbnailData
    }

    // MARK: - Swing Detection

    /// Get the primary detected impact time (first auto-detected swing)
    var detectedImpactTime: TimeInterval? {
        swings.first { $0.isAutoDetected }?.contactTime
    }

    /// Check if video has a high-confidence auto-detected swing
    var hasHighConfidenceDetection: Bool {
        swings.contains { $0.isAutoDetected && $0.detectionConfidence >= 0.7 }
    }
}
