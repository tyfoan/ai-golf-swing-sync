//
//  ComparisonSession.swift
//  golf-sync-swing
//

import Foundation
import SwiftData

@Model
final class ComparisonSession {
    var id: UUID = UUID()
    @Relationship var video1: SwingVideo?
    @Relationship var video2: SwingVideo?
    var syncOffset: TimeInterval = 0
    var createdAt: Date = Date()

    init(video1: SwingVideo? = nil, video2: SwingVideo? = nil, syncOffset: TimeInterval = 0) {
        self.video1 = video1
        self.video2 = video2
        self.syncOffset = syncOffset
    }
}
