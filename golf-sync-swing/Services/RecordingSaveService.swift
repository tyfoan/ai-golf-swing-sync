//
//  RecordingSaveService.swift
//  golf-sync-swing
//
//  Saves a recorded video and its detected swings to SwiftData.
//

import Foundation
import SwiftData

struct RecordingSaveService {

    func save(
        sourceURL: URL,
        swings: [SwingClip],
        expectedDuration: TimeInterval,
        modelContext: ModelContext
    ) async throws -> SwingVideo {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw RecordingSaveError.fileNotFound
        }

        try? await Task.sleep(for: .milliseconds(500))
        let permanentURL = try VideoStorageService.shared.copyVideoToStorage(from: sourceURL)
        var video = await VideoStorageService.shared.createSwingVideo(from: permanentURL)

        if abs(video.duration - expectedDuration) > 5.0 && expectedDuration > 0 {
            video.duration = expectedDuration
        }

        for clip in swings {
            let marker = SwingMarker(
                startTime: clip.startTime, contactTime: clip.impactTime, endTime: clip.endTime
            )
            marker.isAutoDetected = true
            marker.detectionConfidence = clip.confidence
            marker.video = video
            video.swings.append(marker)
        }

        modelContext.insert(video)
        try? FileManager.default.removeItem(at: sourceURL)

        return video
    }
}

enum RecordingSaveError: LocalizedError {
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "Recording file not found"
        }
    }
}
