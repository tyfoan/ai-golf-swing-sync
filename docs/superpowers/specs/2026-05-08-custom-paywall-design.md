# Custom Paywall Design

**Date:** 2026-05-08
**Status:** Spec — pending user approval before plan + implementation
**Branch (target):** `feat/custom-paywall` (off `fix/tier-1-bug-audit` or `main`)
**Related files:** `golf-sync-swing/Views/Paywall/AppPaywallView.swift`, `Services/PurchaseService.swift`

## 1. Goal

Replace the RevenueCatUI dashboard-driven `PaywallView` (currently wrapped by `AppPaywallView`) with a hand-built SwiftUI paywall. The new paywall:

- Visually continuous with the existing dark-mesh-gradient onboarding (gold accent, `.fairwayGreen` CTA gradient).
- Adds a third plan: **Lifetime non-consumable** alongside the existing weekly + annual subscriptions.
- Honors Viktor Seraleev's published guardrails (anti-bait-switch, transparent pricing, paywall-after-onboarding) and Adam Lyttle's content patterns (hero, 3 features, 2 stacked-card plan picker — extended to 3 cards here).
- Same external surface: `AppPaywallView(source: PaywallSource, onDismiss: () -> Void)` so the 3 call sites (Onboarding, FeatureGate, Settings) need no changes.

## 2. Pricing & Trials

| Product ID | Type | Price | Intro offer | Cards label |
|---|---|---|---|---|
| `golfswing.weekly` | Auto-Renewable Subscription · 1 week | $4.99/wk | 3-day free trial | "Weekly" |
| `golfswing.annual` | Auto-Renewable Subscription · 1 year | $49.99/yr | 7-day free trial | "Annual — BEST VALUE · SAVE 81%" (default-selected) |
| `golfswing.lifetime` | Non-Consumable | $79.99 (one-time) | n/a | "Lifetime — FOREVER" |

Annual savings math: `1 - 49.99 / (4.99 × 52) = 81.4%` → rounded to "Save 81%". Equivalent shown as `≈ $0.96/wk` underneath. All math derived from `package.storeProduct.price` at runtime so regional pricing self-adjusts.

Trial copy comes from `package.storeProduct.introductoryDiscount.subscriptionPeriod` — never hardcoded. Trial eligibility is queried via `Purchases.shared.checkTrialOrIntroductoryDiscountEligibility(productIdentifiers:)`; if a user is ineligible, the trial line is stripped and CTA changes from "Start Free Trial" to "Subscribe — $X/yr".

## 3. Architecture

Composable shell + 5 section views + 1 view model + 1 plan value type. Each file ≤ 200 lines.

```
golf-sync-swing/Views/Paywall/
├── AppPaywallView.swift              (kept — body now `CustomPaywallView`)
├── PaywallSource.swift               (kept)
├── CustomPaywallView.swift           (~150 lines — composition + @State)
├── Components/
│   ├── PaywallHero.swift             (~80 lines)
│   ├── PaywallFeatureList.swift      (~70 lines)
│   ├── PaywallPlanPicker.swift       (~140 lines)
│   ├── PaywallCTA.swift              (~50 lines)
│   └── PaywallFooter.swift           (~50 lines)
└── Model/
    ├── PaywallPlan.swift             (~60 lines — value type, savings calc)
    └── PaywallViewModel.swift        (~120 lines — RC integration)
```

State ownership: `PaywallViewModel` is the single source of truth for plans, selection, and load/error state. Section views are dumb — receive props and emit selection callbacks.

## 4. Components

### 4.1 `PaywallHero` (~38% of screen)

- Gold pre-headline `"GOLF SYNC PRO"` (caption2 bold, tracking 2).
- 3-line heavy headline 28pt, copy varies by source:
  - `.onboarding`: "Your swing\nvs a pro's.\nFrame-locked."
  - `.featureGate`: "Unlock\nthe full\ncomparison."
  - `.settings`: "Go Pro.\nEvery feature.\nForever."
- Subheadline 13pt, white 70%, 1 line.
- Phone-frame containing looping `KillerSyncMockup` (existing component reused) with subtle scrubbing animation on the impact line.

### 4.2 `PaywallFeatureList` (3 fixed rows, 60–70pt each)

Each row: 28pt SF Symbol icon (gold tint) + bold title + 1-line subtitle.

1. `figure.golf` — "Auto-sync at impact" — "Frame-perfect alignment with any pro."
2. `slowmo` — "Slow-mo + drawing tools" — "8× slow-motion, lines, angles, HD export."
3. `square.on.square` — "Onion-skin & overlay" — "Compare like a coach."

### 4.3 `PaywallPlanPicker` (3 cards stacked, 8pt spacing)

Each card: 14pt rounded corners, 1.5pt border (gold when selected, white-30% otherwise), 12pt internal vertical padding.

- **Lifetime** (top): gold "ONE-TIME · FOREVER" badge top-right · "$79.99" large · "Pay once, yours forever" small.
- **Annual** (middle, **default-selected**): gold "BEST VALUE · SAVE 81%" badge · "$49.99/yr" large · "≈ $0.96/wk · 7-day free trial" small.
- **Weekly** (bottom): no badge · "$4.99/wk" large · "3-day free trial" small.

Single-tap selects. Selection state owned by `PaywallViewModel.selectedPlanId`.

### 4.4 `PaywallCTA` (full-width, 16pt vertical padding)

- `.onboardingRichGreen → .fairwayGreen` gradient + green shadow (matches onboarding action button).
- Label adapts to selection:
  - Annual → "Start 7-Day Free Trial"
  - Weekly → "Start 3-Day Free Trial"
  - Lifetime → "Buy Forever — $79.99"
- 11pt subtitle below in 50% white: "Cancel anytime." (replaced with "One-time payment." for Lifetime).

### 4.5 `PaywallFooter` (10pt caption, 40% white, evenly spaced HStack)

"Restore Purchases" (button) · "Terms" · "Privacy". Last two open `withcoach.app/terms` / `withcoach.app/privacy` in `SFSafariViewController`.

### 4.6 Close button

Small grey × top-leading, 24pt tap target. **Always visible across all 3 sources.** Per Seraleev: never remove via remote config after App Review passes; consistent paywall avoids dark-pattern violations.

## 5. View Model

```swift
@Observable
final class PaywallViewModel {
    enum LoadState { case loading, ready, failed(String) }
    enum PurchaseOutcome { case succeeded, cancelled, failed(String) }
    enum RestoreOutcome { case succeeded, noActiveEntitlement, failed(String) }

    private(set) var state: LoadState = .loading
    private(set) var plans: [PaywallPlan] = []           // ordered: lifetime, annual, weekly
    var selectedPlanId: PaywallPlan.ID?

    init(source: PaywallSource, purchases: PurchasesType = LivePurchases())  // LivePurchases is a thin struct that forwards each call to Purchases.shared.

    func loadOffering() async
    func purchaseSelected() async -> PurchaseOutcome
    func restore() async -> RestoreOutcome
}
```

`PurchasesType` is a thin protocol over the 4 RC calls used (`offerings()`, `purchase(package:)`, `restorePurchases()`, `checkTrialOrIntroductoryDiscountEligibility(productIdentifiers:)`). Lets unit tests inject a fake.

`PaywallPlan` is a value type with: `id`, `kind` (`.lifetime` / `.annual` / `.weekly`), `priceString`, `trialString?`, `savingsBadge?`, `equivalentString?`, `lineUnderPrice`, and the underlying `Package` (kept private to the module so the view never touches RC types).

## 6. RevenueCat Integration

```swift
// 1. Fetch offering
let offerings = try await Purchases.shared.offerings()
guard let current = offerings.current else { throw PaywallError.noOffering }

// 2. Map to plans — typed package convenience accessors (RC 5.x)
let lifetime = current.lifetime    // Package?
let annual   = current.annual      // Package?
let weekly   = current.weekly      // Package?

// 3. Purchase
let result = try await Purchases.shared.purchase(package: selectedPackage)
if result.userCancelled { /* outcome = .cancelled */ }
let active = result.customerInfo.entitlements[PurchaseService.entitlementID]?.isActive == true

// 4. Restore
let info = try await Purchases.shared.restorePurchases()
let active = info.entitlements[PurchaseService.entitlementID]?.isActive == true

// 5. Trial eligibility (so we don't promise trials to ineligible users)
let dict = await Purchases.shared.checkTrialOrIntroductoryDiscountEligibility(
    productIdentifiers: [annual.storeProduct.productIdentifier,
                         weekly.storeProduct.productIdentifier])
```

On success or successful restore, the view model calls `PurchaseService.shared.refreshStatus()` so the singleton stays the source of truth for `isPremium` across the app. `PurchaseService` itself is unchanged.

## 7. Source Variation

Only these aspects change per source. Hero animation, feature list, plan layout, CTA, footer, and close-button visibility are identical (Seraleev consistency rule).

| Aspect | `.onboarding` | `.featureGate` | `.settings` |
|---|---|---|---|
| Headline copy | "Your swing vs a pro's. Frame-locked." | "Unlock the full comparison." | "Go Pro. Every feature. Forever." |
| Default plan | annual | annual | annual |

The project does not currently have an analytics framework wired up; `PaywallSource`'s "for analytics" comment is forward-looking. When analytics ships, source-tagged events (`paywall_shown:<source>`, `paywall_purchase_started`, `paywall_purchase_completed`, `paywall_dismissed`) drop in via `PaywallViewModel`. Out of scope for this spec.

## 8. Error Handling

| Failure | UX | Code path |
|---|---|---|
| `offerings()` throws | Banner above CTA: "Couldn't load plans. Tap to retry." CTA disabled. | `state = .failed(message)` |
| No `current` offering | Same. | `state = .failed("No offering configured")` |
| Selected package `nil` (lifetime missing for some users) | Card filtered out before render. | View model filters before publishing `plans`. |
| `purchase()` throws | Toast: "Couldn't complete purchase." Paywall stays open. | `AppLogger.general.error(...)`. |
| `purchase()` `userCancelled` | Silent no-op. | No log. |
| `restorePurchases()` throws | Toast: "Restore failed. Check your connection." | Logged. |
| Restore succeeds, no entitlement | Toast: "No previous purchase found." | Common on first install. |
| Eligibility fetch fails | Default to "trial" copy assuming eligible. RC + StoreKit enforce on actual purchase. | Non-blocking. |

Purchase button has 2-second cooldown after success/failure to prevent double-tap.

## 9. App Store Connect + RevenueCat Dashboard Changes

**App Store Connect → In-App Purchases:**

- Update `golfswing.weekly` price to $4.99/wk; ensure 3-day intro free trial offer is active.
- Update `golfswing.annual` price to $49.99/yr; ensure 7-day intro free trial offer is active.
- Create `golfswing.lifetime` (Non-Consumable) at $79.99.
- Subscription Group `"Premium"` contains weekly + annual. Lifetime is independent.

**RevenueCat dashboard:**

- **Products:** link the new `golfswing.lifetime`.
- **Entitlements:** attach `golfswing.lifetime` to `Golf Swing Sync Premium`.
- **Offerings → default:** ensure 3 packages with RC-typed identifiers `$rc_lifetime`, `$rc_annual`, `$rc_weekly`. The typed identifiers are what makes `offering.lifetime / .annual / .weekly` work in code.

These changes will be executed via Chrome / Playwright after spec approval, with explicit confirmation before each ASC mutation.

## 10. Testing

**Unit tests** (`golf-sync-swingTests/Paywall/`):

- `PaywallPlanTests` — savings math (81%), equivalent weekly ($0.96), formatted strings stable across regional pricing fixtures.
- `PaywallViewModelTests` — uses `FakePurchases` conforming to `PurchasesType`. Cases:
  - happy path: load → annual selected → purchase succeeds → outcome = `.succeeded`
  - cancelled: outcome = `.cancelled`, no error log
  - load fails: state = `.failed`, retry recovers
  - restore with no entitlement: outcome = `.noActiveEntitlement`
  - lifetime package missing: plans array has 2 entries, view doesn't crash

**Manual QA on iPhone 17 simulator:**

- Trigger paywall from each of the 3 sources.
- Confirm close button works in each.
- Sandbox: complete weekly trial → verify `isPremium == true` → restore on second sandbox install.

No UI snapshot tests (project doesn't use them today; not adding the dependency).

## 11. Rollout

- Single PR. No feature flag.
- The custom paywall replaces the RC dashboard paywall in one cut. RC dashboard config remains as a passive fallback if revert is ever needed (`AppPaywallView` body is the only thing changed).
- Production API key blocker (`PurchaseService.swift:30-31` `#error`) is **not** part of this paywall change — separate ship-blocker, already known.

## 12. Out of Scope

- Lifetime upgrade flow for existing weekly/annual subscribers (no proration UI).
- Win-back / promotional offers.
- A/B testing infrastructure (added later if conversion data warrants).
- Localization beyond what RC's `localizedPriceString` already provides.
- UI snapshot testing.
- Analytics events — drop in once an analytics framework lands. View model is structured so call sites are obvious.
- Production RevenueCat API key swap in `PurchaseService.swift:30-31` (separate ship-blocker, already known).

## 13. References

- Existing RevenueCat integration: `Services/PurchaseService.swift`
- Onboarding visual language: `Views/Onboarding/OnboardingView.swift`, `OnboardingPageView.swift`
- Killer-first hero mockup: `KillerSyncMockup` (already used in onboarding page 1)
- Recent paywall redesign spec (RC-dashboard era): `docs/superpowers/specs/2026-05-04-onboarding-paywall-redesign.md`
- Viktor Seraleev's published principles (extracted from search snippets — X profile is auth-walled): show paywall after onboarding; lifetime works from onboarding; show real billed price; never bait-switch via remote config; consistent paywall across surfaces.
- Adam Lyttle paywall pattern: hero / 3 features / stacked plan cards / single CTA / footer.
- RevenueCat iOS SDK 5.x docs (queried via Context7 `/revenuecat/docs`).
