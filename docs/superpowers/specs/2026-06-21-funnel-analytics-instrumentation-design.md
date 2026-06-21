# Funnel Analytics Instrumentation — Design

**Date**: 2026-06-21
**Status**: Approved (minimal skeleton scope)
**Author**: Brainstorming session

---

## Problem

We want to know **where most users drop off** in Golf Sync Swing. Today we cannot
answer this: the app has **zero in-app analytics**. The only third-party SDK is
RevenueCat (`purchases-ios-spm`), and there are no event-tracking calls anywhere in
the Swift code. The only behavioral signals available are RevenueCat (bottom of the
funnel) and App Store Connect (top of the funnel) — nothing covers the **middle**
(onboarding abandonment, "downloaded but never recorded," "recorded but never
exported").

## Goal

Instrument a minimal end-to-end funnel so that, within ~1–2 weeks of a release, an
Amplitude funnel chart reveals the single largest drop-off stage. Start with a
~10-event skeleton; add granular events around the leakiest stage in a follow-up.

## Non-Goals (YAGNI)

- Per-onboarding-page sub-events, plan-picker micro-interactions, every comparison mode permutation.
- A/B testing, experiments, feature flags.
- Session replay (free tier includes some, but it is not needed for funnel analysis).
- Custom dashboards beyond Amplitude's core funnel chart.
- Any PII; events are anonymous (device-scoped) — see Privacy.

---

## The two tracks

Instrumentation **only measures going forward**. It requires a new App Store release
plus traffic accumulation before any funnel is readable. So the answer is delivered
in two parallel tracks:

### Track 0 — existing data, zero code (do now, in parallel)
- **App Store Connect → App Analytics**: impressions → downloads → first sessions → retention. (Top of funnel.)
- **RevenueCat dashboard**: paywall views → trial starts → conversions → churn. (Bottom of funnel.)
- These bracket the funnel. The gap they cannot see is what Track 1 instruments.

### Track 1 — instrument the middle (this build)
- The ~10-event skeleton below, shipped in the next App Store release.

---

## Tool choice: Amplitude (free Starter tier)

- **Free Starter (2026)**: 10,000 monthly tracked users, 2M events/month, no credit card. **Funnel analysis is included** in core analytics.
- 10K MTU is sufficient for an indie launch; outgrowing it is a happy problem.
- **RevenueCat → Amplitude native integration**: RevenueCat sends trial-start / conversion / renewal / churn events to Amplitude **server-side, with no app code** — configured in the RevenueCat dashboard with the Amplitude API key. This supplies the bottom of the funnel for free.

---

## Architecture

Protocol-based, typed events, dependency-injected — consistent with the project's
Sandi Metz principles (small things, single responsibility, no stringly-typed calls,
no Amplitude leaking into views).

### Components

- **`AnalyticsTracking` (protocol)** — the seam. `func track(_ event: AnalyticsEvent)` and `func identify(userId: String)`. Everything depends on this, not on Amplitude.
- **`AmplitudeAnalytics`** — the production implementation. Wraps the Amplitude Swift SDK; configures it IDFV-only (no IDFA). Initialized in `golf_sync_swingApp.init()` next to `PurchaseService.shared.configure()`.
- **`NoOpAnalytics`** — does nothing. Default for SwiftUI previews and tests.
- **`AnalyticsEvent` (value type)** — `name: String` + `properties: [String: Any]`, produced **only** via static factory methods (e.g. `.paywallShown(source:)`, `.comparisonOpened(mode:)`). No central `switch`; adding an event means adding a factory method (open/closed). Call sites stay type-safe even though storage is `[String: Any]` at the SDK boundary.
- **`Analytics`** — a thin shared facade (`Analytics.shared`) resolving to `AmplitudeAnalytics` in the app, mirroring the existing `PurchaseService.shared` / `OnboardingService.shared` pattern.

### Dependency injection

ViewModels and services that fire events take an `AnalyticsTracking` parameter with a
default of `.shared` (the same pattern as `OnboardingService(defaults: .standard)`).
Tests inject an `AnalyticsSpy` (records events) or `NoOpAnalytics`. Events fire from
**ViewModels / Services**, never from "dumb" views — except unavoidable
appearance-based milestones (e.g. `main_app_reached`), which fire from a small
`.onAppear` calling the injected tracker.

### Identity linking

On launch, and whenever RevenueCat's `customerInfo` updates, call
`Analytics.shared.identify(userId: Purchases.shared.appUserID)`. This sets Amplitude's
user ID equal to the RevenueCat App User ID so the app-side funnel events and the
RevenueCat-sent monetization events **join into one funnel**. Small, and it is what
makes the two halves connect — included in v1.

### API key

Amplitude's client write key is not a secret in the same sense as a server key
(it is ingestion-only). Store it as a build constant / xcconfig value. Used in
`AmplitudeAnalytics` configuration.

---

## Event taxonomy (the ~10-event skeleton)

| Event | Fires from | Properties |
|---|---|---|
| `onboarding_started` | onboarding flow first appear | — |
| `onboarding_completed` | the call site of `OnboardingService.completeOnboarding()` | — |
| `paywall_shown` | `PaywallViewModel` on present | `source` (reuse existing `PaywallSource`: onboarding / featureGate / settings) |
| `paywall_dismissed` | `PaywallViewModel` on close-without-purchase | `source` |
| `main_app_reached` | `MainTabView` first `.onAppear` | — |
| `recording_started` | `RecordingViewModel` | — |
| `swing_detected` | `RecordingViewModel` (`onSwingDetected`) | — |
| `video_imported` | `VideoImportService` / Home import completion | — |
| `comparison_opened` | `ComparisonViewModel` init / `ComparisonView` appear | `mode` |
| `export_completed` | `VideoExportService` / export success | `aspect_ratio`, `is_hd` |
| `feature_gate_hit` | locked comparison-mode / HD-export tap handlers | `feature` — **the highest-value "intent to convert" signal** |

Monetization events (`trial_started`, `conversion`, `renewal`, `churn`) come from the
**RevenueCat → Amplitude integration**, not app code.

Amplitude **autocapture** is enabled for sessions only (free session/retention data),
layered under these hand-defined events. Screen/tap autocapture is **off** (SwiftUI
screen names are unreliable and would not map to our milestones).

---

## Funnel definitions (the drop-off questions each answers)

1. **Onboarding completion**: `onboarding_started` → `onboarding_completed` — how many bail mid-onboarding?
2. **Paywall outcome**: `onboarding_completed` → (`paywall_dismissed` vs. RevenueCat `trial_started`) — does the first paywall convert or repel?
3. **Activation start**: `main_app_reached` → first core action (`recording_started` OR `video_imported`) — do users ever *use* the app?
4. **Aha moment**: first core action → (`swing_detected` OR `comparison_opened`) — do they reach the value?
5. **Output**: activation → `export_completed` — do they finish a comparison?
6. **Conversion intent**: `feature_gate_hit` → RevenueCat `conversion` — does hitting a lock drive a purchase?

The largest stage-to-stage drop identifies where to invest next.

---

## Privacy (hard gate — shipped v1.2.0 app, rides the next App Store review)

- **`PrivacyInfo.xcprivacy`**: declare collected data types — Usage/Product-Interaction Data and Device ID — marked **not linked to identity**, purpose **Analytics**.
- **App Store privacy nutrition labels**: add Usage Data + Identifiers (Device ID), "Data Not Linked to You," Analytics purpose.
- **IDFV-only**: configure Amplitude to use the vendor identifier, **not** IDFA. No App Tracking Transparency prompt is required.

---

## Testability

- `AnalyticsTracking` seam → inject `NoOpAnalytics` in previews, `AnalyticsSpy` in tests.
- Unit tests assert the right event fires with the right properties at each ViewModel milestone (e.g. `paywall_shown` carries the correct `source`).
- No network calls in tests — the spy/no-op never touches the SDK.

---

## Success criteria

1. Next App Store build ships with the Amplitude SDK + all skeleton events firing, verified via Amplitude's live event stream on a test device.
2. RevenueCat → Amplitude integration configured; monetization events appear in Amplitude joined to app events by user ID.
3. `PrivacyInfo.xcprivacy` + nutrition labels updated; no ATT prompt appears; build passes App Store review.
4. Within ~1–2 weeks, Amplitude funnel chart renders all six funnels and the single largest drop-off stage is identifiable.

---

## Dependencies / external setup (user actions)

- Create Amplitude account, obtain API key (free Starter).
- Configure RevenueCat → Amplitude integration in the RevenueCat dashboard.
- Update App Store privacy labels at submission.
- Confirm Amplitude Swift SDK version available via SPM during implementation.
