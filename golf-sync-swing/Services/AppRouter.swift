//
//  AppRouter.swift
//  golf-sync-swing
//
//  Cross-tab navigation router. Lets one tab request another tab to push
//  a specific destination on appear (e.g. RecordingView asking HistoryView
//  to open a freshly saved recording).
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class AppRouter {
    enum Tab: Int, Hashable, CaseIterable {
        case camera = 0
        case history = 1
        case compare = 2
        case settings = 3
    }

    var selectedTab: Tab = .camera
    private(set) var pendingHistoryVideoID: UUID?

    func openInHistory(videoID: UUID) {
        pendingHistoryVideoID = videoID
        selectedTab = .history
    }

    /// Read-and-clear: returns the pending video ID (if any) and atomically
    /// resets the slot so the destination view doesn't poke router internals.
    func consumePendingHistoryVideoID() -> UUID? {
        defer { pendingHistoryVideoID = nil }
        return pendingHistoryVideoID
    }
}
