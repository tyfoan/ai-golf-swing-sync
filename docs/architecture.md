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

**SwingNetDetector** (`Services/SwingNetDetector.swift`) ⭐ REWRITTEN
- GolfDB-pretrained SwingNet model: 64 frames × 3ch × 160×160 → 64 × 9 event probs
- Pose-based person crop: VNDetectHumanBodyPoseRequest every 60 frames
  - Bounding box from skeleton keypoints, expanded 30% for club arc
  - Falls back to full frame when no pose detected
- MotionGateService for adaptive classification stride (idle=30, active=8, peak=5)
- 6-layer validation: confidence, edge filter, noEvent dominance, temporal order, corroboration
- Exposes topOfBackswingTime/topOfBackswingConfidence for sync enrichment
- ContiguousArray<UInt8> frame buffer, ImageNet normalization deferred to buildMLInput()

**MotionGateService** (`Services/MotionGateService.swift`) ⭐ NEW
- Lightweight frame-to-frame motion detection using luminance comparison
- Returns idle/active/peak state for adaptive processing decisions

**VideoSyncEngine** (`Services/VideoSyncEngine.swift`)
- Uses SwingNetDetector for offline video analysis
- `analyzeAllSwings()` scans entire video, returns all detected swings
- Calculates sync offset from impact times
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

### Auto-Detection Flow (SwingNet)
```
SingleVideoPlayerView → "AUTO-DETECT" button
    ↓
VideoSyncEngine.analyzeAllSwings()
    ↓
SwingNetDetector.processFrame() × N frames (30fps sampling)
    ├── extractRGBData()
    │     ├── detectPersonPose() (every 60 frames) → cachedPersonBounds
    │     ├── crop to person region (if pose detected)
    │     └── scale to 160×160, extract UInt8 CHW data
    ├── MotionGateService.update() → adaptive stride
    └── runSwingNetClassification() (every stride frames)
          ├── buildMLInput() → ImageNet-normalized Float32 tensor
          ├── SwingNet.prediction() → 64×9 event probabilities
          ├── analyzeFullOutput() → SwingNetAnalysis
          └── validateSwingDetection() → 6-layer validation
    ↓
detectedSwings: [SwingBounds] → [SwingDetectionResult]
    ↓
SwingMarker(from: result) × N → SwiftData
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

## SwingNet Detection Algorithm

```
Input: 64 consecutive frames (160×160 RGB, ImageNet normalized)

SwingNet Model (GolfDB pretrained):
  Output: 64 × 9 event probabilities
  Events: address, toe_up, mid_backswing, top, mid_downswing,
          impact, mid_follow_through, finish, no_event

Single-Pass Analysis (O(64×9)):
  - Track peak (frame, probability) for each event
  - Count frames where noEvent is dominant class

6-Layer Validation Pipeline:
  1. Impact confidence ≥ 30%
  2. Impact frame position: high conf → frames 4-60, low conf → 17-47
  3. NoEvent dominance: ≥ 24/64 frames (real swings are mostly idle)
  4. Temporal order: address < top < impact
  5. Corroboration: address OR top confidence ≥ 15%

Pose-Based Person Crop (every 60 frames):
  - VNDetectHumanBodyPoseRequest → skeleton keypoints (conf > 0.1)
  - Bounding box from min/max of keypoint positions
  - Expand 30% for club arc, clamp to image bounds
  - Fallback: full frame when no pose detected

Performance Budget (~3.4ms/frame amortized):
  - Pose detection: ~15ms × 1/60 frames = ~0.25ms
  - Motion gate: ~0.1ms
  - CIImage crop+scale: ~2ms
  - UInt8 extraction: ~1ms
```

## Related Documents
- [Project Spec](../project_spec.md)
- [Changelog](./changelog.md)
- [Project Status](./project_status.md)
- [Milestone 2 Research](../plans/milestone-2-research.md)
