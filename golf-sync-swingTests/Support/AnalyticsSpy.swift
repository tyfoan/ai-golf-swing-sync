import Foundation
@testable import golf_sync_swing

final class AnalyticsSpy: AnalyticsTracking {
    private(set) var trackedEvents: [AnalyticsEvent] = []
    private(set) var identifiedUserIds: [String] = []

    func track(_ event: AnalyticsEvent) {
        trackedEvents.append(event)
    }

    func identify(userId: String) {
        identifiedUserIds.append(userId)
    }
}
