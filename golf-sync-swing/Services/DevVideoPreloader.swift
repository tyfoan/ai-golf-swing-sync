//
//  DevVideoPreloader.swift
//  golf-sync-swing
//

#if DEBUG

import Foundation
import SwiftData

enum DevVideoPreloader {
    private static let sourceDirectory = "/Users/aleksanderogurtsov/Desktop/test/video-comparer/ios/video-comparer/app/refs/golf"

    private static let videoFiles = [
        "1.mp4", "2.mp4", "3.mp4", "4.mp4", "5.mp4",
        "6.mp4", "7.mp4", "8.mp4", "9.mp4", "expert.mp4"
    ]

    @MainActor
    static func preloadIfNeeded(modelContext: ModelContext) async {
        let existingPaths: Set<String>
        do {
            let descriptor = FetchDescriptor<SwingVideo>()
            let existing = try modelContext.fetch(descriptor)
            existingPaths = Set(existing.map(\.localURLString))
        } catch {
            print("⚠️ DevVideoPreloader: failed to fetch existing videos: \(error)")
            return
        }

        var insertedCount = 0

        for filename in videoFiles {
            let url = URL(fileURLWithPath: sourceDirectory).appendingPathComponent(filename)

            guard FileManager.default.fileExists(atPath: url.path) else {
                print("⚠️ DevVideoPreloader: missing \(filename)")
                continue
            }

            guard !existingPaths.contains(url.path) else {
                continue
            }

            let video = await VideoStorageService.shared.createSwingVideo(from: url)
            modelContext.insert(video)
            insertedCount += 1
        }

        if insertedCount > 0 {
            do {
                try modelContext.save()
                print("✅ DevVideoPreloader: inserted \(insertedCount) videos")
            } catch {
                print("❌ DevVideoPreloader: save failed: \(error)")
            }
        }
    }
}

#endif
