//
//  LibraryGateService.swift
//  golf-sync-swing
//
//  Free-tier library cap: non-premium users keep up to 3 user-recorded
//  swings. Pro library entries don't count. Premium = unlimited.
//

import Foundation
import SwiftData

struct LibraryGateService {

    static let freeUserSwingLimit = 3

    static func userSwingCount(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<SwingVideo>()
        guard let videos = try? context.fetch(descriptor) else { return 0 }
        return videos.filter { !$0.isPro }.count
    }

    static func canAddSwing(in context: ModelContext) -> Bool {
        guard !FeatureAccess.isPremiumUser else { return true }
        return userSwingCount(in: context) < freeUserSwingLimit
    }
}
