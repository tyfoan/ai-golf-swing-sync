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
    private static let attemptsKey = "VideoPathMigration_v1_attempts"
    private static let maxAttempts = 3

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
            markCompleted()
            return
        }

        do {
            try context.save()
            AppLogger.storage.info("Path migration: converted \(migratedCount) video(s) to relative paths")
            markCompleted()
        } catch {
            recordFailedAttempt(error)
        }
    }

    private static func markCompleted() {
        UserDefaults.standard.set(true, forKey: migrationKey)
        UserDefaults.standard.removeObject(forKey: attemptsKey)
    }

    /// Capped retry: a transient save failure gets `maxAttempts` launches to succeed
    /// before the flag is set anyway — the anti-loop guard against re-running a full
    /// fetch and mutation of every video at every launch, forever.
    private static func recordFailedAttempt(_ error: Error) {
        let attempts = UserDefaults.standard.integer(forKey: attemptsKey) + 1
        UserDefaults.standard.set(attempts, forKey: attemptsKey)
        AppLogger.storage.error("Path migration: save failed (attempt \(attempts)/\(maxAttempts)): \(error.localizedDescription)")
        guard attempts >= maxAttempts else { return }
        AppLogger.storage.error("Path migration: giving up after \(maxAttempts) failed attempts")
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}
