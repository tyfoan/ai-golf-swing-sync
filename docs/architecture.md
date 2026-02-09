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
│  VideoSyncEngine (orchestrator)                             │
│    └── VideoFrameIterator                                   │
│                                                             │
│  VideoImportService │ VideoStorageService │ VideoExport     │
│  ThumbnailService                                           │
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

**Facade Pattern** — CameraService exposes a simple interface while delegating to 5 collaborators.

**Orchestrator Pattern** — ActionClassifierDetector, VideoSyncEngine, RecordingViewModel are slim orchestrators that wire collaborators together.

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

#### VideoSyncEngine (Orchestrator)

**VideoSyncEngine** (`Services/VideoSyncEngine.swift`) — orchestrates:
- `VideoFrameIterator` — Async frame extraction from video files
- Uses `ActionClassifierDetector` for offline swing detection

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
- @MainActor, dual-player swing-bound playback with 4 comparison modes
- Sync offset from pre-detected contact times (no re-analysis)
- Default: synced + auto-play, looping within swing bounds
- Drift correction (40ms threshold) in synchronized modes

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

### Auto-Detection Flow
```
SingleVideoPlayerView → "AUTO-DETECT" button
    ↓
VideoSyncEngine.analyzeAllSwings()
    ↓
ActionClassifierDetector.processFrame() × N frames (30fps sampling)
    ├── PoseExtractor → MLMultiArray keypoints
    ├── PhaseClassifier → 4-class probabilities
    └── ImpactDetectionChain → 4 strategies
    ↓
detectedSwings: [SwingBounds] → [SwingDetectionResult]
    ↓
SwingMarker(from: result) × N → SwiftData
```

### Manual Swing Marking Flow
```
SwingEditorSheet → SwingMarkerSlider (3 handles) →
SwingMarker model → SwiftData
```

### Comparison Flow
```
HomeView (select 2 swings) → SwingTimeRange × 2
    ↓
ComparisonView → ComparisonViewModel
    ├── syncOffset = swing1.contactTime - swing2.contactTime
    ├── player1 loops swing1 bounds (reference)
    ├── player2 loops swing2 bounds (drift-corrected)
    └── auto-play on entry, synced at impact
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
- [Milestone 2 Research](../plans/milestone-2-research.md)
