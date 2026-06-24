//
//  AnalyticsTracking.swift
//  golf-sync-swing
//
//  The analytics seam. The whole app depends on this protocol, never on a
//  concrete analytics SDK.
//

import Foundation

protocol AnalyticsTracking {
    func track(_ event: AnalyticsEvent)
    func identify(userId: String)
    func record(_ revenue: PurchaseRevenue)
    func setPremium(_ isPremium: Bool)
}
