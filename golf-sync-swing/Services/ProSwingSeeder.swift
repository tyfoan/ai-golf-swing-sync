//
//  ProSwingSeeder.swift
//  golf-sync-swing
//
//  On first launch — and any time the catalog version bumps — copies the
//  bundled pro reference clips into Documents/Videos/Pros and creates matching
//  SwingVideo + SwingMarker records so they flow through the standard
//  comparison pipeline.
//

import Foundation
import SwiftData
import os

@MainActor
enum ProSwingSeeder {
    static let proPathPrefix = "Videos/Pros/"

    private static let seedVersionKey = "proSwingSeedVersion"
    private static let currentSeedVersion = 1

    static func seedIfNeeded(container: ModelContainer) {
        let context = ModelContext(container)
        let stored = UserDefaults.standard.integer(forKey: seedVersionKey)
        if stored >= currentSeedVersion, allProsSeeded(context: context) {
            return
        }
        seed(context: context)
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
        let neededFilenames = Set(ProSwingCatalog.all.map(\.bundleFilename))
        return neededFilenames.isSubset(of: seededFilenames)
    }

    // MARK: - Seeding

    private static func seed(context: ModelContext) {
        try? FileManager.default.createDirectory(at: ProsDirectory.url, withIntermediateDirectories: true)

        for descriptor in ProSwingCatalog.all {
            seedOne(descriptor, context: context)
        }

        do { try context.save() }
        catch { AppLogger.general.error("ProSwingSeeder save failed: \(error.localizedDescription)") }
    }

    private static func seedOne(_ descriptor: ProSwingDescriptor, context: ModelContext) {
        guard let bundleURL = Bundle.main.url(forResource: descriptor.bundleFilename, withExtension: "mp4") else {
            AppLogger.general.error("ProSwing missing in bundle: \(descriptor.bundleFilename).mp4")
            return
        }

        let destURL = ProsDirectory.url.appendingPathComponent("\(descriptor.bundleFilename).mp4")
        if !FileManager.default.fileExists(atPath: destURL.path) {
            do { try FileManager.default.copyItem(at: bundleURL, to: destURL) }
            catch {
                AppLogger.general.error("ProSwing copy failed for \(descriptor.bundleFilename): \(error.localizedDescription)")
                return
            }
        }

        if proRecordExists(filename: descriptor.bundleFilename, context: context) { return }

        let thumbnail = ThumbnailService.shared.generateThumbnail(for: destURL, at: descriptor.contactTime)
        let video = SwingVideo(localURL: destURL, duration: descriptor.duration, fps: 30, thumbnailData: thumbnail)
        video.hasBeenAnalyzed = true
        video.analysisDate = Date()

        let marker = SwingMarker(
            startTime: descriptor.startTime,
            contactTime: descriptor.contactTime,
            endTime: descriptor.endTime
        )
        marker.detectionConfidence = 1.0
        marker.video = video
        video.swings.append(marker)

        context.insert(video)
    }

    private static func proRecordExists(filename: String, context: ModelContext) -> Bool {
        let needle = "\(proPathPrefix)\(filename)"
        let descriptor = FetchDescriptor<SwingVideo>(
            predicate: #Predicate { $0.localURLString.starts(with: needle) }
        )
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }
}

// MARK: - Pros Directory

private enum ProsDirectory {
    static var url: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Videos/Pros", isDirectory: true)
    }
}
