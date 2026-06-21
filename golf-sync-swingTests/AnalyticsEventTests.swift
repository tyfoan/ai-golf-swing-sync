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
}
