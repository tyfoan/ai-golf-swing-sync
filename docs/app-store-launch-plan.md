# Golf Sync Swing — Complete App Store Launch Plan

> **Purpose**: Step-by-step guide to launch Golf Sync Swing on the App Store. Every field, every value, copy-paste ready.
>
> **Last Updated**: 2026-02-13

---

## Table of Contents

1. [Part 1: App Store Connect — Create New App](#part-1-app-store-connect--create-new-app)
2. [Part 2: App Store Connect — In-App Purchases](#part-2-app-store-connect--in-app-purchases)
3. [Part 3: RevenueCat Dashboard Setup](#part-3-revenuecat-dashboard-setup)
4. [Part 4: Xcode Integration](#part-4-xcode-integration)
5. [Part 5: Testing Checklist](#part-5-testing-checklist)
6. [Part 6: Screenshot Plan (appscreens.com)](#part-6-screenshot-plan-appscreenscom)
7. [Submission Checklist](#submission-checklist)

---

# Part 1: App Store Connect — Create New App

## Prerequisites

- [ ] Apple Developer Program membership ($99/year) — active
- [ ] Sign **Paid Applications Agreement**: App Store Connect > Business > Agreements, Tax, and Banking
- [ ] Complete **Tax Forms**: Business > Tax tab
- [ ] Link **Bank Account**: Business > Banking tab (status must show "Clear")
- [ ] Register Bundle ID: Certificates, Identifiers & Profiles > Identifiers > + > App IDs

---

## Step 1: Create New App Dialog

Navigate: **App Store Connect > My Apps > "+" > New App**

| Field | Value | Notes |
|-------|-------|-------|
| **Platforms** | `iOS` (check iPhone only) | Do NOT check macOS, tvOS |
| **Name** | `Golf Sync Swing` | 15 chars (max 30). App Store display name. |
| **Primary Language** | `English (U.S.)` | Default for all metadata |
| **Bundle ID** | `com.COMPANY.golfsyncswing` | Must match Xcode. CANNOT change after first build upload. |
| **SKU** | `GOLFSYNCSWING001` | Internal-only ID, never shown to users. CANNOT change. |
| **User Access** | `Full Access` | Solo/small team = Full Access |

---

## Step 2: App Information Page

| Field | Required | Value |
|-------|----------|-------|
| **Subtitle** | Optional (30 chars) | `Compare & Sync Golf Swings` |
| **Primary Category** | Required | `Sports` |
| **Secondary Category** | Optional | `Photo & Video` |
| **Content Rights** | Required | `This app does not contain, show, or access third-party content` |

### Age Rating Questionnaire

Click "Edit" next to Age Rating. Answer every question:

| Content Descriptor | Answer |
|---|---|
| Cartoon or Fantasy Violence | **None** |
| Realistic Violence | **None** |
| Prolonged Graphic or Sadistic Realistic Violence | **None** |
| Profanity or Crude Humor | **None** |
| Mature or Suggestive Themes | **None** |
| Horror/Fear Themes | **None** |
| Medical or Treatment Information | **None** |
| Sexual Content or Nudity | **None** |
| Graphic Sexual Content and Nudity | **None** |
| Alcohol, Tobacco, or Drug Use or References | **None** |
| Gambling | **None** |
| Simulated Gambling | **None** |
| Contests | **None** |
| Unrestricted Web Access | **No** |
| User-Generated Content | **No** |
| Messaging and Chat | **No** |
| Loot Boxes | **No** |
| Guns or Other Weapons | **None** |

**Result**: **4+** rating (no objectionable content)

---

## Step 3: Pricing and Availability

| Field | Value | Notes |
|-------|-------|-------|
| **Price** | `Free` | Revenue from in-app purchases |
| **Availability** | `All territories` (175 countries) | No reason to restrict |
| **Pre-Order** | `No` | Skip for initial launch |

---

## Step 4: App Privacy

### Privacy Policy URL

| Field | Value |
|-------|-------|
| **Privacy Policy URL** | `https://yoursite.com/golfsyncswing/privacy` |

**Quick way to create one**: Use [app-privacy-policy-generator.firebaseapp.com](https://app-privacy-policy-generator.firebaseapp.com/) — select Camera, Microphone, Photo Library. Host on GitHub Pages.

### Data Collection Questionnaire

**"Do you or your third-party partners collect data from this app?"**

**Initial answer (before RevenueCat)**: `No, we do not collect data from this app`

**After adding RevenueCat, update to declare**:
- Purchase History — Linked to User, Used for App Functionality
- Product Interaction — Not Linked to User

---

## Step 5: Version Information (Prepare for Submission)

### Screenshots

**Required**: 6.9" iPhone screenshots only (1290 x 2796 px). Apple auto-scales for smaller devices.

Format: JPEG or PNG, RGB, no transparency, max 10MB each. Min 1, max 10. **Recommend 6-8.**

*(See Part 6 for the complete screenshot plan)*

### Promotional Text (170 chars max)

```
Auto-detect swing phases and sync two golf videos at ball impact. Compare your swing side-by-side in slow motion. Improve your game with smart video analysis.
```
*(160 chars — can be updated ANY time without a new version)*

### Description (4000 chars max)

```
Automatically detect your golf swing and sync two videos at the exact moment of ball impact — no manual alignment needed.

Golf Sync Swing uses advanced on-device machine learning to analyze your swing phases (backswing, downswing, follow-through) and pinpoint the moment of contact. Record your swing or import any video, and the app does the rest.

SMART SWING DETECTION
- Automatic detection of swing start, ball impact, and follow-through
- Works with any golf swing video — recorded in-app or imported from your library
- Powered by Core ML and the Vision framework, running entirely on your device

SIDE-BY-SIDE COMPARISON
- Compare two swings in perfect sync, aligned at the point of impact
- Four comparison modes: Side-by-Side, Synced Side-by-Side, Onion Skin, and Overlay
- Adjustable sync offset for fine-tuning alignment

SLOW MOTION PLAYBACK
- Frame-by-frame analysis at up to 240 FPS
- Slow motion controls to study every detail of your technique
- Loop playback through your swing for focused practice review

BUILT FOR YOUR PRIVACY
- Everything runs on your device — no cloud uploads, no accounts required
- Your videos and data never leave your phone
- No tracking, no analytics, no third-party data sharing

COMPARE WITH THE PROS
- Import professional swing videos to compare against your own
- Study what separates your technique from tour-level players
- Build a personal library of reference swings

Whether you are a weekend golfer looking to fix a slice or a competitive player refining your mechanics, Golf Sync Swing gives you the tools to see exactly what is happening in your swing — and what to change.

Download Golf Sync Swing and start improving today.

---
SUBSCRIPTION INFORMATION

Golf Sync Swing offers a free tier with basic side-by-side comparison. Premium features (Synced Playback, Onion Skin, Overlay modes) are available through:

- Weekly subscription
- Lifetime purchase (one-time payment)

Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period. You can manage and cancel your subscriptions by going to your account settings on the App Store after purchase.

Terms of Use: https://yoursite.com/terms
Privacy Policy: https://yoursite.com/privacy
```

*(~2,100 chars — well within 4,000 limit. Subscription disclosure at the end is REQUIRED by Apple.)*

### Keywords (100 chars max)

```
golf swing,analyzer,compare,slow motion,video,sync,impact,training,coach,practice
```
*(82 chars. Separate with commas, NO spaces after commas.)*

### URLs

| Field | Required | Value |
|-------|----------|-------|
| **Support URL** | Required | `https://yoursite.com/golfsyncswing/support` |
| **Marketing URL** | Optional | `https://yoursite.com/golfsyncswing` |

**Tip**: A simple GitHub Pages site with your support email satisfies the Support URL requirement.

### Build Upload

1. Xcode: **Product > Archive**
2. Organizer: **Distribute App > App Store Connect > Upload**
3. Wait 5-30 min for processing
4. Return to App Store Connect > Version page > Build section > Select the build

### App Review Information

| Field | Value |
|-------|-------|
| **Contact First Name** | *Your first name* |
| **Contact Last Name** | *Your last name* |
| **Contact Phone** | *Your phone with country code* |
| **Contact Email** | *Your email* |
| **Sign-in Required** | `No` |

**Review Notes** (copy-paste):
```
Golf Sync Swing is a video comparison tool for golf swings. No login or account is required.

To test the core functionality:
1. Grant camera and photo library permissions when prompted
2. Record a golf swing using the Record tab, or import a video from Photos
3. The app automatically detects swing phases (backswing, downswing, follow-through)
4. Select two videos and tap Compare to see synchronized side-by-side playback

The app uses on-device Core ML models for swing detection — no internet connection is required.

Note: For best results during testing, use a video of an actual golf swing. The ML model is trained specifically on golf swing motions.
```

### Version Release

| Field | Value | Notes |
|-------|-------|-------|
| **Version Release** | `Manually release this version` | You control when it goes live after approval |
| **Version** | `1.0` | Auto-populated from build |
| **Copyright** | `2026 Your Name or Company` | |

---

# Part 2: App Store Connect — In-App Purchases

## Step 1: Create Subscription Group

Navigate: **My Apps > [Golf Sync Swing] > Subscriptions** (under Monetization)

1. Click **+** (Create)
2. **Subscription Group Reference Name**: `Golf Sync Swing Premium`
3. Click **Create**
4. Add **App Store Localization**:
   - **Locale**: `English (U.S.)`
   - **Subscription Group Display Name**: `Golf Sync Swing Premium`
   - **Custom App Name**: *(leave blank)*

## Step 2: Create Weekly Subscription

Inside your subscription group, click **+**:

| Field | Value |
|-------|-------|
| **Reference Name** | `Weekly Premium` |
| **Product ID** | `weekly_premium` |
| **Subscription Duration** | `1 Week` |

**Set Pricing**:
- Starting Price country: `United States`
- Price: `$4.99`
- Click Next — Apple auto-generates prices for all 175 territories

**Add Localization**:
| Field | Value |
|-------|-------|
| **Locale** | `English (U.S.)` |
| **Display Name** | `Weekly Premium` |
| **Description** | `Unlock all premium features including synchronized playback, overlay comparison, and HD export.` |

**Free Trial (Introductory Offer)** — Recommended:
- **Type**: `Free Trial`
- **Duration**: `3 Days`
- **Availability**: `All Territories`

**Review Screenshot**: Upload a screenshot of the app showing premium features active.

**Review Notes**: `This subscription unlocks synchronized playback, onion skin comparison, overlay comparison, pose estimation, and HD export without watermark.`

## Step 3: Create Lifetime Purchase (Non-Consumable)

Navigate: **My Apps > [Golf Sync Swing] > In-App Purchases** (under Monetization)

1. Click **+** > Select **Non-Consumable**

| Field | Value |
|-------|-------|
| **Reference Name** | `Lifetime Premium` |
| **Product ID** | `lifetime_premium` |
| **Price** | `$29.99` (select tier, Apple generates all territory prices) |

**Add Localization**:
| Field | Value |
|-------|-------|
| **Locale** | `English (U.S.)` |
| **Display Name** | `Lifetime Premium` |
| **Description** | `One-time purchase. Unlock all premium features forever -- synchronized playback, all comparison modes, pose estimation, HD export, no watermark.` |

**Review Screenshot**: Upload a screenshot showing premium content.
**Family Sharing**: Consider enabling (non-consumables support it).

## Quick Reference: Products

| Product | ID | Type | Price |
|---------|-----|------|-------|
| Weekly | `weekly_premium` | Auto-Renewable | $4.99/week |
| Lifetime | `lifetime_premium` | Non-Consumable | $29.99 |

---

# Part 3: RevenueCat Dashboard Setup

## Step 1: Create Account

1. Go to **https://app.revenuecat.com/signup**
2. Sign up with email or GitHub
3. Free tier: up to $2,500/month MTR (more than enough to start)

## Step 2: Create Project

1. Click **+ New Project**
2. **Project Name**: `Golf Sync Swing`

## Step 3: Connect App Store (Two Keys Needed)

### Key 1: In-App Purchase Key

1. **App Store Connect > Users and Access > Integrations > In-App Purchase**
2. Click **Generate In-App Purchase Key**
3. **Name**: `RevenueCat IAP Key`
4. **Download the .p8 file** (one-time download — save securely!)
5. Note the **Key ID** and **Issuer ID**
6. In **RevenueCat**: App > Service Credentials > In-app purchase key configuration
7. Upload .p8, enter Issuer ID, Save

### Key 2: App Store Connect API Key

1. **App Store Connect > Users and Access > Integrations > App Store Connect API**
2. Click **Generate API Key**
3. **Name**: `RevenueCat ASC Key`
4. **Access**: `Admin`
5. **Download the .p8 file** (one-time!)
6. Note **Key ID**, **Issuer ID**
7. In **RevenueCat**: Project Settings > App Store Connect API Key Configuration
8. Upload .p8, enter Key ID, Issuer ID, Vendor Number
9. Save

### Legacy: App-Specific Shared Secret (Optional)

1. App Store Connect > My Apps > [Golf Sync Swing] > General > App Information
2. App-Specific Shared Secret > Manage > Generate
3. Copy to RevenueCat > App Settings > Shared Secret

## Step 4: Add App

1. In RevenueCat project: **+ New App**
2. **App Store**: `Apple App Store`
3. **App Name**: `Golf Sync Swing`
4. **Bundle ID**: `com.yourcompany.golf-sync-swing` (must match Xcode exactly)

## Step 5: Configure Products

1. **Product Catalog > Products > + New Product**
2. Product 1: App Store Product ID = `weekly_premium`
3. Product 2: App Store Product ID = `lifetime_premium`

*(If ASC API Key configured, use "Import Products" to auto-pull from App Store Connect)*

## Step 6: Create Entitlement

1. **Product Catalog > Entitlements > + New Entitlement**
2. **Identifier**: `premium`
3. **Description**: `Unlocks all premium features`
4. **Attach** both `weekly_premium` and `lifetime_premium` to this entitlement

## Step 7: Create Offering

1. **Product Catalog > Offerings > + New Offering**
2. **Identifier**: `default`
3. **Description**: `Default offering with weekly and lifetime options`
4. Check **Current Offering**
5. Add packages:
   - Package 1: Identifier = `$rc_weekly`, attach `weekly_premium`
   - Package 2: Identifier = `$rc_lifetime`, attach `lifetime_premium`

## Step 8: Get API Key

1. **Project Settings > API Keys**
2. Copy **Public App-Specific API Key** (starts with `appl_`)
3. This key goes in your app code — it's safe (public, read-only)

## Quick Reference: RevenueCat Identifiers

| Item | Identifier |
|------|-----------|
| Entitlement | `premium` |
| Offering | `default` |
| Weekly Package | `$rc_weekly` |
| Lifetime Package | `$rc_lifetime` |
| Public API Key | `appl_...` (from dashboard) |

---

# Part 4: Xcode Integration

## Step 1: Add RevenueCat SDK (SPM)

1. Xcode: **File > Add Package Dependencies...**
2. URL: `https://github.com/RevenueCat/purchases-ios-spm.git`
3. **Dependency Rule**: Up to Next Major Version (minimum `5.0.0`)
4. Select libraries: **RevenueCat** + **RevenueCatUI**

## Step 2: StoreKit Configuration File (Local Testing)

1. Xcode: **File > New > File... > StoreKit Configuration File**
2. Name: `GolfSyncSwingStore.storekit`
3. Do NOT sync with App Store Connect
4. Add subscription:
   - Group: `Golf Sync Swing Premium`
   - Reference Name: `Weekly Premium`
   - Product ID: `weekly_premium`
   - Price: `4.99`
   - Duration: `1 Week`
   - Introductory Offer: Free Trial, 3 Days
5. Add non-consumable:
   - Reference Name: `Lifetime Premium`
   - Product ID: `lifetime_premium`
   - Price: `29.99`
6. Enable: **Scheme > Edit Scheme > Run > Options > StoreKit Configuration** = `GolfSyncSwingStore.storekit`

## Step 3: Capabilities

1. Select project target > **Signing and Capabilities**
2. Click **+ Capability** > Add **In-App Purchase**

## Step 4: Code Integration

### Initialize (App entry point):

```swift
import RevenueCat
import RevenueCatUI

@main
struct GolfSyncSwingApp: App {
    init() {
        Purchases.logLevel = .debug  // Remove for production
        Purchases.configure(withAPIKey: "appl_YOUR_PUBLIC_API_KEY")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Check Entitlement:

```swift
func checkPremiumAccess() async -> Bool {
    do {
        let customerInfo = try await Purchases.shared.customerInfo()
        return customerInfo.entitlements["premium"]?.isActive == true
    } catch {
        return false
    }
}
```

### Present Paywall (simplest):

```swift
import RevenueCatUI

struct SomeView: View {
    @State private var showPaywall = false

    var body: some View {
        Button("Upgrade to Premium") {
            showPaywall = true
        }
        .presentPaywallIfNeeded(
            requiredEntitlementIdentifier: "premium"
        ) { customerInfo in
            // Purchase completed
        }
    }
}
```

---

# Part 5: Testing Checklist

## StoreKit Configuration Testing (Simulator)

- [ ] Set StoreKit config in scheme (Run > Options)
- [ ] Works on simulator — transactions are local only
- [ ] Manage test transactions: Xcode > Debug > StoreKit > Manage Transactions

## Sandbox Testing (Device)

1. App Store Connect: **Users and Access > Sandbox > Testers > +**
   - Email: unique (not existing Apple ID)
   - Territory: United States
2. On device: **Settings > App Store > Sandbox Account** > sign in
3. **IMPORTANT**: Set StoreKit Configuration to **None** in scheme for sandbox to reach RevenueCat
4. Sandbox renewals: 1 week = 3 minutes, auto-renews up to 6 times

## Pre-Submission Checklist

- [ ] Products show "Ready to Submit" in App Store Connect
- [ ] Review screenshots uploaded for each IAP product
- [ ] Localization complete
- [ ] RevenueCat: Entitlement "premium" has both products attached
- [ ] RevenueCat: Offering "default" has Weekly + Lifetime packages
- [ ] API key is PRODUCTION key (not sandbox)
- [ ] StoreKit Configuration set to None for production builds
- [ ] **Restore Purchases button exists** (App Review requirement)
- [ ] Terms of Service + Privacy Policy URLs set
- [ ] Subscription management instructions visible to users

---

# Part 6: Screenshot Plan (appscreens.com)

## Device Sizes Required

| Display Size | Dimensions (Portrait) | Required? |
|---|---|---|
| **6.9" iPhone** | 1290 x 2796 px | **YES — Mandatory** |
| 6.7" iPhone | 1284 x 2778 px | Auto-scaled from 6.9" |
| 6.5" iPhone | 1242 x 2688 px | Auto-scaled from 6.9" |
| All smaller | Various | Auto-scaled from 6.9" |

**You only need to upload 6.9" screenshots.** Apple scales the rest.

## Recommended: 7 Screenshots

### Screenshot 1 (HERO — Most Important)
**Screen**: Side-by-side synced comparison playing at impact
**Headline**: `Auto-Sync at Impact`
**Subtitle**: `AI aligns your swings at the exact moment of contact`
**Why**: This is the killer feature. First screenshot is what 90% of users see.

**Alternative headlines**:
- `Your Swings, Perfectly Synced`
- `AI-Powered Impact Sync`
- `Compare Swings Instantly`

### Screenshot 2
**Screen**: Recording view with pose skeleton overlay + positioning guide
**Headline**: `Smart Swing Recording`
**Subtitle**: `Real-time pose detection guides your setup`

**Alternative headlines**:
- `Record with AI Guidance`
- `Pose-Aware Recording`

### Screenshot 3
**Screen**: Swing detection results — timeline with phase markers
**Headline**: `Detect Every Phase`
**Subtitle**: `Backswing, downswing, follow-through — detected automatically`

**Alternative headlines**:
- `AI Swing Analysis`
- `Instant Phase Detection`

### Screenshot 4
**Screen**: Onion Skin comparison mode (premium)
**Headline**: `Overlay Your Swings`
**Subtitle**: `See exactly where your technique differs`

**Alternative headlines**:
- `Onion Skin Comparison`
- `Layer & Compare`

### Screenshot 5
**Screen**: Slow-motion playback with frame-by-frame controls
**Headline**: `Frame-by-Frame Detail`
**Subtitle**: `Slow motion up to 240 FPS`

**Alternative headlines**:
- `Every Frame Matters`
- `Slow-Mo Analysis`

### Screenshot 6
**Screen**: Video library / home screen with swing thumbnails
**Headline**: `Your Swing Library`
**Subtitle**: `All your swings organized and ready to compare`

**Alternative headlines**:
- `Build Your Collection`
- `Track Your Progress`

### Screenshot 7
**Screen**: Export comparison video preview
**Headline**: `Share & Export`
**Subtitle**: `Send comparison videos to your coach or friends`

**Alternative headlines**:
- `Export Side-by-Side`
- `Share Your Progress`

## Color Theme & Design Direction

| Element | Recommendation |
|---------|---------------|
| **Primary Color** | Deep green (#1B5E20 or #2E7D32) — golf course association |
| **Accent Color** | Bright green (#00C853) or gold (#FFD600) for CTAs |
| **Background** | Dark gradient (#0A1628 → #1B3A4B) — makes screenshots pop |
| **Text Color** | White headlines on dark background |
| **Font Style** | Bold sans-serif (SF Pro Display Bold, or similar) |

## appscreens.com Workflow

1. **Prepare assets**: Take raw screenshots from simulator/device (no status bar preferred)
2. **Go to appscreens.com** > Choose a template from Sports/Fitness category
3. **Upload screenshots** > Add text overlays (headlines + subtitles)
4. **Set device frame**: iPhone 16 Pro Max (or latest)
5. **Set background**: Dark gradient with green accents
6. **Export at 1290 x 2796** for 6.9" display
7. **Download all** and upload to App Store Connect

**What to prepare before using appscreens.com**:
- [ ] 7 raw app screenshots (from device or simulator)
- [ ] Headline + subtitle text for each (from the plan above)
- [ ] Color hex codes (#1B5E20, #00C853, #0A1628)
- [ ] App icon (for branding consistency)

---

# Submission Checklist

## App Store Connect

- [ ] App created (name, bundle ID, SKU)
- [ ] Subtitle filled in
- [ ] Categories: Sports + Photo & Video
- [ ] Age Rating: 4+ (all "None")
- [ ] Privacy Policy URL live
- [ ] App Privacy answered
- [ ] Price: Free
- [ ] Availability: All territories
- [ ] Screenshots uploaded (6.9" iPhone, 6-8 images)
- [ ] Promotional Text written
- [ ] Description written (with subscription disclosure)
- [ ] Keywords filled in
- [ ] Support URL live
- [ ] Build uploaded and selected
- [ ] Review contact info + notes filled
- [ ] Version Release: Manual

## In-App Purchases

- [ ] Subscription group created: "Golf Sync Swing Premium"
- [ ] Weekly subscription: `weekly_premium` at $4.99/week, 3-day free trial
- [ ] Lifetime purchase: `lifetime_premium` at $29.99
- [ ] Localizations added for both products
- [ ] Review screenshots uploaded for both products

## RevenueCat

- [ ] Project created
- [ ] App Store keys connected (IAP key + ASC API key)
- [ ] App added with correct bundle ID
- [ ] Products: `weekly_premium` + `lifetime_premium`
- [ ] Entitlement: `premium` with both products attached
- [ ] Offering: `default` with `$rc_weekly` + `$rc_lifetime` packages
- [ ] Production API key copied to app

## Xcode

- [ ] RevenueCat SDK added via SPM
- [ ] In-App Purchase capability added
- [ ] `Purchases.configure()` called in app init
- [ ] Entitlement check integrated with `FeatureAccess`
- [ ] Paywall view presented
- [ ] Restore Purchases button exists
- [ ] StoreKit config set to None for production
- [ ] Archive + upload to App Store Connect
