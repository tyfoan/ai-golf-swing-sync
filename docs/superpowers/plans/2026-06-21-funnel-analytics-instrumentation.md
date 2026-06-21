# Funnel Analytics Instrumentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Instrument a minimal ~11-event funnel (launch → onboarding → paywall → activation → export → feature-gate) with Amplitude (free tier) + RevenueCat's native Amplitude integration, so the largest user drop-off stage becomes measurable within ~1–2 weeks of a release.

**Architecture:** A protocol seam (`AnalyticsTracking`) with a typed value-object event taxonomy (`AnalyticsEvent` + static factories), a production `AmplitudeAnalytics` wrapper, a `NoOpAnalytics` default, and a thin `Analytics` shared facade. Amplitude is isolated to a single file. Events fire from ViewModels/Services and a few unavoidable view appearance hooks. The RevenueCat App User ID is set as the Amplitude user ID so app events join RevenueCat's server-sent monetization events.

**Tech Stack:** Swift 5 / SwiftUI / SwiftData / iOS 26.1, Swift Testing (`@Test`/`#expect`), Amplitude-Swift SPM (`import AmplitudeSwift`), RevenueCat (already integrated).

**Spec:** `docs/superpowers/specs/2026-06-21-funnel-analytics-instrumentation-design.md`

---

## Testing Philosophy For This Plan

The **pure core is TDD'd** (Tasks 1–2): the `AnalyticsEvent` taxonomy and the `AnalyticsTracking` seam are plain values/protocols with no UI or SDK dependency, so they get real failing-test-first cycles. Unit tests run via Swift Testing on the **iPhone 17** simulator.

The **wiring tasks** (Tasks 3–13) add one tracking call at a verified anchor inside SwiftUI views / ViewModels / services. SwiftUI `onAppear`/closure firing is not meaningfully unit-testable without refactoring views into injectable view-models (out of scope). These tasks are verified by **(a)** a clean build and **(b)** the end-to-end manual checklist in Task 15 against Amplitude's live event stream — which is success criterion #1 in the spec. This tradeoff is deliberate.

**Conventions to follow (verified in codebase):** double-quoted strings, `String(localized:comment:)` for user-facing copy, `static let shared` singletons with `private init`, camelCase members / PascalCase types, standard `import` syntax (no visibility keywords despite `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`). Files stay under 200 lines, methods under 15 lines (Sandi Metz principles in CLAUDE.md).

**Build command (use iPhone 17 per project memory):**
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build
```
**Single Swift Testing test:**
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/AnalyticsEventTests/<funcName> test
```

---

## File Structure

**New files (all in `golf-sync-swing/Services/Analytics/`):**
- `AnalyticsEvent.swift` — typed event value object + static factories (the taxonomy contract).
- `AnalyticsTracking.swift` — the protocol seam (`track`, `identify`).
- `NoOpAnalytics.swift` — does nothing; default before `configure()`, and used in previews/tests.
- `AmplitudeAnalytics.swift` — the ONLY file importing `AmplitudeSwift`; wraps the SDK.
- `Analytics.swift` — shared facade (`Analytics.shared`) with a test-injection seam.

**New test files (`golf-sync-swingTests/`):**
- `AnalyticsEventTests.swift` — asserts each event's name + properties.
- `Support/AnalyticsSpy.swift` — records tracked events / identify calls for tests.

**Modified files:**
- `golf-sync-swing.xcodeproj` — add Amplitude-Swift SPM package (Xcode UI).
- `golf-sync-swing/golf_sync_swingApp.swift` — `Analytics.shared.configure()` at init.
- `golf-sync-swing/Services/PurchaseService.swift` — `identify(userId:)` in `observeCustomerInfo()`.
- `golf-sync-swing/Views/Onboarding/OnboardingView.swift` — `onboarding_started`, `onboarding_completed`.
- `golf-sync-swing/Views/Paywall/CustomPaywallView.swift` — `paywall_shown`, `paywall_dismissed`, `paywall_purchased`.
- `golf-sync-swing/Views/MainTabView.swift` — `main_app_reached`.
- `golf-sync-swing/ViewModels/RecordingViewModel.swift` — `recording_started`, `swing_detected`.
- `golf-sync-swing/Services/VideoImportService.swift` — `video_imported`.
- `golf-sync-swing/Views/ComparisonView.swift` — `comparison_opened`, `feature_gate_hit` (advancedComparisonModes).
- `golf-sync-swing/Views/Components/ExportProgressView.swift` — `feature_gate_hit` (exportHD), `export_completed`.
- `golf-sync-swing/PrivacyInfo.xcprivacy` — `NSPrivacyCollectedDataTypes` (Usage Data + Device ID).

---

## External Setup (user actions — required before Task 4 build passes and before release)

These are credentials/dashboard steps, not code. Do them in parallel with implementation:
1. Create an Amplitude account (free Starter). Copy the project **API Key** (Settings → Organization → Projects → API Key). It is a client write key, safe to embed (the RevenueCat key is already embedded the same way).
2. In the **RevenueCat dashboard** → Integrations → Amplitude: paste the Amplitude API key, keep default event names, set US region (or EU if your Amplitude project is EU). This sends trial/conversion/renewal/churn server-side.
3. At App Store submission: update the privacy nutrition labels to match the manifest (Usage Data + Identifiers/Device ID, "Not Linked to You", purpose Analytics).

---

## Task 1: AnalyticsEvent taxonomy (TDD)

**Files:**
- Create: `golf-sync-swing/Services/Analytics/AnalyticsEvent.swift`
- Test: `golf-sync-swingTests/AnalyticsEventTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `golf-sync-swingTests/AnalyticsEventTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/AnalyticsEventTests test
```
Expected: FAILS to compile — "cannot find 'AnalyticsEvent' in scope".

- [ ] **Step 3: Write the implementation**

Create `golf-sync-swing/Services/Analytics/AnalyticsEvent.swift`:

```swift
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
}
```

> Note: `exportCompleted` takes `ExportAspectRatio?` (not a raw `String`) for type safety, mapping `nil → "legacy"` to cover the non-`layoutConfig` (legacy) export path. `String(describing:)` on a raw-valued enum returns the **case name** (e.g. `"stacked"`), not the display raw value (`"Stacked"`). The test above pins this behavior — keep it.

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/AnalyticsEventTests test
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add golf-sync-swing/Services/Analytics/AnalyticsEvent.swift golf-sync-swingTests/AnalyticsEventTests.swift
git commit -m "feat(analytics): typed AnalyticsEvent funnel taxonomy"
```

---

## Task 2: AnalyticsTracking seam, NoOp, Spy, and facade (TDD)

**Files:**
- Create: `golf-sync-swing/Services/Analytics/AnalyticsTracking.swift`
- Create: `golf-sync-swing/Services/Analytics/NoOpAnalytics.swift`
- Create: `golf-sync-swing/Services/Analytics/Analytics.swift`
- Create: `golf-sync-swingTests/Support/AnalyticsSpy.swift`
- Test: `golf-sync-swingTests/AnalyticsFacadeTests.swift`

- [ ] **Step 1: Write the failing test + the spy**

Create `golf-sync-swingTests/Support/AnalyticsSpy.swift`:

```swift
import Foundation
@testable import golf_sync_swing

final class AnalyticsSpy: AnalyticsTracking {
    private(set) var trackedEvents: [AnalyticsEvent] = []
    private(set) var identifiedUserIds: [String] = []

    func track(_ event: AnalyticsEvent) {
        trackedEvents.append(event)
    }

    func identify(userId: String) {
        identifiedUserIds.append(userId)
    }
}
```

Create `golf-sync-swingTests/AnalyticsFacadeTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/AnalyticsFacadeTests test
```
Expected: FAILS to compile — "cannot find 'AnalyticsTracking' / 'Analytics' / 'NoOpAnalytics'".

- [ ] **Step 3: Write the protocol**

Create `golf-sync-swing/Services/Analytics/AnalyticsTracking.swift`:

```swift
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
}
```

- [ ] **Step 4: Write NoOpAnalytics**

Create `golf-sync-swing/Services/Analytics/NoOpAnalytics.swift`:

```swift
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
}
```

- [ ] **Step 5: Write the Analytics facade**

Create `golf-sync-swing/Services/Analytics/Analytics.swift`:

```swift
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
}
```

> `configure()` references `AmplitudeAnalytics`, created in Task 4. Until then this file will not compile on its own — that's expected; Step 6 below temporarily stubs it so Task 2 is self-contained and testable. Task 4 replaces the stub.

- [ ] **Step 6: Add a temporary AmplitudeAnalytics stub so Task 2 compiles**

Create `golf-sync-swing/Services/Analytics/AmplitudeAnalytics.swift` (temporary — replaced in Task 4):

```swift
//
//  AmplitudeAnalytics.swift
//  golf-sync-swing
//
//  TEMPORARY STUB — replaced with the real Amplitude SDK wrapper in Task 4
//  once the Amplitude-Swift package is added.
//

import Foundation

final class AmplitudeAnalytics: AnalyticsTracking {
    func track(_ event: AnalyticsEvent) {}
    func identify(userId: String) {}
}
```

- [ ] **Step 7: Run to verify pass**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/AnalyticsFacadeTests test
```
Expected: PASS (3 tests).

- [ ] **Step 8: Commit**

```bash
git add golf-sync-swing/Services/Analytics/AnalyticsTracking.swift golf-sync-swing/Services/Analytics/NoOpAnalytics.swift golf-sync-swing/Services/Analytics/Analytics.swift golf-sync-swing/Services/Analytics/AmplitudeAnalytics.swift golf-sync-swingTests/Support/AnalyticsSpy.swift golf-sync-swingTests/AnalyticsFacadeTests.swift
git commit -m "feat(analytics): tracking seam, NoOp, spy, and shared facade"
```

---

## Task 3: Add the Amplitude-Swift SPM package

**Files:**
- Modify: `golf-sync-swing.xcodeproj` (via Xcode UI)
- Auto-updated: `.../swiftpm/Package.resolved`

This step uses the Xcode UI rather than hand-editing `project.pbxproj` (generated object IDs make manual edits error-prone — the existing RevenueCat reference is just for pattern reference).

- [ ] **Step 1: Add the package in Xcode**

In Xcode: **File → Add Package Dependencies…**
- Repository URL: `https://github.com/amplitude/Amplitude-Swift.git`
- Dependency Rule: **Up to Next Major Version**, starting from the latest 1.x shown.
- Add to target **golf-sync-swing** (the app target only — not the test/UI targets).
- Product to add: **AmplitudeSwift**.

- [ ] **Step 2: Verify the package resolved**

Run:
```bash
git status --short
```
Expected: `Package.resolved` shows as modified, with a new pin whose identity is `amplitude-swift`.

- [ ] **Step 3: Build to confirm the package links**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED (the temporary stub still satisfies the facade).

- [ ] **Step 4: Commit**

```bash
git add golf-sync-swing.xcodeproj
git commit -m "build(analytics): add Amplitude-Swift SPM dependency"
```

---

## Task 4: Real AmplitudeAnalytics implementation

**Files:**
- Modify (replace stub): `golf-sync-swing/Services/Analytics/AmplitudeAnalytics.swift`

- [ ] **Step 1: Replace the stub with the real wrapper**

Overwrite `golf-sync-swing/Services/Analytics/AmplitudeAnalytics.swift` with:

```swift
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
```

> `apiKey` is filled from the External Setup step. It is a configuration value (a client write key), not a secret — the engineer pastes the real value from the Amplitude project. Leave the literal name obvious so a missing key is caught in review.

- [ ] **Step 2: Build to verify it compiles against the SDK**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED. If `Configuration` rejects `autocapture:`, the installed SDK is older — use `defaultTracking: DefaultTrackingOptions(sessions: true, appLifecycles: false, screenViews: false)` instead (same effect).

- [ ] **Step 3: Re-run the analytics unit tests (regression)**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/AnalyticsEventTests -only-testing:golf-sync-swingTests/AnalyticsFacadeTests test
```
Expected: PASS (8 tests). Tests use NoOp/Spy, so they never hit the network.

- [ ] **Step 4: Commit**

```bash
git add golf-sync-swing/Services/Analytics/AmplitudeAnalytics.swift
git commit -m "feat(analytics): real Amplitude SDK wrapper (IDFV-only, session autocapture)"
```

---

## Task 5: Configure Analytics at app launch

**Files:**
- Modify: `golf-sync-swing/golf_sync_swingApp.swift` (init, after line 47)

- [ ] **Step 1: Add configure() call**

In `golf_sync_swingApp.swift` `init()`, change:

```swift
        PurchaseService.shared.configure()
        VideoPathMigrationService.migrateIfNeeded(modelContainer: sharedModelContainer)
```
to:
```swift
        Analytics.shared.configure()
        PurchaseService.shared.configure()
        VideoPathMigrationService.migrateIfNeeded(modelContainer: sharedModelContainer)
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/golf_sync_swingApp.swift
git commit -m "feat(analytics): initialize Amplitude at app launch"
```

---

## Task 6: Identity linking (Amplitude user = RevenueCat App User ID)

**Files:**
- Modify: `golf-sync-swing/Services/PurchaseService.swift` (`observeCustomerInfo()`, ~lines 55–61)

- [ ] **Step 1: Add identify() inside the customerInfo stream**

In `observeCustomerInfo()`, change:

```swift
        for await info in Purchases.shared.customerInfoStream {
            customerInfo = info
            isPremium = info.entitlements[Self.entitlementID]?.isActive == true
            AppLogger.general.info("PurchaseService: premium=\(self.isPremium)")
        }
```
to:
```swift
        for await info in Purchases.shared.customerInfoStream {
            customerInfo = info
            isPremium = info.entitlements[Self.entitlementID]?.isActive == true
            Analytics.shared.identify(userId: Purchases.shared.appUserID)
            AppLogger.general.info("PurchaseService: premium=\(self.isPremium)")
        }
```

> `setUserId` is idempotent, so re-calling it on every stream update is harmless. This is what joins app-side events with RevenueCat's server-sent monetization events.

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Services/PurchaseService.swift
git commit -m "feat(analytics): set Amplitude user id from RevenueCat app user id"
```

---

## Task 7: Onboarding events (started + completed)

**Files:**
- Modify: `golf-sync-swing/Views/Onboarding/OnboardingView.swift` (`.onAppear` ~line 44; `finishOnboarding()` ~lines 172–176)

- [ ] **Step 1: Fire onboarding_started on appear**

Change:
```swift
        .onAppear { revealSkipAfterDelay() }
```
to:
```swift
        .onAppear {
            Analytics.shared.track(.onboardingStarted)
            revealSkipAfterDelay()
        }
```

- [ ] **Step 2: Fire onboarding_completed in finishOnboarding()**

Change:
```swift
    private func finishOnboarding() {
        sheet = nil
        OnboardingService.shared.completeOnboarding()
        onComplete()
    }
```
to:
```swift
    private func finishOnboarding() {
        sheet = nil
        OnboardingService.shared.completeOnboarding()
        Analytics.shared.track(.onboardingCompleted)
        onComplete()
    }
```

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add golf-sync-swing/Views/Onboarding/OnboardingView.swift
git commit -m "feat(analytics): track onboarding started + completed"
```

---

## Task 8: Paywall events (shown + dismissed + purchased)

**Files:**
- Modify: `golf-sync-swing/Views/Paywall/CustomPaywallView.swift` (`.task` ~line 36; `closeButton` ~lines 126–144; `handlePurchaseOutcome` ~lines 186–195)

`AppPaywallView` is a 1:1 wrapper over `CustomPaywallView`, so instrumenting `CustomPaywallView` covers all three call sites (onboarding / featureGate / settings). The `source` property is in scope here.

- [ ] **Step 1: Fire paywall_shown in the existing .task**

Change:
```swift
        .task { await viewModel.loadOffering() }
```
to:
```swift
        .task {
            Analytics.shared.track(.paywallShown(source: source))
            await viewModel.loadOffering()
        }
```

- [ ] **Step 2: Fire paywall_dismissed only on the X button**

In `closeButton`, change:
```swift
            Button(action: onDismiss) {
                Image(systemName: "xmark")
```
to:
```swift
            Button {
                Analytics.shared.track(.paywallDismissed(source: source))
                onDismiss()
            } label: {
                Image(systemName: "xmark")
```

- [ ] **Step 3: Fire paywall_purchased on successful purchase**

In `handlePurchaseOutcome(_:)`, change:
```swift
        case .succeeded:
            onDismiss()
```
to:
```swift
        case .succeeded:
            Analytics.shared.track(.paywallPurchased(source: source))
            onDismiss()
```

> `.cancelled` (closed the StoreKit sheet) and `.failed` (error toast) fire nothing — the user stays on the paywall. Only the X button is a true dismissal.

- [ ] **Step 4: Build**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add golf-sync-swing/Views/Paywall/CustomPaywallView.swift
git commit -m "feat(analytics): track paywall shown, dismissed, and purchased"
```

---

## Task 9: main_app_reached

**Files:**
- Modify: `golf-sync-swing/Views/MainTabView.swift` (after `.tint(.appTeal)`)

- [ ] **Step 1: Fire main_app_reached on appear**

Change:
```swift
        .tint(.appTeal)
    }
```
to:
```swift
        .tint(.appTeal)
        .onAppear { Analytics.shared.track(.mainAppReached) }
    }
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Views/MainTabView.swift
git commit -m "feat(analytics): track main app reached"
```

---

## Task 10: Recording events (started + swing detected)

**Files:**
- Modify: `golf-sync-swing/ViewModels/RecordingViewModel.swift` (`beginRecording()` line ~213; `init()` swing-detected closure lines ~78–90)

- [ ] **Step 1: Fire recording_started after the state transition**

In `beginRecording()`, change:
```swift
        state = .recording
        cameraService.onFrameCaptured = { [weak self] pixelBuffer, timestamp in
```
to:
```swift
        state = .recording
        Analytics.shared.track(.recordingStarted)
        cameraService.onFrameCaptured = { [weak self] pixelBuffer, timestamp in
```

- [ ] **Step 2: Fire swing_detected in the onSwingDetected closure**

In `init()`, change:
```swift
                self.detectedSwings.append(clip)
                self.playbackSpeed = 1.0
                UINotificationFeedbackGenerator().notificationOccurred(.success)
```
to:
```swift
                self.detectedSwings.append(clip)
                self.playbackSpeed = 1.0
                Analytics.shared.track(.swingDetected)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
```

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add golf-sync-swing/ViewModels/RecordingViewModel.swift
git commit -m "feat(analytics): track recording started + swing detected"
```

---

## Task 11: video_imported

**Files:**
- Modify: `golf-sync-swing/Services/VideoImportService.swift` (`importVideo(from:into:)` after the save, ~line 19)

- [ ] **Step 1: Fire video_imported after a successful save**

Change:
```swift
        try await MainActor.run {
            modelContext.insert(video)
            try modelContext.save()
        }
        let isInTempDirectory = url.path.contains(NSTemporaryDirectory()) || url.path.contains("/tmp/")
```
to:
```swift
        try await MainActor.run {
            modelContext.insert(video)
            try modelContext.save()
        }
        Analytics.shared.track(.videoImported)
        let isInTempDirectory = url.path.contains(NSTemporaryDirectory()) || url.path.contains("/tmp/")
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Services/VideoImportService.swift
git commit -m "feat(analytics): track video imported"
```

---

## Task 12: comparison_opened + feature_gate_hit (comparison modes)

**Files:**
- Modify: `golf-sync-swing/Views/ComparisonView.swift` (`onViewAppear()` line ~189; `modeMenuItem` else-branch line ~133)

- [ ] **Step 1: Fire comparison_opened when the view-model is created**

In `onViewAppear()`, change:
```swift
        viewModel = vm
        vm.play()
```
to:
```swift
        viewModel = vm
        Analytics.shared.track(.comparisonOpened(mode: vm.comparisonMode))
        vm.play()
```

- [ ] **Step 2: Fire feature_gate_hit when a locked mode is tapped**

In `modeMenuItem(mode:viewModel:)` else-branch, change:
```swift
            Button {
                showPaywall = true
            } label: {
                Label(String(localized: "\(mode.displayName) (Pro)", comment: "Mode picker label for premium-locked modes"), systemImage: "lock.fill")
            }
```
to:
```swift
            Button {
                if let feature = mode.premiumFeature {
                    Analytics.shared.track(.featureGateHit(feature: feature))
                }
                showPaywall = true
            } label: {
                Label(String(localized: "\(mode.displayName) (Pro)", comment: "Mode picker label for premium-locked modes"), systemImage: "lock.fill")
            }
```

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add golf-sync-swing/Views/ComparisonView.swift
git commit -m "feat(analytics): track comparison opened + comparison feature gate"
```

---

## Task 13: feature_gate_hit (HD export) + export_completed

**Files:**
- Modify: `golf-sync-swing/Views/Components/ExportProgressView.swift` (`qualityRow` locked branch line ~150; `handleExportResult` success case line ~325)

- [ ] **Step 1: Fire feature_gate_hit when locked export quality is tapped**

In `qualityRow(_:)`, change:
```swift
            guard !locked else {
                showPaywall = true
                return
            }
```
to:
```swift
            guard !locked else {
                Analytics.shared.track(.featureGateHit(feature: .exportHD))
                showPaywall = true
                return
            }
```

- [ ] **Step 2: Fire export_completed on success**

In `handleExportResult(_:)`, change:
```swift
        case .success(let url):
            exportedURL = url
```
to:
```swift
        case .success(let url):
            exportedURL = url
            Analytics.shared.track(.exportCompleted(
                aspectRatio: layoutConfig?.aspectRatio,
                isHD: selectedQuality.requiresPremium
            ))
```

> `layoutConfig` is a `let VideoLayoutConfig?` on the view; `layoutConfig?.aspectRatio` is an `ExportAspectRatio` whose `rawValue` is the case name (e.g. `"tikTokVertical"`). `selectedQuality.requiresPremium` is `true` for `.high`/`.ultra`. Both are in scope at this line.

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add golf-sync-swing/Views/Components/ExportProgressView.swift
git commit -m "feat(analytics): track export feature gate + export completed"
```

---

## Task 14: Privacy manifest (Usage Data + Device ID)

**Files:**
- Modify: `golf-sync-swing/PrivacyInfo.xcprivacy`

- [ ] **Step 1: Populate NSPrivacyCollectedDataTypes**

The array is currently empty. Change:
```xml
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
```
to:
```xml
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeProductInteraction</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<false/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAnalytics</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeDeviceID</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<false/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAnalytics</string>
			</array>
		</dict>
	</array>
```

> `NSPrivacyTracking` stays `<false/>` and `NSPrivacyTrackingDomains` stays empty — we use IDFV (vendor id), not IDFA, and do not track across apps. `Linked = false` (anonymous), `Tracking = false`, purpose `Analytics`.

- [ ] **Step 2: Validate the plist parses**

Run:
```bash
plutil -lint golf-sync-swing/PrivacyInfo.xcprivacy
```
Expected: `golf-sync-swing/PrivacyInfo.xcprivacy: OK`.

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add golf-sync-swing/PrivacyInfo.xcprivacy
git commit -m "chore(privacy): declare Usage Data + Device ID for Amplitude analytics"
```

---

## Task 15: Full verification + docs

**Files:**
- Modify: `docs/project_status.md`, `docs/changelog.md` (via the update-changelog skill or by hand)

- [ ] **Step 1: Full build + full test suite**

Run:
```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: all tests pass, including the 8 new analytics tests; no regressions. (Pose-dependent GolfDB tests remain skipped on simulator — that is the existing baseline.)

- [ ] **Step 2: Confirm the API key is set**

Verify `AmplitudeAnalytics.apiKey` is the real key (not `PASTE_AMPLITUDE_API_KEY_FROM_DASHBOARD`). Run:
```bash
grep -n "PASTE_AMPLITUDE_API_KEY_FROM_DASHBOARD" golf-sync-swing/Services/Analytics/AmplitudeAnalytics.swift
```
Expected: no output (placeholder replaced).

- [ ] **Step 3: Manual end-to-end event-stream check**

In Amplitude: **Data → Sources → (your iOS source) → Live event stream** (or User Lookup). On a device/simulator build, exercise the funnel and confirm each event arrives with correct properties:

| Action | Expected event | Property to verify |
|---|---|---|
| Fresh launch (reset onboarding via Settings → Debug) | `onboarding_started` | — |
| Reach paywall in onboarding | `paywall_shown` | `source = onboarding` |
| Tap X on paywall | `paywall_dismissed` | `source = onboarding` |
| Finish onboarding | `onboarding_completed`, then `main_app_reached` | — |
| Import a video on Compare tab | `video_imported` | — |
| Open a comparison | `comparison_opened` | `mode = sideBySide` |
| Tap a locked mode (Stacked/Sequential) | `feature_gate_hit` | `feature = advancedComparisonModes` |
| Tap HD/Ultra export quality while free | `feature_gate_hit` | `feature = exportHD` |
| Finish an export | `export_completed` | `aspect_ratio`, `is_hd` |
| Record a swing (**physical device only** — Vision pose detection does not run on simulator) | `recording_started`, `swing_detected` | — |

Note which export flow actually presents the quality picker: `ExportQuality` (and thus `is_hd`/the `exportHD` gate) drives the legacy comparison export; the editor/`layoutConfig` path renders by aspect-ratio dimensions and may not show the picker, so `is_hd` reads `false` there. That's expected — read `is_hd` as "user chose HD quality in the legacy export," not "output was high-res." Confirm the behavior of each path during this check so the funnel is interpreted correctly later.

Confirm `paywall_purchased` fires on a sandbox purchase, and that the Amplitude user shows a `user_id` equal to the RevenueCat App User ID once `customerInfoStream` emits.

- [ ] **Step 4: Update docs**

Add a dated entry to `docs/changelog.md` (Added: funnel analytics instrumentation) and update `docs/project_status.md` (Monetization milestone). Then:
```bash
git add docs/changelog.md docs/project_status.md
git commit -m "docs(analytics): record funnel instrumentation in changelog + status"
```

- [ ] **Step 5: Finish the branch**

Use the superpowers:finishing-a-development-branch skill to decide merge / PR for `feat/funnel-analytics`.

---

## Self-Review

**Spec coverage:**
- ✅ Tool = Amplitude free + RevenueCat integration (Tasks 3, 6; External Setup).
- ✅ Protocol-based typed events, DI, NoOp (Tasks 1, 2).
- ✅ Amplitude isolated to one file, IDFV-only, session autocapture (Task 4).
- ✅ Identity linking (Task 6).
- ✅ All 10 spec events + the justified `paywall_purchased` addition (Tasks 7–13).
- ✅ Privacy manifest + nutrition-label note (Task 14, External Setup).
- ✅ Success criteria verified (Task 15 build/test/event-stream checklist).
- ✅ Track 0 (App Store Connect + RevenueCat dashboards) — captured in the spec; nothing to build.

**Deviation from spec (intentional):** Added `paywall_purchased` (app-side, fired at `handlePurchaseOutcome.succeeded`). The spec said purchases come only from RevenueCat. This one extra event directly answers the highest-value funnel question ("does the first paywall convert?") immediately, without depending on the RevenueCat→Amplitude join being perfectly configured. One line at a verified anchor. Kept.

**Placeholder scan:** No "TBD"/"TODO"/"implement later". The single literal `PASTE_AMPLITUDE_API_KEY_FROM_DASHBOARD` is a real external credential the engineer fills (Task 4 + verified in Task 15 Step 2), not an unfinished implementation.

**Type consistency:** `AnalyticsTracking.track(_:)`/`identify(userId:)` are used identically in `NoOpAnalytics`, `AmplitudeAnalytics`, `Analytics`, and `AnalyticsSpy`. Event factory names (`onboardingStarted`, `paywallShown(source:)`, `comparisonOpened(mode:)`, `featureGateHit(feature:)`, `exportCompleted(aspectRatio:isHD:)`) match between Task 1 definitions and Tasks 7–13 call sites. `PaywallSource`, `ComparisonMode`, `PremiumFeature`, `ExportQuality.requiresPremium`, `VideoLayoutConfig.aspectRatio` are all verified to exist with the referenced shapes.
