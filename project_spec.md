# Project Spec: Golf Sync Swing

> **Definition**: What you want to build and how you want to build it.
>
> This document combines Product Requirements (PRD) and Engineering Design (EDD) into a single source of truth.

---

## Part 1: Product Requirements

### 1.1 Overview

**Project Name**: Golf Sync Swing

**One-liner**: Automatically detect golf swing phases and sync two videos at ball impact for side-by-side comparison.

**Problem Statement**: Golfers want to compare their swings to pros or their past selves, but manually finding the same moment in two videos is tedious. Existing apps require frame-by-frame scrubbing to align swings. Golf Sync Swing uses computer vision to automatically detect ball impact and sync videos instantly.

---

### 1.2 Target Users

**Primary Users**: Amateur golfers who want to analyze and improve their swing

**User Personas**:
| Persona | Description | Pain Points |
|---------|-------------|-------------|
| Weekend Golfer | Plays 1-2x/month, wants to fix slice | Can't see what they're doing wrong without slow-mo comparison to a good swing |
| Serious Amateur | Takes lessons, practices weekly | Spends too much time manually syncing videos to compare with coach's examples |
| Golf Coach | Teaches students, sends video feedback | Needs quick way to create comparison videos for students |

---

### 1.3 Goals & Success Metrics

**Project Goals**:
1. Automatically detect swing phases (address, backswing, downswing, impact, follow-through) with >90% accuracy
2. Auto-sync two videos at ball impact with <3 frame error
3. Convert free users to paid with compelling paywall flow

**Success Metrics**:
| Metric | Target | How to Measure |
|--------|--------|----------------|
| Trial start rate | >40% | Users who start free trial / users who see paywall |
| Trial conversion | >15% | Trials that convert to paid subscription |
| Sync accuracy | <3 frames | Manual review of auto-synced videos |
| App Store rating | >4.5 stars | App Store Connect |

---

### 1.4 Functional Requirements

#### Core Features

**Feature 1: Video Import & Recording**
- [ ] Import videos from Photos library with PHPickerViewController
- [ ] Import videos from Files app
- [ ] Built-in camera recording with countdown timer (3/5/10 sec options)
- [ ] Support for slow-motion videos (120/240 FPS)
- [ ] Auto-save recordings to app library

**Feature 2: Single Video Analysis**
- [ ] Auto-detect swing phases: address → backswing → top → downswing → impact → follow-through
- [ ] Display phase markers on timeline scrubber
- [ ] Tap phase marker to jump to that moment
- [ ] Slow-motion playback (0.25x, 0.5x, 1x speeds)
- [ ] Frame-by-frame stepping with gesture or buttons

**Feature 3: Video Comparison (Side-by-Side)**
- [ ] Select two videos for comparison
- [ ] Auto-sync at ball impact (detect impact frame in both, align them)
- [ ] Manual sync adjustment: drag to offset videos
- [ ] **Free mode**: Sequential playback (video 1 plays, then video 2)
- [ ] **Premium mode**: Synchronized playback (both play together, aligned at impact)
- [ ] Swap left/right video positions
- [ ] Independent zoom/pan per video with pinch gestures

**Feature 4: Drawing & Annotation**
- [ ] Draw lines, circles, angles on frozen frame
- [ ] Color picker for annotations
- [ ] Undo/redo drawing actions
- [ ] Clear all annotations
- [ ] Annotations persist when scrubbing (anchored to frame)

**Feature 5: Export**
- [ ] Export single video with phase markers overlay
- [ ] Export comparison video (side-by-side layout)
- [ ] Export options: with/without watermark (premium = no watermark)
- [ ] Share directly to social media, Messages, email
- [ ] Save to Photos library

**Feature 6: Onboarding & Paywall**
- [ ] Onboarding: 3-4 screens showing value (auto-sync demo, phase detection, comparison)
- [ ] Free tier: 1 swing analysis free
- [ ] After 1st swing: Show "Rate App" prompt
- [ ] After 2nd swing: Hit paywall limit
- [ ] Free comparison: Side-by-side with sequential (non-synced) playback
- [ ] Premium: Synced playback, unlimited swings, no watermark on export
- [ ] Subscription options: Weekly + Lifetime (no annual to simplify)

---

### 1.5 User Flows

**Flow 1: First-Time User (Single Video)**
```
Open App → Onboarding (3 screens) → Import/Record Video →
Auto-detect phases → View analysis with markers →
"Rate App" prompt → Done
```

**Flow 2: Second Swing (Paywall)**
```
Open App → Import 2nd video → "Upgrade to Premium" paywall →
[Subscribe] → Full access OR [Skip] → Limited features
```

**Flow 3: Comparison (Premium)**
```
Select Video 1 → Select Video 2 → Auto-sync at impact →
Adjust if needed → Play synchronized → Draw annotations →
Export comparison video
```

**Flow 4: Comparison (Free)**
```
Select Video 1 → Select Video 2 → Videos shown side-by-side →
Play sequentially (not synced) → Paywall prompt for sync feature
```

---

### 1.6 Non-Functional Requirements

- **Performance**: Phase detection < 5 seconds for 10-second video
- **Video Support**: MP4, MOV, up to 4K resolution, 30-240 FPS
- **Offline**: All features work offline (no server dependency)
- **Storage**: Videos stored locally, user controls deletion
- **Device Support**: iPhone only (no iPad initially), iOS 17+

---

### 1.7 Out of Scope

- Cloud storage / sync across devices
- Social features / sharing within app
- Lesson booking / coach marketplace
- Android version
- Apple Watch companion
- Pro swing library (future feature)

---

## Part 2: Engineering Design

### 2.1 Tech Stack

| Layer | Technology | Rationale |
|-------|------------|-----------|
| UI | SwiftUI | Modern, declarative, fast iteration |
| Data | SwiftData | Native persistence, iCloud-ready for future |
| Video | AVFoundation | Full control over playback, frame access |
| Detection | Vision + Core ML | On-device pose estimation, custom model for phase detection |
| Camera | AVCaptureSession | Custom recording UI with countdown |
| Purchases | RevenueCat | Paywall UI, analytics, A/B testing, easier subscription management |
| Analytics | TelemetryDeck or Firebase | Privacy-focused or industry standard |

---

### 2.2 System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      SwiftUI Views                          │
│  HomeView │ VideoPlayerView │ ComparisonView │ PaywallView  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      ViewModels                             │
│  VideoPlayerVM │ ComparisonVM │ AnalysisVM │ PurchaseVM     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       Services                              │
│  SwingDetector │ VideoSyncEngine │ VideoExporter │          │
│  PurchaseService │ CameraService │ AnalyticsService         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Data Layer                             │
│  SwiftData Models │ AVFoundation │ Vision │ RevenueCat      │
└─────────────────────────────────────────────────────────────┘
```

---

### 2.3 Data Models

**SwingVideo**
```swift
@Model
class SwingVideo {
    var id: UUID
    var localURL: URL
    var createdAt: Date
    var duration: TimeInterval
    var fps: Double
    var phases: [SwingPhase]  // Detected phases with timestamps
    var thumbnailData: Data?
}
```

**SwingPhase**
```swift
struct SwingPhase: Codable {
    var type: PhaseType  // address, backswing, top, downswing, impact, followThrough
    var timestamp: TimeInterval  // Seconds from video start
    var confidence: Float  // 0-1 detection confidence
}

enum PhaseType: String, Codable {
    case address, backswing, top, downswing, impact, followThrough
}
```

**ComparisonSession**
```swift
@Model
class ComparisonSession {
    var id: UUID
    var video1: SwingVideo
    var video2: SwingVideo
    var syncOffset: TimeInterval  // Seconds to offset video2 relative to video1
    var createdAt: Date
    var annotations: [Annotation]
}
```

**Annotation**
```swift
struct Annotation: Codable {
    var id: UUID
    var type: AnnotationType  // line, circle, angle
    var points: [CGPoint]
    var color: String  // Hex color
    var frameTimestamp: TimeInterval  // Which frame it's anchored to
    var videoIndex: Int  // 0 = left video, 1 = right video
}
```

---

### 2.4 API Design

N/A - Fully offline app, no backend API.

**StoreKit Products**:
| Product ID | Type | Description |
|------------|------|-------------|
| `weekly_premium` | Auto-renewable | Weekly subscription |
| `lifetime_premium` | Non-consumable | One-time lifetime purchase |

---

### 2.5 Security Considerations

- **Video Privacy**: All videos stored locally, never uploaded
- **No Account Required**: No user data collected beyond anonymous analytics
- **RevenueCat**: Handles payment security, receipt validation server-side
- **Entitlements**: RevenueCat manages purchase state, syncs across reinstalls

---

## Part 3: Milestones

### Milestone 1: MVP - Video Player & Basic Comparison
**Goal**: Side-by-side video playback with manual sync

**Deliverables**:
- [ ] Video import from Photos
- [ ] Single video player with scrubbing and slow-mo
- [ ] Side-by-side comparison view
- [ ] Manual sync (drag to adjust offset)
- [ ] Basic export (side-by-side video)

---

### Milestone 2: Auto-Detection & Sync
**Goal**: Automatic swing phase detection and impact sync

**Deliverables**:
- [ ] Vision-based pose estimation integration
- [ ] Phase detection algorithm (address → impact → follow-through)
- [ ] Auto-sync at impact frame
- [ ] Phase markers on timeline

---

### Milestone 3: Recording & Annotations
**Goal**: Complete capture-to-analysis workflow

**Deliverables**:
- [ ] Built-in camera with countdown timer
- [ ] Drawing tools (lines, circles, angles)
- [ ] Annotation persistence per frame

---

### Milestone 4: Monetization & Polish
**Goal**: Launch-ready with paywall

**Deliverables**:
- [ ] Onboarding flow (3-4 screens)
- [ ] Paywall with Weekly + Lifetime options
- [ ] Free tier limits (1 swing, sequential comparison)
- [ ] Rate app prompt after 1st swing
- [ ] Analytics integration
- [ ] App Store assets and screenshots

---

## Part 4: Risks & Open Questions

| Risk | Impact | Mitigation |
|------|--------|------------|
| Phase detection accuracy < 90% | High | Start with impact-only detection, add other phases incrementally |
| Slow processing on older devices | Med | Show progress indicator, optimize model, test on iPhone 11 |
| Users don't understand auto-sync value | Med | Demo in onboarding, show "before/after" of manual vs auto |
| App Store rejection for paywall | Low | Follow Apple guidelines, ensure free tier has real value |

**Open Questions**:
- [ ] Which ML model approach? Vision body pose vs custom Core ML model?
- [ ] Should free tier allow export with watermark or no export at all?
- [ ] Pro swing library - curate ourselves or license from somewhere?
- [ ] Do we need a "swing library" to save past swings, or just recent videos?
