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
    static let onboardingStarted = AnalyticsEvent(name: "onboarding_started")
    static let onboardingCompleted = AnalyticsEvent(name: "onboarding_completed")
    static let mainAppReached = AnalyticsEvent(name: "main_app_reached")
    static let recordingStarted = AnalyticsEvent(name: "recording_started")
    static let swingDetected = AnalyticsEvent(name: "swing_detected")
    static let videoImported = AnalyticsEvent(name: "video_imported")

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
}
