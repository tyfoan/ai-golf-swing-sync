# Onboarding & Paywall Redesign

**Date:** 2026-05-04
**Status:** Approved, in implementation

## Problem

Current onboarding (3 SF-symbol pages with bullet lists) and paywall don't convert. User wants Adam-Lyttle-/Виктор-Сералеев-style content — bold typography, social proof, killer-first product showcase, weekly trial.

## Decisions

1. **Architecture:** Product-showcase (3 demo screens → paywall). User picked `B`.
2. **Content order:** Killer-first (AI sync at impact → Smart camera → Slow-mo + tools). User picked `B`.
3. **Visual:** Keep current dark green mesh + gold palette. Borrow Витя-style content treatment (bold typography, pre-headlines, phone-frame mockups, social proof).
4. **Hero medium:** Animated SwiftUI mockups (phone-frame with stylized product UI), not real video.
5. **Trial:** Weekly with 3-day free trial — `golfswing.weekly` at $4.99/wk.
6. **Paywall implementation:** `RevenueCatUI.PaywallView` (RC dashboard manages design), not custom Swift UI.

## Onboarding screens

**Screen 1 — KILLER (AI sync at impact)**
- Pre-headline: `5,000+ GOLFERS · ⭐ 4.9` *(replace with honest copy: `BUILT FOR SERIOUS GOLFERS`)*
- Headline (3 lines, 34pt heavy): `Your swing\nvs a pro's.\nAuto-synced.`
- Subtitle: `AI lines you up frame by frame at the moment of impact.`
- Hero: phone-frame mockup, two side-by-side video tiles, gold "IMPACT" line pulsing between them.
- CTA: `Continue`

**Screen 2 — Smart Camera**
- Pre-headline: `ZERO-TAP CAPTURE`
- Headline: `Just point.\nIt knows when\nyou swing.`
- Subtitle: `Detects, trims, and saves every swing automatically.`
- Hero: phone-frame mockup, viewfinder with golf-figure silhouette, gold detection bracket pulsing scale 0.95↔1.05.
- CTA: `Continue`

**Screen 3 — Slow-mo + Tools**
- Pre-headline: `FRAME BY FRAME`
- Headline: `Spot the fix.\nSend it to\nyour coach.`
- Subtitle: `8× slow-mo, drawing tools, HD export.`
- Hero: phone-frame mockup, stylized timeline + gold bezier-curve drawn via `trim` over 1.5s.
- CTA: `Get Started`

## Paywall

Replace custom `AppPaywallView` body with `RevenueCatUI.PaywallView`. Keep signature `(source: PaywallSource, onDismiss: () -> Void)` so 5 callers don't change.

`PaywallView` handles:
- Plan layout (sticky bottom is RC's responsibility via Paywall Editor)
- Weekly default with 3-day trial display
- Purchase / restore / close

`AppPaywallView` body:

```swift
PaywallView(displayCloseButton: true)
    .onPurchaseCompleted { _ in
        Task { await PurchaseService.shared.refreshStatus(); onDismiss() }
    }
    .onRestoreCompleted { info in
        if info.entitlements[PurchaseService.entitlementID]?.isActive == true {
            Task { await PurchaseService.shared.refreshStatus(); onDismiss() }
        }
    }
    .onRequestedDismissal { onDismiss() }
```

## File changes

**Delete:**
- `Views/Paywall/PaywallFeatureRow.swift`
- `Views/Paywall/SubscriptionOptionView.swift`

**Replace body:**
- `Views/Paywall/AppPaywallView.swift` (signature unchanged)

**New (onboarding hero mockups):**
- `Views/Onboarding/HeroMockup/PhoneFrameView.swift`
- `Views/Onboarding/HeroMockup/KillerSyncMockup.swift`
- `Views/Onboarding/HeroMockup/SmartCameraMockup.swift`
- `Views/Onboarding/HeroMockup/SlowMoToolsMockup.swift`

**Modify:**
- `Views/Onboarding/OnboardingFeature.swift` — model: `preHeadline`, `headlineLines: [String]`, `subtitle`, `heroBuilder: () -> AnyView`
- `Views/Onboarding/OnboardingPageView.swift` — layout for new model (no SF symbol; pre-headline label; 3-line headline; hero from builder)
- `Views/Onboarding/OnboardingView.swift` — skip dimmer (`opacity 0.3`), appears after 1s

**Unchanged:** `PaywallSource.swift`, `PurchaseService.swift`, `OnboardingService.swift`, `golf_sync_swingApp.swift`, all 5 paywall callers.

## RevenueCat & ASC (already done)

- ASC: `golfswing.weekly` $4.99/wk, 3-day free trial in 175 countries.
- RC: `$rc_weekly` package with `golfswing.weekly`; attached to "Golf Swing Sync Premium" entitlement; `$rc_monthly` cleaned of weekly mismapping.
- Code: `AppPaywallView.preferredDefault` returns `.weekly` (now moot since RC `PaywallView` handles default selection per its own dashboard config).

## Manual user tasks (after deploy)

1. **Design paywall in RevenueCat dashboard** (`app.revenuecat.com` → Offerings → default → Add Paywall). Without this, RC shows a default template.
2. **Upload Review Screenshot to ASC** (`appstoreconnect.apple.com` → app → Subscriptions → Weekly → Review Information → Choose File). Required to clear "Missing Metadata" before App Store submission.
3. **Sandbox-test** the trial flow end-to-end on a real device with sandbox account.

## Out of scope

- Goal-capture screen (architecture B, not B+ — user explicitly chose pure B)
- Real video recording (using SwiftUI animations instead)
- Localization beyond English (matches current state)
- A/B testing variants (single variant)
