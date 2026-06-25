//
//  NoOpAnalytics.swift
//  golf-sync-swing
//
//  Default tracker before configure() runs, and the tracker used in
//  SwiftUI previews and tests. Intentionally does nothing.
//

import Foundation

final class NoOpAnalytics: AnalyticsTracking {
    func track(_ event: AnalyticsEvent) {}
    func identify(userId: String) {}
    func record(_ revenue: PurchaseRevenue) {}
    func setPremium(_ isPremium: Bool) {}
}
