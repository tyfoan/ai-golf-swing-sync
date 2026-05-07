//
//  ScreenshotDataService.swift
//  golf-sync-swing
//
//  Populates the database with demo videos and pre-set swing
//  markers for App Store screenshot capture. Debug-only.
//

#if DEBUG

import Foundation
import SwiftData

@Observable
final class ScreenshotDataService {
    static let shared = ScreenshotDataService()

    private(set) var loadState: LoadState = .idle

    private init() {}

    // MARK: - Load State

    enum LoadState {
        case idle
        case loading(Int, Int)
        case done(Int)
        case error(String)

        var label: String {
            switch self {
            case .idle:                  return "Not loaded"
            case .loading(let n, let t): return "Loading \(n)/\(t)..."
            case .done(let count):       return "\(count) videos ready"
            case .error(let msg):        return "Error: \(msg)"
            }
        }

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    // MARK: - Public

    func loadScreenshotData(context: ModelContext) async {
        let sources = bundleVideoPaths
        guard !sources.isEmpty else {
            loadState = .error("No demo videos in bundle")
            return
        }

        let entries = scheduleEntries(from: sources)
        loadState = .loading(0, entries.count)

        let storage = VideoStorageService.shared
        var loaded = 0

        for entry in entries {
            do {
                let destURL = try storage.copyVideoToStorage(from: entry.url)
                let video = await storage.createSwingVideo(from: destURL)
                video.createdAt = entry.date
                video.hasBeenAnalyzed = true
                video.analysisDate = entry.date

                // Demo clips are 1:30–2:00 long; middle of clip is reliably in the action
                // (t=0 is letterbox; preset contact times are seconds-not-percent and miss).
                let thumbnailTime = video.duration * 0.5
                if let betterThumbnail = ThumbnailService.shared.generateThumbnail(for: destURL, at: thumbnailTime) {
                    video.thumbnailData = betterThumbnail
                }

                context.insert(video)

                let marker = buildMarker(for: entry, videoDuration: video.duration)
                marker.video = video
                video.swings.append(marker)

                try context.save()
                loaded += 1
                loadState = .loading(loaded, entries.count)
            } catch {
                loadState = .error(error.localizedDescription)
                return
            }
        }

        loadState = .done(loaded)
    }

    // MARK: - Bundle Videos

    private var bundleVideoPaths: [URL] {
        ScreenshotVideoCatalog.all
    }

    // MARK: - Schedule

    private func scheduleEntries(from sources: [URL]) -> [ScheduleEntry] {
        ScreenshotSchedule.entries(from: sources)
    }

    // MARK: - Marker Builder

    private func buildMarker(for entry: ScheduleEntry, videoDuration: TimeInterval) -> SwingMarker {
        let timing = entry.timing

        // Demo clips are full YouTube clips with fade-in/letterbox at the start.
        // Center the swing window at the middle of the video so swing thumbnails
        // (extracted at contactTime in SwingThumbnailView) land on real content,
        // while preserving the preset's pre/post-contact balance.
        let preDuration = timing.contact - timing.start
        let postDuration = timing.end - timing.contact
        let contact = videoDuration * 0.5
        let start = max(0, contact - preDuration)
        let end = min(videoDuration, contact + postDuration)

        let marker = SwingMarker(startTime: start, contactTime: contact, endTime: end)
        marker.isAutoDetected = true
        marker.detectionConfidence = timing.confidence
        marker.isFavorite = entry.isFavorite
        return marker
    }
}

// MARK: - Video Catalog

private enum ScreenshotVideoCatalog {

    static let entries: [String] = [
        "31p1YZI_mrc.mp4",
        "7DR3pFxkPVg.mp4",
        "CAlO52kAYHE.mp4",
        "UoshlPscc2U.mp4",
        "pxO_eGmiDFk.mp4",
        "PlSBuqG15oA.mp4",
        "Ya_DsarE9KU.mp4",
        "eykMCjLK6GQ.mp4",
        "hpZC-9PvQyQ.mp4",
        "B1uIW4LN16Q.mp4",
    ]

    static var all: [URL] {
        entries.compactMap { filename in
            let url = videosDirectory.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }

    private static var videosDirectory: URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        // #filePath → .../golf-sync-swing/Services/ScreenshotDataService.swift
        let projectRoot = thisFile
            .deletingLastPathComponent()  // Services/
            .deletingLastPathComponent()  // golf-sync-swing/
            .deletingLastPathComponent()  // project root
        return projectRoot
            .appendingPathComponent("ml-training")
            .appendingPathComponent("youtube_videos")
    }
}

// MARK: - Swing Timing Presets

private struct SwingTiming {
    let start: TimeInterval
    let contact: TimeInterval
    let end: TimeInterval
    let confidence: Double
}

private struct ScheduleEntry {
    let url: URL
    let date: Date
    let timing: SwingTiming
    let isFavorite: Bool
}

// MARK: - Schedule with Realistic Dates

private enum ScreenshotSchedule {
    static func entries(from sources: [URL]) -> [ScheduleEntry] {
        let calendar = Calendar.current
        let timings = presetTimings
        let dates = sessionDates(calendar: calendar)
        let favorites: Set<Int> = [0, 2, 5]

        return sources.enumerated().map { index, url in
            let timing = timings[index % timings.count]
            let date = dates[index % dates.count]
            let isFav = favorites.contains(index)
            return ScheduleEntry(url: url, date: date, timing: timing, isFavorite: isFav)
        }
    }

    private static func sessionDates(calendar: Calendar) -> [Date] {
        [
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 8,  minute: 30))!,
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 14, minute: 15))!,
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 11, hour: 9,  minute: 45))!,
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 12, hour: 7,  minute: 20))!,
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 12, hour: 16, minute: 10))!,
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 13, hour: 10, minute: 0))!,
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 13, hour: 15, minute: 30))!,
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 14, hour: 8,  minute: 45))!,
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 14, hour: 13, minute: 20))!,
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 15, hour: 9,  minute: 0))!
        ]
    }

    private static var presetTimings: [SwingTiming] {
        [
            SwingTiming(start: 0.4, contact: 1.8, end: 3.2, confidence: 0.92),
            SwingTiming(start: 0.3, contact: 1.6, end: 3.0, confidence: 0.88),
            SwingTiming(start: 0.5, contact: 2.0, end: 3.5, confidence: 0.95),
            SwingTiming(start: 0.6, contact: 1.9, end: 3.3, confidence: 0.85),
            SwingTiming(start: 0.3, contact: 1.7, end: 3.1, confidence: 0.91),
            SwingTiming(start: 0.4, contact: 1.5, end: 2.8, confidence: 0.93),
            SwingTiming(start: 0.5, contact: 2.1, end: 3.6, confidence: 0.87),
            SwingTiming(start: 0.3, contact: 1.8, end: 3.4, confidence: 0.90),
            SwingTiming(start: 0.6, contact: 2.0, end: 3.2, confidence: 0.89),
            SwingTiming(start: 0.4, contact: 1.6, end: 3.0, confidence: 0.94)
        ]
    }
}

#endif
