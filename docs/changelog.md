# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Fixed
- **Data loss on reinstall**: SwingVideo now stores relative paths instead of absolute paths; container UUID changes no longer break video references
- **Race conditions in detectors**: Added NSLock synchronization to PersonCropper and MotionGateService; wrapped all mutable state mutations in SwingNetDetector and ActionClassifierDetector
- **Save-before-delete**: RecordingSaveService and VideoImportService now call `modelContext.save()` before deleting source files
- **Notification leak in SwingReplayView**: Loop observer stored as `@State`, removed in `onDisappear`
- **savedVideo never cleared**: RecordingView fullScreenCover now clears `savedVideo` on dismiss
- **seekToImpact ignoring contactTime2**: ComparisonViewModel now uses both contact times to set sync offset
- **ComparisonViewModel resource leak**: Players paused and Combine subscriptions cancelled in `deinit`
- **Export temp files accumulate**: Export temp files deleted after successful save to Photos; orphaned exports cleaned at launch
- **Force unwraps in CrossCorrelationRefiner**: Replaced `window1.last!`/`window1.first!` with guard
- **Duration timer on wrong thread**: RecordingCoordinator timer now scheduled on main run loop
- **FeatureAccess always false in Release**: All features now unlocked until paywall is implemented

### Added
- **AppLogger**: Unified logging via `os.Logger` with 6 subsystem categories (detection, storage, camera, sync, general, ui)
- **VideoPathMigrationService**: One-time migration converting absolute paths to relative paths at app launch
- **@MainActor on ViewModels**: VideoPlayerViewModel and ComparisonViewModel formalize main thread isolation

### Changed
- Replaced all 39 `print()` calls across 15 files with `AppLogger` (debug/info stripped in Release builds)

### Removed
- **SwingPlaybackManager.swift**: Unused dead code
- **CountdownManager.swift**: Unused dead code

### Fixed (previous)
- **Favorites lost on save**: RecordingSaveService now copies `isFavorite` from SwingClip to SwingMarker
- **Re-analysis wipes live-detected swings**: Videos saved with swings now marked `hasBeenAnalyzed = true` to skip redundant auto-detection
- **No navigation after save**: Recording save now opens SingleVideoPlayerView via `fullScreenCover(item:)` instead of showing a confirmation dialog
- **Comparison ignores selected swing**: HomeView passes selected swing contact times to ComparisonView for precise sync offset
- **HomeView date grouping sorts wrong**: Changed from string-based sort to `Calendar.startOfDay` + `Date` comparison
- **Swing replay doesn't loop**: `enforceSwingBounds` now seeks back to start and resumes playback instead of pausing
- **PiP shows wrong swing after swap**: `swapMainAndPip` preserves existing `replayingSwingIndex` instead of always resetting to last
- **SpeedButton non-functional**: Added `onTap` callback, wired `cyclePlaybackSpeed()` with [0.25x, 0.5x, 1.0x] speeds through PiP to SwingReplayView
- **DateFormatter created per render**: Extracted to `static let dateFormatter` in HistoryView
- **Timeline swing markers at wrong position**: Added `.frame(width: width)` to inner ZStack so offset calculations reference correct center
- **Countdown lag on cancel→re-start**: Stored countdown Task reference; `cancel()` now cancels the running Task immediately instead of waiting for the next 1-second sleep to complete
- **Bloated swing bounds**: Reduced pre/post swing buffers from 1.5s→0.8s across all 4 impact detection strategies; added `maxHalfDuration=2.0s` cap to prevent swing bounds exceeding ~4s total (real golf swings are 1.5-3s)
- **Wasted bottom space in SwingDetectionPanel**: Removed `Spacer()` that pushed swing list upward, leaving empty space below

### Changed
- **SingleVideoPlayerView layout**: Removed 16:9 aspect ratio constraint — video fills available space, reduced spacing for compact layout
- **PlaybackControlsView**: Smaller buttons (40/48px), subtler backgrounds, transport left-aligned with speed pill right-aligned
- **SwingDetectionPanel**: Split EDIT MANUALLY into separate EDIT (pencil, for selected swing) and ADD (plus, for new swing) actions
- **SwingThumbnailView**: Shrunk from 100x140 to 72x96, right-aligned with auto-scroll to selected thumbnail
- **Redundant save confirmation removed**: Recording save flow goes directly to video player instead of showing dialog

### Added
- **Sandi Metz OOP Decomposition**: Major refactoring of 11 files exceeding 200-line class limit
  - 41 new focused files created, all under 200 lines
  - Strategy pattern: 4 impact detection strategies as polymorphic chain of responsibility
  - Composite pattern: 5 swing validation rules in pipeline
  - Facade pattern: CameraService delegates to 5 collaborators
  - Orchestrator pattern: VideoSyncEngine, RecordingViewModel delegate to focused collaborators
- **New Services**: PoseExtractor, PhaseClassifier, PoseFrameBuffer, RGBFrameBuffer, PersonCropper, SwingNetPredictor, ImpactDetectionChain, SwingValidationPipeline, FrameProcessingGate, RecordingSaveService, VideoImportService, CameraNotificationHandler
- **New Camera Collaborators**: CameraPermissionManager, CaptureSessionConfigurator, RecordingCoordinator, CameraError (extracted)
- **New Sync Collaborators**: TempoAnalyzer, CrossCorrelationRefiner, SyncStrategySelector, VideoFrameIterator (extracted)
- **New View Components**: SwingDetectionPanel, ComparisonTimelineSlider, ComparisonControlsView, RecordingTopBar, RecordingControlsView, RecordingPiPView, RecordingOverlayView
- **DetectorFactory**: Centralized detector instantiation
- **SyncTypes.swift**: Extracted model types (SwingDetectionResult, SyncResult, etc.)
- **RecordingTypes.swift**: RecordingState enum moved from RecordingViewModel
- **GolfSwingClassifier v3**: Retrained 4-class model with fixed phase boundaries (backswing=toe_up→top, longer no_swing windows)
- **Positioning Guide Overlay**: Full-screen dark overlay with best practice rules shown on camera during idle state
  - 4 rules with SF Symbol icons: full body in frame, no other people, face light source, keep phone steady
  - Automatically dismissed when recording starts
- **Swing Replay Controls**: Play/pause + mute floating buttons on SwingReplayView during recording
  - 32pt circular buttons with `.ultraThinMaterial` background
  - Pause stops looping; play resumes it
- **4-Strategy Swing Detection**: Expanded ActionClassifierDetector from 2 to 4 detection strategies
  - Strategy 1: downswing→follow_through phase transition (best accuracy)
  - Strategy 2: backswing→follow_through fallback (downswing too brief)
  - Strategy 3: downswing→no_swing decay (follow_through not detected, common from front camera)
  - Strategy 4: backswing→no_swing decay with residual swing signal (very fast swings)
- **v3 Training Pipeline**: `scripts/prepare_golfdb_v3_training_data.py` for GolfDB data preparation
- **SwingNet ML Model**: GolfDB-pretrained SwingNet replaces heuristic detection for offline video analysis
  - 64-frame sliding window with 9-event classification (address → impact → finish)
  - ImageNet normalization for correct model input
  - 6-layer validation pipeline: confidence, edge filter, noEvent dominance, temporal order, corroboration
- **Pose-Based Person Crop**: VNDetectHumanBodyPoseRequest runs every 60 frames (~2x/sec)
  - Computes bounding box from skeleton keypoints, expands 30% for club arc
  - Crops frames before 160x160 resize — boosts model confidence from ~30% to ~35%
  - Graceful fallback to full frame when no pose detected
- **MotionGateService**: Lightweight motion detection gate for adaptive processing
  - Compares frame luminance to detect idle/active/peak motion states
  - Adaptive classification stride: idle=30, active=8, peak=5 frames
- **Multi-Swing Detection**: `analyzeAllSwings()` scans entire video, returns all detected swings
  - `detectedSwings` array accumulates validated swings during analysis
  - SingleVideoPlayerView shows count of detected swings
  - Old auto-detected markers removed before adding new ones
- **Top-of-Backswing Extraction**: `topOfBackswingTime`/`topOfBackswingConfidence` for sync enrichment
- **Frame Processing Gate**: Prevents OutOfBuffers by dropping frames when processing queue is busy
- **PiP Animation**: Spring animation on PiP appearance during recording
- **isMotionDetected**: Added to `RealTimeSwingDetector` protocol for UI feedback

### Changed
- **ActionClassifierDetector**: Decomposed from 667→187 lines; orchestrates PoseExtractor, PhaseClassifier, PoseFrameBuffer, ImpactDetectionChain
- **SwingNetDetector**: Decomposed from 693→233 lines; orchestrates RGBFrameBuffer, PersonCropper, SwingNetPredictor, SwingValidationPipeline
- **CameraService**: Decomposed from 824→313 lines; facade over CameraPermissionManager, CaptureSessionConfigurator, RecordingCoordinator, CameraNotificationHandler
- **VideoSyncEngine**: Decomposed from 796→248 lines; orchestrates VideoFrameIterator, TempoAnalyzer, SyncStrategySelector, CrossCorrelationRefiner
- **RecordingViewModel**: Decomposed from 579→263 lines; delegates to FrameProcessingGate, RecordingSaveService
- **RecordingView**: Decomposed from 593→203 lines; uses RecordingTopBar, RecordingControlsView, RecordingPiPView, RecordingOverlayView
- **ComparisonView**: Decomposed from 366→194 lines; extracted ComparisonTimelineSlider, ComparisonControlsView
- **SingleVideoPlayerView**: Decomposed from 339→204 lines; extracted SwingDetectionPanel
- **HomeView/HistoryView**: Duplicate `importVideo` replaced with VideoImportService
- **ActionClassifierDetector**: Upgraded from v2 to v3 model, removed v2 model from bundle
- **RecordingView**: Replaced CameraTipsOverlay with PositioningGuideOverlay in idle state
- **SwingNetDetector**: Complete rewrite of detection pipeline
  - Person detection switched from `VNDetectHumanRectanglesRequest` to `VNDetectHumanBodyPoseRequest`
  - Frame buffer uses `ContiguousArray<UInt8>` instead of `[Float]` (memory + perf)
  - ImageNet normalization deferred to `buildMLInput()` (normalize once, not per-frame)
  - Impact confidence threshold: 20% → 30% (person crop restores confidence)
  - Pose detection interval: 30 → 60 frames (less frequent, amortized ~0.25ms/frame)
- **VideoSyncEngine**: `analyzeAndMarkSwing()` → `analyzeAllSwings()` returning array
  - Top-of-backswing time now extracted from SwingNet analysis
- **RecordingViewModel**: Swing replay shows in PiP instead of replacing main camera view
  - Recording continues seamlessly after swing detection (no `processingSwing` state)
- **RecordingView**: Removed `processingSwingOverlay`, PiP border color logic updated

### Fixed
- **OutOfBuffers**: Added `_isProcessingFrame` gate to prevent camera buffer pool exhaustion
- **Camera Recording**: Full recording workflow with countdown and real-time pose detection
- **CameraService**: AVCaptureSession management with video/audio capture
- **LivePoseDetector**: Real-time body pose detection on camera frames
- **LiveSwingDetector**: Real-time swing detection using wrist velocity analysis
- **RecordingView**: Recording UI with pose overlay, countdown, and PiP replay
- **Camera Tab**: New Camera tab in MainTabView for recording
- **Camera Permissions**: Added camera and microphone usage descriptions
- **Fast Swing Detection Plan**: Documented approach for <500ms swing detection
- **Camera Optimization Plan**: Comprehensive production-ready camera plan (`plans/camera-optimization-plan.md`)
- **App Lifecycle Handling**: Camera session pauses on background, resumes on foreground
- **Session Interruption Handling**: Handles phone calls, Siri, other camera apps
- **Disk Space Validation**: Checks for 500MB+ free space before recording
- **Thermal State Monitoring**: Detects device overheating conditions
- **Audio Session Configuration**: Proper AVAudioSession setup for video recording
- **Permission State Monitoring**: Checks permission status before session start
- **Interruption Overlay UI**: Shows user-friendly message when recording interrupted

### Changed
- **ML-Only Swing Detection**: Removed heuristic velocity-based detector, now exclusively uses Core ML Action Classifier
  - Simplified frame processing pipeline
  - Removed audio impact detector (ML model doesn't need audio confirmation)
  - Cleaner codebase with single detection path
- **Tab Navigation**: Reordered tabs to Camera, History, Compare
- **LiveSwingDetector**: Rewritten for immediate impact detection (~300ms latency)
  - Fires at velocity peak confirmation (2-3 frames) instead of waiting for follow-through
  - Velocity smoothing with moving average filter for noise reduction
  - Dual wrist tracking - auto-detects which hand is swinging
  - Estimates end time instead of waiting for it
- **LivePoseDetector**: Added adaptive frame processing
  - Processes every frame during active swing tracking
  - Falls back to every-2nd-frame when idle (battery saving)
  - Added `leftWristPosition` and `rightWristPosition` properties
  - Wrapped Vision processing in autoreleasepool to prevent memory leaks
- **RecordingViewModel**: Background pose processing for speed
  - Dedicated processing queue avoids main thread blocking
  - Passes both wrist positions to swing detector
  - UI updates on main thread only
  - Handles optional URL from startRecording() for error cases
- **CameraService**: Complete rewrite for production readiness
  - Prioritizes highest resolution format supporting target FPS
  - Uses YUV420 pixel format instead of BGRA (more efficient)
  - Session preset set to `.inputPriority` to avoid conflicts
  - Added CameraError enum with all error cases and user-friendly descriptions
  - Added background task management for recording completion
  - Movie fragment interval set to 5 seconds (less data loss on crash)
- **RecordingView**: Added scene phase handling and error alerts
  - `.id(swing.id)` modifier to fix swing switching in replay
- **ML Swing Detection**: Added Core ML Action Classifier for swing phase detection
  - GolfSwingClassifier.mlmodel trained with 81% training / 79% validation accuracy
  - MLSwingDetector service with fallback to heuristic detection
  - `useMLDetection` toggle to switch between ML and velocity-based detection
- **Tab Switching Performance**: Optimized camera pause/resume for fast tab switching
  - Uses `pauseSession()`/`resumeSession()` instead of full session reconfiguration
  - Tracks tab visibility to avoid resuming camera when on other tabs
  - Session configured only once, then paused/resumed on tab switches

### Fixed
- **Recording Camera Position**: Front camera now used during countdown so users can see themselves to position correctly, then switches to back camera for recording
- **Swing Replay**: When swing detected, main view shows looping replay while PiP shows live recording continuing
- **Swing Timestamps**: Now correctly file-relative by tracking recording start time
- **Skeleton Mirroring**: PoseOverlayView now correctly mirrors skeleton on front camera
- **Save/Delete Dialog**: Always shows after stopping recording (not just when swings detected)
- **Swing Switching**: Can now switch between multiple detected swings in replay view
- **Memory Leak in Vision**: Fixed potential memory leak by adding autoreleasepool
- **Tap Area on Swing Cards**: Added `.contentShape(Rectangle())` for better tap handling
- **Tab Switching Lag**: Camera tab no longer freezes when switching between tabs

---

## [0.3.0] - 2026-01-30

### Added
- **Auto-Detection Service**: SwingDetector using Vision framework body pose estimation
- **Video Sync Engine**: VideoSyncEngine for automatic sync offset calculation
- **Body Pose Analysis**: Tracks 8 key joints (wrists, elbows, shoulders, hips) for swing detection
- **Audio Impact Detection**: Analyzes audio waveform for ball impact sound spikes
- **Hybrid Detection**: Combines pose velocity + audio analysis for ~80-85% accuracy
- **Auto-Detect UI**: "AUTO-DETECT" button in SingleVideoPlayerView with progress indicator
- **Auto-Sync UI**: "Auto-Sync" button in ComparisonView to align videos at impact
- **Detection Confidence**: Shows confidence badge (High/Medium/Low) on auto-detected swings
- **Research Documentation**: Comprehensive milestone-2-research.md with algorithm details

### Changed
- **SwingMarker Model**: Added `isAutoDetected`, `detectionConfidence` properties
- **SwingVideo Model**: Added `hasBeenAnalyzed`, `analysisDate`, helper properties
- **ComparisonViewModel**: Added `setSyncOffset()` method for auto-sync
- **SingleVideoPlayerView**: Redesigned with AUTO-DETECT and MANUAL buttons
- **ComparisonView**: Added sync controls section with Auto-Sync button and reset

---

## [0.2.0] - 2026-01-30

### Added
- **Video Import**: PHPicker integration for importing videos from photo library
- **Video Playback**: Single video player with play/pause, speed controls, and timeline scrubbing
- **Side-by-Side Comparison**: ComparisonView with synchronized dual video playback
- **Manual Swing Marking**: Three-handle slider for marking swing start (green), ball contact (orange), and swing end (green)
- **Swing Editor Sheet**: Full UI for adding, editing, and deleting swing markers
- **History Tab**: List of all recordings with swing counts, tap to view/edit swings
- **Video Export**: Side-by-side video composition export to Photos library
- **Data Models**: SwingVideo, SwingMarker, ComparisonSession with SwiftData persistence
- **Services**: VideoStorageService, ThumbnailService, VideoExportService
- **Tab Navigation**: MainTabView with Compare and Recordings tabs
- Photo Library usage descriptions in project settings

### Changed
- Replaced Xcode template ContentView/Item with custom app architecture
- Updated SwiftData schema to use SwingVideo, SwingMarker, ComparisonSession

---

## [0.1.0] - 2026-01-30

### Added
- CLAUDE.md with project overview, build commands, and architecture guidance
- Code principles: Sandi Metz rules (adapted for Swift), atomic architecture, service extraction
- Monetization principles: Adam Lyttle onboarding/paywall patterns
- Documentation structure: project_spec.md, architecture.md, changelog.md, project_status.md
- Complete project specification with PRD and engineering design
- Initial Xcode project scaffolding
- SwiftData model setup
