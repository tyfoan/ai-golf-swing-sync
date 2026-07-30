//
//  ProSwingSeeder.swift
//  golf-sync-swing
//
//  On first launch — and any time the catalog version bumps — copies the
//  bundled pro reference clips into Documents/Videos/Pros and creates matching
//  SwingVideo + SwingMarker records so they flow through the standard
//  comparison pipeline.
//

import AVFoundation
import Foundation
import SwiftData
import UIKit
import os

/// Split across actors so the heavy work never sits on the main thread: the `@Model`
/// types are main-actor-isolated under this project's default isolation, so every
/// SwiftData touch (fetch, insert, save) stays on the main actor and is metadata-cheap,
/// while the I/O — 19 bundled-clip copies (~59 MB) and an `AVAssetImageGenerator`
/// decode per clip — runs in `@concurrent` helpers on the global executor.
/// `inFlightSeed` serializes overlapping passes: without it, two passes interleaved
/// across the await points could both see a clip as missing and double-insert it
/// (`localURLString` has no unique constraint).
enum ProSwingSeeder {
    static let proPathPrefix = "Videos/Pros/"

    private static let seedVersionKey = "proSwingSeedVersion"
    private static let currentSeedVersion = 5
    private static var inFlightSeed: Task<Void, Never>?

    /// Cheap to call from the main actor: schedules the pass and returns immediately.
    static func seedIfNeeded(container: ModelContainer) {
        guard inFlightSeed == nil else { return }
        inFlightSeed = Task(priority: .utility) {
            await performSeedPass(container: container)
            inFlightSeed = nil
        }
    }

    private static func performSeedPass(container: ModelContainer) async {
        // Before the early-return, so already-seeded installs get it too — otherwise the
        // ~60 MB of duplicated bundle content stays in the iCloud backup of every existing
        // user, which is the entire population this is meant to help. Idempotent.
        await excludeProsFromBackup()

        let context = ModelContext(container)
        let stored = UserDefaults.standard.integer(forKey: seedVersionKey)
        if stored >= currentSeedVersion, allProsSeeded(context: context) {
            return
        }
        await seed(context: context)
        UserDefaults.standard.set(currentSeedVersion, forKey: seedVersionKey)
    }

    // MARK: - Existence Check

    private static func allProsSeeded(context: ModelContext) -> Bool {
        let prefix = proPathPrefix
        let descriptor = FetchDescriptor<SwingVideo>(
            predicate: #Predicate { $0.localURLString.starts(with: prefix) }
        )
        guard let existing = try? context.fetch(descriptor) else { return false }
        let seededFilenames = Set(existing.map { $0.localURL.deletingPathExtension().lastPathComponent })
        // A record alone is not enough: Videos/Pros is excluded from backup, so after a
        // device restore the records survive but the media does not. Requiring the file
        // too lets seedIfNeeded fall through to seedOne, which heals the missing copy.
        return ProSwingCatalog.all.allSatisfy { entry in
            seededFilenames.contains(entry.bundleFilename)
                && FileManager.default.fileExists(atPath: ProsDirectory.mediaURL(for: entry.bundleFilename).path)
        }
    }

    // MARK: - Seeding

    private static func seed(context: ModelContext) async {
        await prepareProsDirectory()

        for descriptor in ProSwingCatalog.all {
            await seedOne(descriptor, context: context)
        }

        do { try context.save() }
        catch { AppLogger.general.error("ProSwingSeeder save failed: \(error.localizedDescription)") }
    }

    private static func seedOne(_ descriptor: ProSwingDescriptor, context: ModelContext) async {
        guard let bundleURL = Bundle.main.url(forResource: descriptor.bundleFilename, withExtension: "mp4") else {
            AppLogger.general.error("ProSwing missing in bundle: \(descriptor.bundleFilename).mp4")
            return
        }

        let destURL = ProsDirectory.mediaURL(for: descriptor.bundleFilename)
        let existing = proRecord(filename: descriptor.bundleFilename, context: context)

        // Record AND file present: metadata refresh only, no ~59 MB of pointless copy I/O.
        if let existing, FileManager.default.fileExists(atPath: destURL.path) {
            update(existing, with: descriptor)
            return
        }

        guard await copyBundleVideo(from: bundleURL, descriptor: descriptor) != nil else {
            return
        }

        // Record without media means an iCloud restore (Videos/Pros is excluded from backup,
        // so records survive but files do not): heal in place — inserting here would leave
        // every pro swing in the library twice, since localURLString has no unique constraint.
        if let existing {
            await heal(existing, mediaURL: destURL, with: descriptor)
        } else {
            await insertFresh(descriptor, mediaURL: destURL, context: context)
        }
    }

    private static func heal(_ video: SwingVideo, mediaURL: URL, with descriptor: ProSwingDescriptor) async {
        // The restored record usually still carries its thumbnail; regenerate only when it
        // does not, since generation runs an image-decode pass per clip.
        if video.thumbnailData == nil {
            video.thumbnailData = await renderThumbnail(for: mediaURL, at: descriptor.contactTime)
        }
        update(video, with: descriptor)
    }

    private static func insertFresh(_ descriptor: ProSwingDescriptor, mediaURL: URL, context: ModelContext) async {
        let thumbnail = await renderThumbnail(for: mediaURL, at: descriptor.contactTime)
        let video = SwingVideo(localURL: mediaURL, duration: descriptor.duration, fps: 30, thumbnailData: thumbnail)
        update(video, with: descriptor)
        context.insert(video)
    }

    private static func proRecord(filename: String, context: ModelContext) -> SwingVideo? {
        let needle = "\(proPathPrefix)\(filename)"
        let descriptor = FetchDescriptor<SwingVideo>(
            predicate: #Predicate { $0.localURLString.starts(with: needle) }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - Off-Main I/O

    /// The backup-exclusion flag is a filesystem write, so it runs with the rest of the
    /// seeder's I/O on the global executor.
    @concurrent
    private nonisolated static func excludeProsFromBackup() async {
        ProsDirectory.excludeFromBackup()
    }

    @concurrent
    private nonisolated static func prepareProsDirectory() async {
        try? FileManager.default.createDirectory(at: ProsDirectory.url, withIntermediateDirectories: true)
        // Again after creation — the flag can only be set on a directory that exists, and on a
        // fresh install the call in performSeedPass ran before this mkdir.
        ProsDirectory.excludeFromBackup()
    }

    @concurrent
    private nonisolated static func copyBundleVideo(from bundleURL: URL, descriptor: ProSwingDescriptor) async -> URL? {
        let destURL = ProsDirectory.mediaURL(for: descriptor.bundleFilename)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: bundleURL, to: destURL)
            return destURL
        } catch {
            AppLogger.general.error("ProSwing copy failed for \(descriptor.bundleFilename): \(error.localizedDescription)")
            return nil
        }
    }

    /// Inlined rather than routed through `ThumbnailService`: that service is main-actor-
    /// isolated, and this decode must stay on the global executor. Same 300x400 / 0.7 JPEG
    /// contract as `ThumbnailService.generateThumbnail(for:at:)`.
    @concurrent
    private nonisolated static func renderThumbnail(for url: URL, at time: TimeInterval) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 300, height: 400)
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        guard let image = try? await generator.image(at: cmTime).image else {
            return nil
        }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.7)
    }

    private static func update(_ video: SwingVideo, with descriptor: ProSwingDescriptor) {
        video.duration = descriptor.duration
        video.fps = 30
        video.hasBeenAnalyzed = true
        video.analysisDate = Date()

        if let marker = video.swings.first {
            update(marker, with: descriptor)
        } else {
            let marker = SwingMarker(
                startTime: descriptor.startTime,
                contactTime: descriptor.contactTime,
                endTime: descriptor.endTime
            )
            update(marker, with: descriptor)
            marker.video = video
            video.swings.append(marker)
        }
    }

    private static func update(_ marker: SwingMarker, with descriptor: ProSwingDescriptor) {
        marker.updateTimes(
            start: descriptor.startTime,
            contact: descriptor.contactTime,
            end: descriptor.endTime
        )
        marker.isAutoDetected = true
        marker.detectionConfidence = 1.0
    }
}

// MARK: - Pros Directory

/// `nonisolated`: called from the seeder's `@concurrent` I/O helpers, and everything it
/// touches (FileManager, URL) is safe off the main actor.
private nonisolated enum ProsDirectory {
    static var url: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Videos/Pros", isDirectory: true)
    }

    static func mediaURL(for bundleFilename: String) -> URL {
        url.appendingPathComponent("\(bundleFilename).mp4")
    }

    /// These clips ship inside the app bundle, so backing the copies up wastes the user's
    /// iCloud quota on ~60 MB that can always be recreated from the binary.
    static func excludeFromBackup() {
        var directory = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }
}
