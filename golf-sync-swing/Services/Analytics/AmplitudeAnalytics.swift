//
//  AmplitudeAnalytics.swift
//  golf-sync-swing
//
//  The ONLY file that imports the Amplitude SDK. Configured IDFV-only
//  (Amplitude-Swift does not collect IDFA unless its IDFA plugin is added,
//  which we do not), so no App Tracking Transparency prompt is required.
//  Session autocapture is on; screen/lifecycle/network autocapture is off.
//

import AmplitudeSwift
import Foundation

final class AmplitudeAnalytics: AnalyticsTracking {

    // Client write key from the Amplitude dashboard (Settings → Projects → API Key).
    // Safe to embed, like the RevenueCat key in PurchaseService.
    static let apiKey = "PASTE_AMPLITUDE_API_KEY_FROM_DASHBOARD"

    private let amplitude: Amplitude

    init() {
        amplitude = Amplitude(configuration: Configuration(
            apiKey: Self.apiKey,
            autocapture: [.sessions]
        ))
    }

    func track(_ event: AnalyticsEvent) {
        amplitude.track(eventType: event.name, eventProperties: event.properties)
    }

    func identify(userId: String) {
        amplitude.setUserId(userId: userId)
    }
}
