//
//  VideoImportService.swift
//  golf-sync-swing
//
//  Encapsulates video import workflow: copy to storage, create SwingVideo,
//  insert into model context. Extracted from HomeView + HistoryView.
//

import Foundation
import SwiftData

struct VideoImportService {

    func importVideo(from url: URL, into modelContext: ModelContext) async throws {
        let localURL = try VideoStorageService.shared.copyVideoToStorage(from: url)
        let video = await VideoStorageService.shared.createSwingVideo(from: localURL)
        try await MainActor.run {
            modelContext.insert(video)
            try modelContext.save()
        }
        Analytics.shared.track(.videoImported)
        let isInTempDirectory = url.path.contains(NSTemporaryDirectory()) || url.path.contains("/tmp/")
        if isInTempDirectory {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
