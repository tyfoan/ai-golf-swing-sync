# Architecture

> System design and data flow for Golf Sync Swing

## System Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         CLIENT                               │
│                    SwiftUI Views Layer                       │
│   MainTabView → HomeView / HistoryView → SingleVideoPlayer   │
│                     ↓              ↓                         │
│            ComparisonView    SwingEditorSheet                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      VIEW MODELS                             │
│              State Management & Business Logic               │
│         VideoPlayerViewModel │ ComparisonViewModel           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        SERVICES                              │
│  VideoStorageService │ ThumbnailService │ VideoExportService │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      DATA LAYER                              │
│              SwiftData │ AVFoundation │ Photos               │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Models

**SwingVideo** (`Models/SwingVideo.swift`)
- Stores video metadata: localURL, duration, fps, thumbnail
- Has relationship to SwingMarker array

**SwingMarker** (`Models/SwingMarker.swift`)
- Stores swing timing: startTime, contactTime, endTime
- Belongs to SwingVideo

**ComparisonSession** (`Models/ComparisonSession.swift`)
- Links two SwingVideo references
- Stores sync offset between videos

### 2. Services

**VideoStorageService** (`Services/VideoStorageService.swift`)
- Copies imported videos to app's Documents directory
- Creates SwingVideo model with metadata
- Manages video file lifecycle

**ThumbnailService** (`Services/ThumbnailService.swift`)
- Generates thumbnail from first frame of video
- Uses AVAssetImageGenerator

**VideoExportService** (`Services/VideoExportService.swift`)
- Creates side-by-side video composition
- Uses AVMutableComposition and AVAssetExportSession
- Saves to Photos library

### 3. ViewModels

**VideoPlayerViewModel** (`ViewModels/VideoPlayerViewModel.swift`)
- Wraps AVPlayer with @Observable
- Provides play/pause, seek, speed control
- Tracks current time and duration

**ComparisonViewModel** (`ViewModels/ComparisonViewModel.swift`)
- Manages two VideoPlayerViewModels
- Synchronizes playback with offset
- Handles swap functionality

### 4. Views

**MainTabView** - Tab container (Compare, Recordings)
**HomeView** - Video library with selection for comparison
**HistoryView** - All videos with swing counts
**ComparisonView** - Side-by-side synchronized playback
**SingleVideoPlayerView** - Single video with swings list
**SwingEditorSheet** - Add/edit swing markers with 3-handle slider

### 5. Components

**VideoPlayerView** - AVPlayerViewController wrapper
**VideoRowView** - Video thumbnail with metadata
**PlaybackControlsView** - Play/pause, speed, frame step buttons
**TimelineSlider** - Scrubbing timeline
**SwingMarkerSlider** - 3-handle slider for swing phases
**SwingRowView** - Single swing display with edit button
**ExportProgressView** - Export progress and share UI

## Data Flow

### Video Import Flow
```
PHPicker → VideoStorageService.copyVideoToStorage →
ThumbnailService.generateThumbnail → SwingVideo model → SwiftData
```

### Swing Marking Flow
```
SwingEditorSheet → SwingMarkerSlider (3 handles) →
SwingMarker model → SwiftData
```

### Comparison Flow
```
HomeView (select 2 videos) → ComparisonView →
ComparisonViewModel (sync offset) → VideoPlayerViewModel × 2
```

### Export Flow
```
ComparisonView → VideoExportService.exportComparison →
AVMutableComposition → AVAssetExportSession → Photos library
```

## Related Documents
- [Project Spec](../project_spec.md)
- [Changelog](./changelog.md)
- [Project Status](./project_status.md)
