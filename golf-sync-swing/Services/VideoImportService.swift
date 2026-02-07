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
        await MainActor.run {
            modelContext.insert(video)
        }
        try? FileManager.default.removeItem(at: url)
    }
}
