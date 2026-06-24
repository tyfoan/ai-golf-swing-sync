import Testing
@testable import golf_sync_swing

struct AnalyticsEventTests {

    @Test("Parameterless events carry the right name and no properties")
    func parameterlessEvents() {
        #expect(AnalyticsEvent.onboardingStarted.name == "onboarding_started")
        #expect(AnalyticsEvent.onboardingCompleted.name == "onboarding_completed")
        #expect(AnalyticsEvent.mainAppReached.name == "main_app_reached")
        #expect(AnalyticsEvent.recordingStarted.name == "recording_started")
        #expect(AnalyticsEvent.swingDetected.name == "swing_detected")
        #expect(AnalyticsEvent.videoImported.name == "video_imported")
        #expect(AnalyticsEvent.onboardingStarted.properties.isEmpty)
    }

    @Test("Paywall events carry the source raw value")
    func paywallEvents() {
        #expect(AnalyticsEvent.paywallShown(source: .onboarding).name == "paywall_shown")
        #expect(AnalyticsEvent.paywallShown(source: .onboarding).properties == ["source": "onboarding"])
        #expect(AnalyticsEvent.paywallDismissed(source: .featureGate).name == "paywall_dismissed")
        #expect(AnalyticsEvent.paywallDismissed(source: .featureGate).properties == ["source": "featureGate"])
        #expect(AnalyticsEvent.paywallPurchased(source: .settings).name == "paywall_purchased")
        #expect(AnalyticsEvent.paywallPurchased(source: .settings).properties == ["source": "settings"])
    }

    @Test("comparison_opened uses the stable mode case name")
    func comparisonOpened() {
        #expect(AnalyticsEvent.comparisonOpened(mode: .stacked).properties == ["mode": "stacked"])
        let sbs = AnalyticsEvent.comparisonOpened(mode: .sideBySide)
        #expect(sbs.name == "comparison_opened")
        #expect(sbs.properties == ["mode": "sideBySide"])
    }

    @Test("feature_gate_hit uses the feature raw value")
    func featureGateHit() {
        let event = AnalyticsEvent.featureGateHit(feature: .advancedComparisonModes)
        #expect(event.name == "feature_gate_hit")
        #expect(event.properties == ["feature": "advancedComparisonModes"])
    }

    @Test("export_completed carries aspect ratio and HD flag as strings")
    func exportCompleted() {
        let hd = AnalyticsEvent.exportCompleted(aspectRatio: .tikTokVertical, isHD: true)
        #expect(hd.name == "export_completed")
        #expect(hd.properties == ["aspect_ratio": "tikTokVertical", "is_hd": "true"])
        let legacy = AnalyticsEvent.exportCompleted(aspectRatio: nil, isHD: false)
        #expect(legacy.properties == ["aspect_ratio": "legacy", "is_hd": "false"])
    }

    @Test("export_started carries aspect ratio and quality")
    func exportStarted() {
        let event = AnalyticsEvent.exportStarted(aspectRatio: .square, quality: "ultra")
        #expect(event.name == "export_started")
        #expect(event.properties == ["aspect_ratio": "square", "quality": "ultra"])
        #expect(AnalyticsEvent.exportStarted(aspectRatio: nil, quality: "standard").properties["aspect_ratio"] == "legacy")
    }

    @Test("export_failed carries aspect ratio and a stable reason")
    func exportFailed() {
        let event = AnalyticsEvent.exportFailed(aspectRatio: .tikTokVertical, reason: "noVideoTrack")
        #expect(event.name == "export_failed")
        #expect(event.properties == ["aspect_ratio": "tikTokVertical", "reason": "noVideoTrack"])
    }

    @Test("swing_saved carries save type and count")
    func swingSaved() {
        let clip = AnalyticsEvent.swingSaved(saveType: "clip", count: 3)
        #expect(clip.name == "swing_saved")
        #expect(clip.properties == ["save_type": "clip", "count": "3"])
    }

    @Test("comparison_mode_changed carries stable from/to case names")
    func comparisonModeChanged() {
        let event = AnalyticsEvent.comparisonModeChanged(from: .sideBySide, to: .stacked)
        #expect(event.name == "comparison_mode_changed")
        #expect(event.properties == ["from": "sideBySide", "to": "stacked"])
    }

    @Test("purchase_completed carries plan, product, price, currency and source")
    func purchaseCompleted() {
        let revenue = PurchaseRevenue(productId: "golfswing.annual", price: 49.99, currency: "USD")
        let event = AnalyticsEvent.purchaseCompleted(revenue: revenue, plan: "annual", source: .onboarding)
        #expect(event.name == "purchase_completed")
        #expect(event.properties == [
            "plan": "annual",
            "product_id": "golfswing.annual",
            "price": "49.99",
            "currency": "USD",
            "source": "onboarding"
        ])
    }

    @Test("trial_started carries plan, product and source — no revenue")
    func trialStarted() {
        let event = AnalyticsEvent.trialStarted(plan: "weekly", productId: "golfswing.weekly", source: .featureGate)
        #expect(event.name == "trial_started")
        #expect(event.properties == ["plan": "weekly", "product_id": "golfswing.weekly", "source": "featureGate"])
    }

    @Test("purchase_restored carries the source")
    func purchaseRestored() {
        let event = AnalyticsEvent.purchaseRestored(source: .settings)
        #expect(event.name == "purchase_restored")
        #expect(event.properties == ["source": "settings"])
    }
}
