# Milestone 4: Monetization & Polish

**Goal**: Launch-ready with paywall

**Status**: Not Started

**Depends on**: Milestone 3

---

## Tasks

### 4.1 RevenueCat Setup
- [ ] Create RevenueCat account and app
- [ ] Configure products in App Store Connect:
  - `weekly_premium` - Auto-renewable weekly
  - `lifetime_premium` - Non-consumable lifetime
- [ ] Add products to RevenueCat dashboard
- [ ] Create "premium" entitlement
- [ ] Initialize RevenueCat SDK in app

### 4.2 Purchase Service
- [ ] Create `PurchaseService` singleton
- [ ] Check entitlement status on app launch
- [ ] Fetch available packages
- [ ] Handle purchase flow
- [ ] Handle restore purchases
- [ ] Listen for entitlement changes
- [ ] Expose `isPremium` published property

### 4.3 Onboarding Flow
- [ ] Create `OnboardingView` (3-4 pages)
- [ ] Page 1: Welcome + value prop ("Sync your swings instantly")
- [ ] Page 2: Demo auto-sync feature (animation/video)
- [ ] Page 3: Show phase detection benefit
- [ ] Page 4: Get started CTA
- [ ] Store `hasSeenOnboarding` in UserDefaults
- [ ] Show only on first launch

### 4.4 Paywall View
- [ ] Create `PaywallView` or use RevenueCat Paywalls
- [ ] Animated hero image/video at top
- [ ] Feature list with icons:
  - Unlimited swing analysis
  - Auto-sync at impact
  - No watermark on exports
  - All drawing tools
- [ ] Weekly option with price
- [ ] Lifetime option with price (show savings)
- [ ] "Restore Purchases" button
- [ ] Terms & Privacy links
- [ ] Close button (X)

### 4.5 Free Tier Limits
- [ ] Track swing count in UserDefaults
- [ ] After 1st swing: Show rate app prompt (SKStoreReviewController)
- [ ] After 2nd swing: Show paywall
- [ ] Free comparison: Allow side-by-side but sequential playback only
- [ ] Show lock icon on sync button for free users
- [ ] Watermark on exports for free users

### 4.6 Premium Gating
- [ ] Gate synced playback behind premium
- [ ] Gate unlimited swings behind premium
- [ ] Gate watermark-free export behind premium
- [ ] Show upgrade prompt when hitting limits
- [ ] Unlock all features when premium active

### 4.7 Analytics
- [ ] Choose analytics provider (TelemetryDeck recommended)
- [ ] Track key events:
  - `onboarding_completed`
  - `video_imported`
  - `video_recorded`
  - `swing_analyzed`
  - `comparison_created`
  - `paywall_shown`
  - `purchase_started`
  - `purchase_completed`
  - `video_exported`
- [ ] Track conversion funnel

### 4.8 App Store Prep
- [ ] App icon (1024x1024)
- [ ] Screenshots for App Store (6.7", 6.5", 5.5")
- [ ] App preview video (optional but recommended)
- [ ] App description and keywords
- [ ] Privacy policy URL
- [ ] Terms of service URL
- [ ] Set up TestFlight for beta testing

---

## Technical Notes

### RevenueCat Integration
```swift
// AppDelegate or App init
Purchases.configure(withAPIKey: "your_api_key")

// Check premium status
Purchases.shared.getCustomerInfo { info, error in
    let isPremium = info?.entitlements["premium"]?.isActive == true
}

// Show paywall
let offerings = try await Purchases.shared.offerings()
if let package = offerings.current?.availablePackages.first {
    let result = try await Purchases.shared.purchase(package: package)
}
```

### Free Tier State Machine
```
New User
    ↓
[Import 1st video] → Analyze → Show "Rate App"
    ↓
[Import 2nd video] → Show Paywall
    ↓
[Skip] → Limited Mode (sequential only, watermark)
    OR
[Subscribe] → Full Premium
```

### Paywall Best Practices (Adam Lyttle)
- Full-screen presentation
- Animated hero draws attention
- Weekly shows lower commitment
- Lifetime shows value ("Save 80%")
- Features use benefits, not features
- Always have restore option

---

## Definition of Done
- [ ] RevenueCat configured with products
- [ ] Onboarding shows on first launch only
- [ ] Paywall appears after 2nd swing
- [ ] Rate app prompt after 1st swing
- [ ] Free users get sequential playback only
- [ ] Free exports have watermark
- [ ] Premium unlocks all features
- [ ] Restore purchases works
- [ ] Analytics tracking key events
- [ ] App Store assets ready
