import Foundation
@testable import golf_sync_swing

final class AnalyticsSpy: AnalyticsTracking {
    private(set) var trackedEvents: [AnalyticsEvent] = []
    private(set) var identifiedUserIds: [String] = []
    private(set) var recordedRevenue: [PurchaseRevenue] = []
    private(set) var premiumFlags: [Bool] = []

    func track(_ event: AnalyticsEvent) {
        trackedEvents.append(event)
    }

    func identify(userId: String) {
        identifiedUserIds.append(userId)
    }

    func record(_ revenue: PurchaseRevenue) {
        recordedRevenue.append(revenue)
    }

    func setPremium(_ isPremium: Bool) {
        premiumFlags.append(isPremium)
    }
}
