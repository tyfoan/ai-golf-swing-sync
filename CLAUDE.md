# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Golf Sync Swing is an iOS app for golf swing video comparison with automatic motion sync. The core feature is **automatic detection of swing phases** (start, ball impact, end) and **synchronized playback** of two videos aligned at the point of ball contact.

### Target Feature Set (Reference: Golf Swing Cam)
- Side-by-side video comparison with synchronized playback
- **Auto-sync at ball impact** - automatically detect and align swing phases
- Slow-motion playback (up to 120 FPS support)
- Drawing/annotation tools for swing analysis
- Video export with comparison layout
- Pro swing library for comparison

## Build Commands

```bash
# Build from command line
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run single test
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:golf-sync-swingTests/TestClassName/testMethodName test
```

## Technical Stack

- **iOS 26.1+** / Swift 5.0 / SwiftUI
- **SwiftData** for persistence
- **AVFoundation** for video playback and export
- **Vision framework** for swing detection (to be implemented)
- **Core ML** for motion analysis models (to be implemented)

## Architecture (Planned)

```
golf-sync-swing/
├── Models/
│   ├── SwingVideo.swift        # Video metadata + detected swing phases
│   ├── SwingPhase.swift        # Enum: setup, backswing, downswing, impact, follow-through
│   └── ComparisonSession.swift # Paired videos with sync offset
├── Services/
│   ├── SwingDetector.swift     # Vision/ML-based phase detection
│   ├── VideoSyncEngine.swift   # Calculate sync offset from impact frames
│   └── VideoExporter.swift     # Composite video export
├── Views/
│   ├── VideoPlayerView.swift   # Single video with scrubbing
│   ├── ComparisonView.swift    # Side-by-side synced playback
│   └── TimelineView.swift      # Visual swing phase markers
└── ViewModels/
    └── ComparisonViewModel.swift
```

## Swing Detection Algorithm (Core Challenge)

The key technical challenge is detecting three critical frames:
1. **Swing Start** - First significant club movement from address position
2. **Ball Impact** - Frame where club contacts ball (primary sync point)
3. **Swing End** - Follow-through completion

Approaches to consider:
- **Vision framework pose estimation** - Track body keypoints, detect characteristic pose sequences
- **Optical flow analysis** - Detect rapid motion changes at impact
- **Audio detection** - Ball impact produces distinctive sound spike
- **Core ML custom model** - Train on labeled swing datasets

## Reference Implementation

The existing `video-comparer` project at `~/Desktop/test/video-comparer` has reusable components:
- `VideoPlayerView.swift` - AVPlayer wrapper with playback controls
- `VideoExportService.swift` - Side-by-side video composition
- `VideoTrimmer.swift` - Frame-accurate trimming UI
- `DrawingShapes.swift` - Annotation overlay system

---

## Code Principles

### Sandi Metz Rules (Adapted for Swift)
- **Classes ≤ 200 lines** - If larger, split into focused components
- **Methods ≤ 15 lines** - Extract logic into well-named helper methods
- **≤ 5 parameters** - Use configuration objects for complex initialization
- **Single Responsibility** - Each class/struct does ONE thing well
- **Dependency Injection** - Pass dependencies in, don't create them inside

### Atomic Architecture
- **One file = One purpose** - No multi-responsibility files
- **Views are dumb** - Display only, no business logic
- **Extract early** - If logic could be reused, make it a Service immediately
- **Small, composable views** - Build complex UI from simple building blocks

### Service Extraction Rules
When you detect logic, ask: "Could this be tested independently?"
- YES → Extract to `Services/` folder
- Services must be **stateless** or use **injected state**
- Services must be **testable in isolation** (no UI dependencies)
- Services must be **reusable** across views

```
Services/
├── SwingDetector.swift      # Pure logic, takes video → returns phases
├── VideoSyncEngine.swift    # Pure logic, takes phases → returns offset
├── VideoExporter.swift      # Takes config → produces file
├── PurchaseService.swift    # Handles RevenueCat, injected into views
└── AnalyticsService.swift   # Fire-and-forget tracking
```

---

## Monetization Principles (Adam Lyttle)

### Onboarding → Paywall Flow
1. **Congratulate** - "Great choice downloading [App]!" with social proof
2. **Show benefits** - Not features, but what user gains
3. **Demo premium** - Show advanced functionality they'll unlock
4. **Paywall** - Reinforce premium features, present subscription options

### Paywall Best Practices
- **Weekly subscriptions convert better** - Lower perceived commitment
- **Full-screen presentation** - No distractions, focused conversion
- **Animated hero image** - Draws attention, feels premium
- **Feature list with icons** - Quick scannable benefits
- **Two options max** - Weekly + Annual (annual shows savings)

### Revenue Architecture
```
App/
├── Onboarding/
│   ├── OnboardingView.swift       # Reusable across all apps
│   ├── OnboardingFeature.swift    # Model: title, description, icon
│   └── OnboardingPageView.swift   # Single page component
├── Paywall/
│   ├── PaywallView.swift          # Full-screen purchase UI (or use RevenueCat Paywalls)
│   ├── PurchaseFeatureView.swift  # Single feature row
│   └── PurchaseModel.swift        # RevenueCat entitlements, state management
└── Services/
    └── PurchaseService.swift      # Actual purchase/restore logic
```

### Key Metrics to Optimize
- **Trial start rate** - % of users who start free trial
- **Trial conversion** - % of trials that convert to paid
- **Time to paywall** - Show value first, but don't wait too long

### Reusable Code Philosophy
Build onboarding and paywall **once**, reuse across all apps. Parameterize:
- App name, colors, icons
- Feature list
- Subscription products
- Analytics events

---

## Documentation

- [Project Spec](project_spec.md) - Full requirements, API specs, tech details
- [Architecture](docs/architecture.md) - System design and data flow
- [Changelog](docs/changelog.md) - Version history
- [Project Status](docs/project_status.md) - Current progress

Update files in the docs folder after major milestones and major additions to the project.

---

## Implementation Plans

Detailed task breakdowns live in `plans/`:

| Plan | Status | Description |
|------|--------|-------------|
| [Milestone 1: MVP](plans/milestone-1-mvp.md) | ✅ Complete | Video player, import, side-by-side, manual sync, export |
| [Milestone 2: Auto-Detection](plans/milestone-2-auto-detection.md) | Not Started | Vision pose detection, phase markers, auto-sync at impact |
| [Milestone 3: Recording & Annotations](plans/milestone-3-recording-annotations.md) | Not Started | Camera with countdown, drawing tools |
| [Milestone 4: Monetization](plans/milestone-4-monetization.md) | Not Started | RevenueCat, onboarding, paywall, analytics |

### Working with Plans

1. **Before starting work**: Read the relevant milestone plan
2. **Check off tasks** as you complete them (mark `[x]`)
3. **Update plan** if approach changes or new tasks discovered
4. **Follow dependencies**: Milestones build on each other (1 → 2 → 3 → 4)

### Current Focus

**Milestone 1 is complete.** Next up is **Milestone 2: Auto-Detection**:
1. Vision framework pose estimation
2. Swing phase detection algorithm
3. Auto-sync at ball impact
