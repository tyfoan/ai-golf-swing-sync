//
//  AnalyticsEvent.swift
//  golf-sync-swing
//
//  Typed funnel-analytics event. Construct only via the static factories
//  below so event names and property keys stay consistent across call sites.
//

import Foundation

struct AnalyticsEvent: Equatable {
    let name: String
    let properties: [String: String]

    private init(name: String, properties: [String: String] = [:]) {
        self.name = name
        self.properties = properties
    }
}

extension AnalyticsEvent {
    /// The denominator. Without it every other count is a rate against nothing.
    static let appLaunched = AnalyticsEvent(name: "app_launched")

    static let onboardingStarted = AnalyticsEvent(name: "onboarding_started")
    static let onboardingCompleted = AnalyticsEvent(name: "onboarding_completed")
    static let mainAppReached = AnalyticsEvent(name: "main_app_reached")
    static let recordingStarted = AnalyticsEvent(name: "recording_started")
    static let swingDetected = AnalyticsEvent(name: "swing_detected")
    static let videoImported = AnalyticsEvent(name: "video_imported")

    // MARK: - Failure-side events
    //
    // Until these existed the funnel could only show success. A recording that started and
    // never finished looked identical to one that was never started, which is precisely how
    // the finalize freeze stayed invisible in production for months.

    /// Pairs with `recordingStarted`. A `recording_started` with no matching
    /// `recording_stopped` is the freeze's fingerprint in the funnel.
    static func recordingStopped(swingCount: Int) -> AnalyticsEvent {
        AnalyticsEvent(name: "recording_stopped", properties: ["swing_count": String(swingCount)])
    }

    /// The recording finished with nothing detected in it. Pairs with `recordingStopped`:
    /// the share of takes that reach this instead of `swingSaved` is the detection quality
    /// metric the funnel never had. It used to delete the clip silently, so the most common
    /// way a recording produces nothing was also the least visible.
    static func recordingNoSwingsDetected(duration: TimeInterval) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "recording_no_swings_detected",
            properties: ["duration_seconds": String(format: "%.1f", duration)]
        )
    }

    /// The finalize watchdog fired: the recording never completed on its own.
    static func recordingFinalizeTimeout(swingCount: Int) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "recording_finalize_timeout",
            properties: ["swing_count": String(swingCount)]
        )
    }

    /// `AVCaptureSession` configuration failed — the user sees an error alert and cannot record.
    static func cameraConfigFailed(reason: String) -> AnalyticsEvent {
        AnalyticsEvent(name: "camera_config_failed", properties: ["reason": reason])
    }

    /// A crash reported by MetricKit on a later launch. Stack traces stay in Xcode Organizer;
    /// this exists so crash *rate* is visible next to the funnel.
    static func crashDetected(properties: [String: String]) -> AnalyticsEvent {
        AnalyticsEvent(name: "crash_detected", properties: properties)
    }

    /// A hang (unresponsive main thread) reported by MetricKit. The class of failure a crash
    /// reporter never sees, and the one that actually hurt this app.
    static func hangDetected(properties: [String: String]) -> AnalyticsEvent {
        AnalyticsEvent(name: "hang_detected", properties: properties)
    }

    static func paywallShown(source: PaywallSource) -> AnalyticsEvent {
        AnalyticsEvent(name: "paywall_shown", properties: ["source": source.rawValue])
    }

    static func paywallDismissed(source: PaywallSource) -> AnalyticsEvent {
        AnalyticsEvent(name: "paywall_dismissed", properties: ["source": source.rawValue])
    }

    static func paywallPurchased(source: PaywallSource) -> AnalyticsEvent {
        AnalyticsEvent(name: "paywall_purchased", properties: ["source": source.rawValue])
    }

    static func comparisonOpened(mode: ComparisonMode) -> AnalyticsEvent {
        AnalyticsEvent(name: "comparison_opened", properties: ["mode": String(describing: mode)])
    }

    static func featureGateHit(feature: PremiumFeature) -> AnalyticsEvent {
        AnalyticsEvent(name: "feature_gate_hit", properties: ["feature": feature.rawValue])
    }

    static func exportCompleted(aspectRatio: ExportAspectRatio?, isHD: Bool) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "export_completed",
            properties: ["aspect_ratio": aspectRatio?.rawValue ?? "legacy", "is_hd": String(describing: isHD)]
        )
    }

    static func exportStarted(aspectRatio: ExportAspectRatio?, quality: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "export_started",
            properties: ["aspect_ratio": aspectRatio?.rawValue ?? "legacy", "quality": quality]
        )
    }

    static func exportFailed(aspectRatio: ExportAspectRatio?, reason: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "export_failed",
            properties: ["aspect_ratio": aspectRatio?.rawValue ?? "legacy", "reason": reason]
        )
    }

    static func swingSaved(saveType: String, count: Int) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "swing_saved",
            properties: ["save_type": saveType, "count": String(count)]
        )
    }

    static func comparisonModeChanged(from: ComparisonMode, to: ComparisonMode) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "comparison_mode_changed",
            properties: ["from": String(describing: from), "to": String(describing: to)]
        )
    }

    static func purchaseCompleted(revenue: PurchaseRevenue, plan: String, source: PaywallSource) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "purchase_completed",
            properties: [
                "plan": plan,
                "product_id": revenue.productId,
                "price": String(revenue.price),
                "currency": revenue.currency,
                "source": source.rawValue
            ]
        )
    }

    static func trialStarted(plan: String, productId: String, source: PaywallSource) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "trial_started",
            properties: ["plan": plan, "product_id": productId, "source": source.rawValue]
        )
    }

    static func purchaseRestored(source: PaywallSource) -> AnalyticsEvent {
        AnalyticsEvent(name: "purchase_restored", properties: ["source": source.rawValue])
    }

    /// Money actually recognised, observed from the entitlement stream rather than the
    /// paywall. The paywall can only see the tap that starts a subscription — and since
    /// every plan offers a free trial, its paid branch never ran and no revenue reached
    /// Amplitude at all. This fires for trial→paid conversions and renewals too.
    static func revenueRecognized(revenue: PurchaseRevenue, isRenewal: Bool) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "revenue_recognized",
            properties: [
                "product_id": revenue.productId,
                "price": String(revenue.price),
                "currency": revenue.currency,
                "is_renewal": String(isRenewal)
            ]
        )
    }
}
