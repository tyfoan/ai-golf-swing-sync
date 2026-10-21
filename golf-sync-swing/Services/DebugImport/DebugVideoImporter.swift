//
//  DebugVideoImporter.swift
//  golf-sync-swing
//
//  DEBUG-only. Imports a picked video the way VideoImportService does (copy into
//  app storage, build the SwingVideo), then runs it through the live swing
//  detector. Markers come only from detection: a file where nothing is detected
//  is saved with no swings, never with guessed ones.
//

#if DEBUG

import Foundation
import SwiftData

struct DebugVideoImporter {

    private let storage: VideoStorageService

    init(storage: VideoStorageService = .shared) {
        self.storage = storage
    }

    func importVideo(from pickedURL: URL, into context: ModelContext) async throws -> VideoFileSwingDetector.Report {
        let storedURL = try storage.copyVideoToStorage(from: pickedURL)
        let video = await storage.createSwingVideo(from: storedURL)
        let report = try await VideoFileSwingDetector().detectSwings(in: storedURL)
        context.insert(video)
        attach(report.clips, to: video, in: context)
        try context.save()
        try? FileManager.default.removeItem(at: pickedURL)
        return report
    }

    private func attach(_ clips: [SwingClip], to video: SwingVideo, in context: ModelContext) {
        video.hasBeenAnalyzed = !clips.isEmpty
        video.analysisDate = clips.isEmpty ? nil : Date()
        for clip in clips {
            let marker = marker(for: clip, within: video.duration)
            marker.video = video
            context.insert(marker)
        }
    }

    /// Same trimming as RecordingViewModel.swingMarker(for:within:): a marker never names
    /// footage past the end of the file. Duplicated rather than shared so this DEBUG-only
    /// path leaves release code untouched.
    private func marker(for clip: SwingClip, within duration: TimeInterval) -> SwingMarker {
        let limit = duration > 0 ? duration : clip.endTime
        let marker = SwingMarker(
            startTime: min(clip.startTime, limit),
            contactTime: min(clip.impactTime, limit),
            endTime: min(clip.endTime, limit)
        )
        marker.isAutoDetected = true
        marker.detectionConfidence = clip.confidence
        return marker
    }
}

#endif
