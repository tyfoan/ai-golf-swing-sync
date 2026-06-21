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

    @Test("NoOpAnalytics swallows calls without crashing")
    func noOpDoesNothing() {
        let noOp = NoOpAnalytics()
        noOp.track(.swingDetected)
        noOp.identify(userId: "x")
        // No assertion — the test's value is that these calls don't crash or throw.
    }
}
