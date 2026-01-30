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
│  VideoStorage │ Thumbnail │ VideoExport │ SwingDetector     │
│                     │              │                         │
│               VideoSyncEngine ←────┘                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      DATA LAYER                              │
│       SwiftData │ AVFoundation │ Vision │ Photos            │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Models

**SwingVideo** (`Models/SwingVideo.swift`)
- Stores video metadata: localURL, duration, fps, thumbnail
- Tracks analysis status: hasBeenAnalyzed, analysisDate
- Has relationship to SwingMarker array
- Helper: detectedImpactTime, hasHighConfidenceDetection

**SwingMarker** (`Models/SwingMarker.swift`)
- Stores swing timing: startTime, contactTime, endTime
- Tracks detection: isAutoDetected, detectionConfidence
- Helper: confidenceDescription (High/Medium/Low)
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

**SwingDetector** (`Services/SwingDetector.swift`) ⭐ NEW
- Extracts body poses using VNDetectHumanBodyPoseRequest
- Tracks 8 key joints: wrists, elbows, shoulders, hips
- Calculates wrist velocity and acceleration
- Detects impact: max downward velocity + sudden deceleration
- Detects swing start/end from movement thresholds
- Returns SwingDetectionResult with confidence

**VideoSyncEngine** (`Services/VideoSyncEngine.swift`) ⭐ NEW
- Uses SwingDetector to analyze both videos
- Calculates sync offset from impact times
- Combines pose + audio detection for higher accuracy
- Returns SyncResult with offset and confidence

### 3. ViewModels

**VideoPlayerViewModel** (`ViewModels/VideoPlayerViewModel.swift`)
- Wraps AVPlayer with @Observable
- Provides play/pause, seek, speed control
- Tracks current time and duration

**ComparisonViewModel** (`ViewModels/ComparisonViewModel.swift`)
- Manages two VideoPlayerViewModels
- Synchronizes playback with offset
- setSyncOffset() for auto-sync integration
- Handles swap functionality

### 4. Views

**MainTabView** - Tab container (Compare, Recordings)
**HomeView** - Video library with selection for comparison
**HistoryView** - All videos with swing counts
**ComparisonView** - Side-by-side playback + Auto-Sync button
**SingleVideoPlayerView** - Video player + AUTO-DETECT button
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

### Auto-Detection Flow ⭐ NEW
```
SingleVideoPlayerView → "AUTO-DETECT" button
    ↓
VideoSyncEngine.analyzeAndMarkSwing()
    ↓
SwingDetector.analyzeVideo()
    ├── extractPoses() → VNDetectHumanBodyPoseRequest × N frames
    ├── detectImpactFromPoses() → velocity/acceleration analysis
    └── detectImpactFromAudio() → amplitude spike detection
    ↓
combineImpactDetections() → final impact time + confidence
    ↓
SwingMarker(from: result) → SwiftData
```

### Auto-Sync Flow ⭐ NEW
```
ComparisonView → "Auto-Sync" button
    ↓
VideoSyncEngine.calculateSyncOffset(video1, video2)
    ├── getImpactTime(video1) → detect or use cached
    └── getImpactTime(video2) → detect or use cached
    ↓
offset = impact1 - impact2
    ↓
ComparisonViewModel.setSyncOffset(offset)
```

### Manual Swing Marking Flow
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

## Impact Detection Algorithm

```
Input: Video frames at sample intervals

For each frame:
  1. VNDetectHumanBodyPoseRequest → body joints
  2. Extract wrist position (rightWrist or leftWrist)
  3. Store in pose history

For each frame n (n >= 2):
  1. velocity[n] = (wrist_y[n] - wrist_y[n-2]) / dt
  2. acceleration[n] = (velocity[n] - velocity[n-1]) / dt

Impact detected when:
  - velocity < -THRESHOLD (fast downward)
  - acceleration > THRESHOLD (sudden deceleration)
  - wrist_y near lowest position

Confidence = f(|velocity|, acceleration, position)
```

## Related Documents
- [Project Spec](../project_spec.md)
- [Changelog](./changelog.md)
- [Project Status](./project_status.md)
- [Milestone 2 Research](../plans/milestone-2-research.md)
