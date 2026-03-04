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

    // MARK: - Path Resolution

    static var documentsDirectory: URL {
        // Safe: iOS sandbox guarantees documentDirectory exists
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// The URL for the video file.
    /// Handles both legacy absolute paths and new relative paths.
    var localURL: URL {
        guard !localURLString.hasPrefix("/") else {
            return URL(fileURLWithPath: localURLString)
        }
        return Self.documentsDirectory.appendingPathComponent(localURLString)
    }

    /// Whether the video file exists on disk
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: localURL.path)
    }

    /// Safe URL access - returns nil if file doesn't exist
    var validLocalURL: URL? {
        guard fileExists else { return nil }
        return localURL
    }

    /// File size in bytes, or nil if file doesn't exist
    var fileSize: Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path),
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
        self.localURLString = Self.relativePath(for: localURL)
        self.duration = duration
        self.fps = fps
        self.thumbnailData = thumbnailData
    }

    // MARK: - Private

    /// Convert an absolute URL to a path relative to Documents directory.
    /// Returns the path unchanged if it's outside the Documents directory.
    private static func relativePath(for url: URL) -> String {
        let documentsPath = documentsDirectory.path
        let absolutePath = url.path
        guard absolutePath.hasPrefix(documentsPath) else { return absolutePath }
        let relative = String(absolutePath.dropFirst(documentsPath.count))
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
    }
}
