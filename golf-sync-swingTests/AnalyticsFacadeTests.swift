import Testing
@testable import golf_sync_swing

struct AnalyticsFacadeTests {

    @Test("Facade routes track() to the injected tracker")
    func facadeRoutesTrack() {
        let spy = AnalyticsSpy()
        let analytics = Analytics(tracker: spy)
        analytics.track(.recordingStarted)
        analytics.track(.paywallShown(source: .onboarding))
        #expect(spy.trackedEvents == [.recordingStarted, .paywallShown(source: .onboarding)])
    }

    @Test("Facade routes identify() to the injected tracker")
    func facadeRoutesIdentify() {
        let spy = AnalyticsSpy()
        let analytics = Analytics(tracker: spy)
        analytics.identify(userId: "rc-user-123")
        #expect(spy.identifiedUserIds == ["rc-user-123"])
    }

    @Test("Facade routes record() revenue to the injected tracker")
    func facadeRoutesRecord() {
        let spy = AnalyticsSpy()
        let analytics = Analytics(tracker: spy)
        let revenue = PurchaseRevenue(productId: "golfswing.annual", price: 49.99, currency: "USD")
        analytics.record(revenue)
        #expect(spy.recordedRevenue == [revenue])
    }

    @Test("Facade routes setPremium() to the injected tracker")
    func facadeRoutesSetPremium() {
        let spy = AnalyticsSpy()
        let analytics = Analytics(tracker: spy)
        analytics.setPremium(true)
        analytics.setPremium(false)
        #expect(spy.premiumFlags == [true, false])
    }

    @Test("NoOpAnalytics swallows calls without crashing")
    func noOpDoesNothing() {
        let noOp = NoOpAnalytics()
        noOp.track(.swingDetected)
        noOp.identify(userId: "x")
        noOp.record(PurchaseRevenue(productId: "p", price: 1.0, currency: "USD"))
        noOp.setPremium(true)
        // No assertion — the test's value is that these calls don't crash or throw.
    }
}
