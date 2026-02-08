# Architecture

> System design and data flow for Golf Sync Swing

## System Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     VIEWS (SwiftUI)                          │
│   MainTabView → HomeView / HistoryView → SingleVideoPlayer  │
│   ComparisonView ← ComparisonTimelineSlider                 │
│                    ← ComparisonControlsView                  │
│   RecordingView  ← RecordingTopBar, RecordingControlsView   │
│                  ← RecordingPiPView, RecordingOverlayView   │
│   SingleVideoPlayerView ← SwingDetectionPanel               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      VIEW MODELS                            │
│  RecordingViewModel (orchestrator)                          │
│    ├── FrameProcessingGate   (thread-safe frame gating)     │
│    └── RecordingSaveService  (save to SwiftData)            │
│  VideoPlayerViewModel │ ComparisonViewModel                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   SERVICES (Orchestrators)                   │
│                                                             │
│  CameraService (facade)                                     │
│    ├── CameraPermissionManager                              │
│    ├── CaptureSessionConfigurator                           │
│    ├── RecordingCoordinator                                 │
│    └── CameraNotificationHandler                            │
│                                                             │
│  ActionClassifierDetector (orchestrator)                     │
│    ├── PoseExtractor → PhaseClassifier                      │
│    ├── PoseFrameBuffer (thread-safe ring buffer)            │
│    └── ImpactDetectionChain (4 strategy objects)            │
│                                                             │
│  SwingNetDetector (orchestrator, deprecated)                │
│    ├── PersonCropper → SwingNetPredictor                    │
│    ├── RGBFrameBuffer (thread-safe ring buffer)             │
│    └── SwingValidationPipeline (5 rule objects)             │
│                                                             │
│  VideoSyncEngine (orchestrator)                             │
│    ├── VideoFrameIterator                                   │
│    ├── TempoAnalyzer                                        │
│    ├── SyncStrategySelector                                 │
│    └── CrossCorrelationRefiner                              │
│                                                             │
│  VideoImportService │ VideoStorageService │ VideoExport     │
│  DetectorFactory │ ThumbnailService │ MotionGateService     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      DATA LAYER                             │
│       SwiftData │ AVFoundation │ Vision │ CoreML │ Photos  │
└─────────────────────────────────────────────────────────────┘
```

## Design Patterns

**Strategy Pattern** — Impact detection uses 4 interchangeable strategies in a chain of responsibility:
  `DownswingToFollowThroughStrategy`, `BackswingToFollowThroughStrategy`, `DownswingDecayStrategy`, `BackswingDecayStrategy`

**Composite Pattern** — Swing validation uses 5 rules in a pipeline:
  `ImpactConfidenceRule`, `EdgeArtifactRule`, `NoEventDominanceRule`, `TemporalOrderRule`, `MultiEventCorroborationRule`

**Facade Pattern** — CameraService exposes a simple interface while delegating to 5 collaborators.

**Orchestrator Pattern** — ActionClassifierDetector, SwingNetDetector, VideoSyncEngine, RecordingViewModel are slim orchestrators that wire collaborators together.

**Factory Pattern** — DetectorFactory centralizes detector instantiation.

## Components

### 1. Models

**SwingVideo** (`Models/SwingVideo.swift`)
- Stores video path relative to Documents directory (survives reinstall/restore)
- Resolves legacy absolute paths for backwards compatibility
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

**VideoImportService** (`Services/VideoImportService.swift`)
- Imports video from URL into SwiftData (used by HomeView + HistoryView)
- Saves context before deleting source file

**RecordingSaveService** (`Services/RecordingSaveService.swift`)
- Saves recorded video + detected swings to SwiftData
- Saves context before deleting source file

**AppLogger** (`Services/AppLogger.swift`)
- Unified `os.Logger` with 6 subsystem categories: detection, storage, camera, sync, general, ui
- Debug/info messages stripped in Release builds

**VideoPathMigrationService** (`Services/VideoPathMigrationService.swift`)
- One-time migration: converts absolute paths to relative paths in SwingVideo records
- Guarded by UserDefaults flag, runs at app launch

**DetectorFactory** (`Services/Detection/DetectorFactory.swift`)
- Centralized detector instantiation for ActionClassifier and SwingNet

#### Camera Service (Facade)

**CameraService** (`Services/CameraService.swift`) — facade over:
- `CameraPermissionManager` — Permission requests and state checks
- `CaptureSessionConfigurator` — Session setup and format negotiation
- `RecordingCoordinator` — Recording lifecycle and duration timer
- `CameraNotificationHandler` — Session interruption/error notifications
- `CameraError` — Error types for camera operations

#### ActionClassifierDetector (Orchestrator)

**ActionClassifierDetector** (`Services/ActionClassifierDetector.swift`) — orchestrates:
- `PoseExtractor` — VNDetectHumanBodyPoseRequest → MLMultiArray keypoints
- `PhaseClassifier` — CoreML GolfSwingClassifier v3 model wrapper
- `PoseFrameBuffer` — Thread-safe ring buffer for pose frames (NSLock)
- `ImpactDetectionChain` → 4 strategies in priority order:
  1. `DownswingToFollowThroughStrategy` — phase transition crossover
  2. `BackswingToFollowThroughStrategy` — fast swing fallback
  3. `DownswingDecayStrategy` — front camera (no follow_through)
  4. `BackswingDecayStrategy` — very fast swings

#### SwingNetDetector (Orchestrator, Deprecated)

**SwingNetDetector** (`Services/SwingNetDetector.swift`) — orchestrates:
- `RGBFrameBuffer` — Thread-safe ring buffer for RGB frame data
- `PersonCropper` — Pose-based person detection + bounding box crop
- `SwingNetPredictor` — CoreML SwingNet model + ImageNet normalization
- `SwingValidationPipeline` → 5 rules:
  1. `ImpactConfidenceRule`, 2. `EdgeArtifactRule`, 3. `NoEventDominanceRule`, 4. `TemporalOrderRule`, 5. `MultiEventCorroborationRule`

**MotionGateService** (`Services/MotionGateService.swift`)
- Lightweight motion detection for adaptive processing stride

#### VideoSyncEngine (Orchestrator)

**VideoSyncEngine** (`Services/VideoSyncEngine.swift`) — orchestrates:
- `VideoFrameIterator` — Async frame extraction from video files
- `TempoAnalyzer` — Swing tempo comparison
- `SyncStrategySelector` — Best sync point selection (4 cases)
- `CrossCorrelationRefiner` — Sub-frame alignment via velocity cross-correlation

### 3. ViewModels

**RecordingViewModel** (`ViewModels/RecordingViewModel.swift`) — orchestrator
- Composes: FrameProcessingGate, RecordingSaveService, CameraService, ActionClassifierDetector
- State machine: idle → countdown → recording → finalizingVideo → reviewing → saving

**FrameProcessingGate** (`ViewModels/Recording/FrameProcessingGate.swift`)
- Thread-safe NSLock-based frame gating (prevents OutOfBuffers)
- Tracks recording timestamps for relative timing

**VideoPlayerViewModel** (`ViewModels/VideoPlayerViewModel.swift`)
- @MainActor, wraps AVPlayer with @Observable
- Provides play/pause, seek, speed control

**ComparisonViewModel** (`ViewModels/ComparisonViewModel.swift`)
- @MainActor, manages dual-player synchronized playback with drift correction

### 4. Views

**MainTabView** - Tab container (Camera, Compare, Recordings)
**HomeView** - Video library with selection for comparison
**HistoryView** - All videos with swing counts
**ComparisonView** → ComparisonTimelineSlider + ComparisonControlsView
**SingleVideoPlayerView** → SwingDetectionPanel (auto-detect + swing list)
**RecordingView** → RecordingTopBar + RecordingControlsView + RecordingPiPView + RecordingOverlayView
**SwingEditorSheet** - Add/edit swing markers with 3-handle slider

### 5. Components

**VideoPlayerView** - AVPlayerViewController wrapper
**VideoRowView** - Video thumbnail with metadata
**PlaybackControlsView** - Play/pause, speed, frame step buttons
**TimelineSlider** - Scrubbing timeline
**SwingMarkerSlider** - 3-handle slider for swing phases
**SwingRowView** - Single swing display with edit button
**ExportProgressView** - Export progress and share UI
**SwingDetectionPanel** - Auto-detect button, progress, swing list
**ComparisonTimelineSlider** - Timeline for comparison view
**ComparisonControlsView** - Playback controls for comparison
**RecordingTopBar** - Cancel, timer, swing count badge
**RecordingControlsView** - Record/stop/save buttons
**RecordingPiPView** - Picture-in-picture overlay
**RecordingOverlayView** - State-dependent overlays (finalizing, replay, interruption)

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
