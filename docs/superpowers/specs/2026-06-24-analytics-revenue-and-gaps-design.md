# Analytics: revenue tracking + funnel gaps

**Date:** 2026-06-24
**Branch:** `feat/analytics-revenue-and-gaps`

## Context

Amplitude (project `golf-sync-swing`, appId `831534`) shows only 7 events, all
from 3 pre-launch test sessions that went onboarding → paywall and no further.
The recording / comparison / export-completed events **already exist in code**
and are wired correctly — they simply haven't been triggered since the API key
activated (commit `59eeda5`). Delivery is proven: onboarding/paywall events
travel the same `Analytics.shared.track()` → `AmplitudeAnalytics.track()` path.

This change fills the *genuine* gaps, the largest being real purchase/revenue
tracking, so the monetization funnel becomes measurable end-to-end.

## Decisions

- **Full revenue tracking** via Amplitude's `Revenue` API (not stringified event
  props). `AnalyticsEvent` stays `[String: String]`; money flows through a new
  `record(_:)` seam method.
- **`is_premium` user property** set from the entitlement observer so every
  funnel can be segmented by paid vs free.
- **Keep `paywall_purchased`** (unified paywall-conversion terminal) *and* add
  `purchase_completed` / `trial_started` (revenue + plan breakdown). They answer
  different questions.
- **Defer** section-E extras (`recording_stopped`, `swing_marker_edited`) to a
  follow-up to keep this change coherent and reviewable.

## Seam changes (`Services/Analytics/`)

- `AnalyticsTracking` gains:
  - `func record(_ revenue: PurchaseRevenue)` → Amplitude `Revenue` API.
  - `func setPremium(_ isPremium: Bool)` → `identify(userProperties: ["is_premium": ...])`.
- New value type `PurchaseRevenue { productId: String, price: Double, currency: String, quantity: Int = 1 }`.
- `AmplitudeAnalytics`: implement both (verified: `Revenue` supports
  `productId`/`price`/`quantity`/`currency`; `revenue(revenue:)` ignores nil-price
  so trials never count as revenue).
- `NoOpAnalytics`: no-op both. `AnalyticsSpy` (tests): record both.

## New events (`AnalyticsEvent.swift`)

| Factory | name | properties |
|---|---|---|
| `purchaseCompleted(plan:productId:price:currency:source:)` | `purchase_completed` | plan, product_id, price, currency, source |
| `trialStarted(plan:productId:source:)` | `trial_started` | plan, product_id, source |
| `purchaseRestored(source:)` | `purchase_restored` | source |
| `exportStarted(aspectRatio:quality:)` | `export_started` | aspect_ratio, quality |
| `exportFailed(aspectRatio:reason:)` | `export_failed` | aspect_ratio, reason |
| `swingSaved(saveType:count:)` | `swing_saved` | save_type, count |
| `comparisonModeChanged(from:to:)` | `comparison_mode_changed` | from, to |

Property values use existing conventions: enum `rawValue`/case name, numbers and
bools stringified, aspect ratio `nil → "legacy"`.

## Call sites

- **`PaywallViewModel`**: enrich `PurchaseOutcome.succeeded` → `.succeeded(PurchaseRecord)`
  where `PurchaseRecord { productId, plan, price, currency, isTrial }`. `isTrial`
  from `result.customerInfo.entitlements[id]?.periodType == .trial`; price/currency/
  productId from `plan.package.storeProduct`; plan from `PaywallPlan.Kind`.
- **`CustomPaywallView.handlePurchaseOutcome(.succeeded(record))`**: keep
  `paywall_purchased`; then if `record.isTrial` → `trial_started`, else
  `purchase_completed` **+ `Analytics.shared.record(revenue)`**.
- **`CustomPaywallView.handleRestoreOutcome(.succeeded)`**: `purchase_restored(source:)`.
- **`PurchaseService.observeCustomerInfo()`**: `Analytics.shared.setPremium(isPremium)`
  next to the existing `identify(...)`.
- **`ExportProgressView.startExport()`**: `export_started`; non-cancelled failure
  branch of `handleExportResult` → `export_failed` (reason = `String(describing: error)`,
  stable case name, not localized).
- **`RecordingViewModel.finalizeSave(...)`** (before clearing `detectedSwings`):
  `swing_saved` with `save_type = detectedSwings.isEmpty ? "full" : "clip"`, count.
- **`ComparisonViewModel.onModeChanged(from:)`**: `comparison_mode_changed(from: old, to: comparisonMode)`.

## Tests

- `AnalyticsEventTests`: name + properties for each new factory (incl. trial vs paid).
- `AnalyticsSpy`: add `recordedRevenue: [PurchaseRevenue]`, `premiumFlags: [Bool]`.
- `AnalyticsFacadeTests`: facade routes `record(_:)` and `setPremium(_:)` to tracker;
  `NoOpAnalytics` swallows both.
- Build + run on iPhone 17 simulator.

## After this ships

Monetization funnel by source *and* plan; revenue/LTV; "which plan converts";
any funnel segmented by `is_premium`; export started→completed/failed drop-off;
activation chain `recording_started → swing_detected → swing_saved`.
