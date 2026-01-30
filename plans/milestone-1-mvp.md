# Milestone 1: MVP - Video Player & Basic Comparison

**Goal**: Side-by-side video playback with manual sync

**Status**: Not Started

---

## Tasks

### 1.1 Project Setup
- [ ] Create folder structure (Models, Views, ViewModels, Services)
- [ ] Add RevenueCat SDK via SPM
- [ ] Configure app entitlements (Photo Library access)
- [ ] Set up SwiftData container

### 1.2 Video Import
- [ ] Create `VideoPickerView` using PHPickerViewController
- [ ] Create `SwingVideo` SwiftData model
- [ ] Generate and cache thumbnails
- [ ] Handle video copy to app sandbox
- [ ] Create `VideoLibraryView` to show imported videos

### 1.3 Single Video Player
- [ ] Create `VideoPlayerView` with AVPlayer
- [ ] Add play/pause button
- [ ] Add timeline scrubber (seek bar)
- [ ] Add slow-motion controls (0.25x, 0.5x, 1x)
- [ ] Add frame-by-frame stepping (+/- buttons)
- [ ] Handle video orientation correctly

### 1.4 Side-by-Side Comparison
- [ ] Create `ComparisonView` with two video players
- [ ] Sync play/pause across both videos
- [ ] Add manual sync adjustment (drag gesture to offset)
- [ ] Show sync offset value
- [ ] Add swap left/right button
- [ ] Create `ComparisonSession` SwiftData model

### 1.5 Basic Export
- [ ] Create `VideoExporter` service
- [ ] Composite two videos side-by-side using AVMutableComposition
- [ ] Add watermark overlay (for free tier)
- [ ] Save to Photos library
- [ ] Show export progress indicator
- [ ] Share sheet integration

### 1.6 Home Screen
- [ ] Create `HomeView` with options:
  - Import new video
  - View video library
  - Start comparison
- [ ] Recent comparisons list
- [ ] Empty state for new users

---

## Technical Notes

### Video Player Architecture
```
VideoPlayerView
├── AVPlayer (wrapped in VideoPlayerViewModel)
├── TimelineView (scrubber)
├── PlaybackControlsView (play, speed, frame step)
└── Overlay for annotations (future)
```

### Export Pipeline
```
Video 1 + Video 2
    ↓
AVMutableComposition (side-by-side layout)
    ↓
AVVideoComposition (apply transforms)
    ↓
AVAssetExportSession
    ↓
Output to temp file → Save to Photos
```

---

## Definition of Done
- [ ] User can import video from Photos
- [ ] User can play single video with slow-mo and scrubbing
- [ ] User can view two videos side-by-side
- [ ] User can manually adjust sync offset
- [ ] User can export comparison video
- [ ] All videos persist across app restarts
