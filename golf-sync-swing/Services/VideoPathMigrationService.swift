//
//  VideoPathMigrationService.swift
//  golf-sync-swing
//
//  One-time migration: converts absolute paths stored in SwingVideo
//  to relative paths (relative to Documents directory). This prevents
//  data loss when the container UUID changes on reinstall/restore.
//

import Foundation
import SwiftData
import os

struct VideoPathMigrationService {

    private static let migrationKey = "VideoPathMigration_v1_completed"

    static func migrateIfNeeded(modelContainer: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SwingVideo>()

        guard let videos = try? context.fetch(descriptor) else {
            AppLogger.storage.error("Path migration: failed to fetch videos")
            return
        }

        let documentsPath = SwingVideo.documentsDirectory.path
        var migratedCount = 0

        for video in videos {
            guard video.localURLString.hasPrefix("/") else { continue }
            guard video.localURLString.hasPrefix(documentsPath) else { continue }

            let relative = String(video.localURLString.dropFirst(documentsPath.count))
            video.localURLString = relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
            migratedCount += 1
        }

        guard migratedCount > 0 else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        do {
            try context.save()
            AppLogger.storage.info("Path migration: converted \(migratedCount) video(s) to relative paths")
        } catch {
            AppLogger.storage.error("Path migration: save failed: \(error.localizedDescription)")
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}
