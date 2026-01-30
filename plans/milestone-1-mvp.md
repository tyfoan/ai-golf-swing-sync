# Milestone 1: MVP - Video Player & Basic Comparison

**Goal**: Side-by-side video playback with manual sync

**Status**: Complete ✅

---

## Tasks

### 1.1 Project Setup
- [x] Create folder structure (Models, Views, ViewModels, Services)
- [ ] Add RevenueCat SDK via SPM (deferred to Milestone 4)
- [x] Configure app entitlements (Photo Library access)
- [x] Set up SwiftData container

### 1.2 Video Import
- [x] Create `VideoPickerView` using PHPickerViewController
- [x] Create `SwingVideo` SwiftData model
- [x] Generate and cache thumbnails
- [x] Handle video copy to app sandbox
- [x] Create `VideoLibraryView` to show imported videos

### 1.3 Single Video Player
- [x] Create `VideoPlayerView` with AVPlayer
- [x] Add play/pause button
- [x] Add timeline scrubber (seek bar)
- [x] Add slow-motion controls (0.25x, 0.5x, 1x)
- [x] Add frame-by-frame stepping (+/- buttons)
- [x] Handle video orientation correctly

### 1.4 Side-by-Side Comparison
- [x] Create `ComparisonView` with two video players
- [x] Sync play/pause across both videos
- [x] Add manual sync adjustment (drag gesture to offset)
- [x] Show sync offset value
- [x] Add swap left/right button
- [x] Create `ComparisonSession` SwiftData model

### 1.5 Basic Export
- [x] Create `VideoExporter` service
- [x] Composite two videos side-by-side using AVMutableComposition
- [ ] Add watermark overlay (disabled - was causing issues)
- [x] Save to Photos library
- [x] Show export progress indicator
- [x] Share sheet integration

### 1.6 Home Screen
- [x] Create `HomeView` with options:
  - Import new video
  - View video library
  - Start comparison
- [ ] Recent comparisons list (not implemented)
- [x] Empty state for new users

### 1.7 Additional Features (Added)
- [x] Create `SwingMarker` model for marking swing phases
- [x] Create `SwingMarkerSlider` with 3 handles (start/contact/end)
- [x] Create `SwingEditorSheet` for adding/editing swings
- [x] Create `HistoryView` tab with video list and swing counts
- [x] Create `MainTabView` with Compare and Recordings tabs

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
- [x] User can import video from Photos
- [x] User can play single video with slow-mo and scrubbing
- [x] User can view two videos side-by-side
- [x] User can manually adjust sync offset
- [x] User can export comparison video
- [x] All videos persist across app restarts
- [x] User can mark swing phases (start, contact, end)
- [x] User can view/edit swings in History tab
