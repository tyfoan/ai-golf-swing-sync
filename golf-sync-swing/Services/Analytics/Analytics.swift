//
//  Analytics.swift
//  golf-sync-swing
//
//  Shared facade. Stays NoOp until configure() swaps in the Amplitude
//  implementation at app launch. Mirrors PurchaseService's configure() pattern.
//

import Foundation

final class Analytics: AnalyticsTracking {

    static let shared = Analytics()

    private var tracker: AnalyticsTracking
    private var isConfigured = false

    init(tracker: AnalyticsTracking = NoOpAnalytics()) {
        self.tracker = tracker
    }

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        tracker = AmplitudeAnalytics()
    }

    func track(_ event: AnalyticsEvent) {
        tracker.track(event)
    }

    func identify(userId: String) {
        tracker.identify(userId: userId)
    }

    func record(_ revenue: PurchaseRevenue) {
        tracker.record(revenue)
    }

    func setPremium(_ isPremium: Bool) {
        tracker.setPremium(isPremium)
    }
}
