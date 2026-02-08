# Project Status

> Current progress for Golf Sync Swing

**Last Updated**: 2026-02-09

---

## Current Phase

**Phase**: Deployment Preparation
**Status**: On Track
**Current Focus**: Bug fixes, thread safety, production hardening

---

## Milestone Progress

### Milestone 1: [MVP] - Complete ✅

| Deliverable | Status | Notes |
|-------------|--------|-------|
| Project Setup | Done | Folder structure, SwiftData models |
| Video Import | Done | PHPicker integration, copy to app storage |
| Single Video Player | Done | AVPlayer with controls, timeline slider |
| Side-by-Side Comparison | Done | Synced dual playback with offset adjustment |
| Manual Swing Marking | Done | 3-handle slider (green/orange/green) |
| History Tab | Done | Video list with swing counts |
| Video Export | Done | Side-by-side composition to Photos |

**Progress**: ██████████ 100%

### Milestone 2: [Auto-Detection] - Complete ✅

| Deliverable | Status | Notes |
|-------------|--------|-------|
| Vision pose estimation | Done | VNDetectHumanBodyPoseRequest, 8 key joints |
| Impact detection algorithm | Done | Wrist velocity + acceleration analysis |
| Audio impact detection | Done | Amplitude spike detection |
| Auto-detect UI | Done | Button + progress in SingleVideoPlayerView |
| Auto-sync at impact | Done | VideoSyncEngine + ComparisonView button |
| Confidence scoring | Done | High/Medium/Low based on detection quality |

**Progress**: ██████████ 100%

### Milestone 3: [Recording & Annotations] - In Progress

| Deliverable | Status | Notes |
|-------------|--------|-------|
| Camera recording | Done | CameraService with AVCaptureSession |
| Real-time pose detection | Done | LivePoseDetector using Vision |
| Real-time swing detection | Done | LiveSwingDetector with velocity analysis |
| Recording UI | Done | RecordingView with countdown, pose overlay |
| PiP during replay | Done | Shows live feed during swing replay |
| **Production Camera Fixes** | Done | Lifecycle, interruptions, errors, memory |
| **SwingNet ML Detection** | Done | GolfDB pretrained, 6-layer validation |
| **Pose-Based Person Crop** | Done | VNDetectHumanBodyPoseRequest, 30% expansion |
| **Multi-Swing Detection** | Done | Full-video scan, returns all swings |
| **Motion Gate** | Done | Adaptive stride, frame processing gate |
| **4-Strategy Detection** | Done | Phase transition, backswing fallback, downswing decay, backswing decay |
| **Positioning Guide** | Done | Best practice rules overlay on camera |
| **Replay Controls** | Done | Play/pause + mute on swing replay |
| Drawing tools | Not Started | |
| Annotation overlay | Not Started | |

**Progress**: █████████░ 85%

### Code Quality: [Sandi Metz Decomposition] - Complete ✅

| Deliverable | Status | Notes |
|-------------|--------|-------|
| ActionClassifierDetector decomposition | Done | 667→187 lines, 9 new files |
| SwingNetDetector decomposition | Done | 693→233 lines, 9 new files (deprecated) |
| CameraService decomposition | Done | 824→313 lines, 5 new files |
| VideoSyncEngine decomposition | Done | 796→248 lines, 4 new files |
| RecordingViewModel decomposition | Done | 579→263 lines, 2 new files |
| View decomposition | Done | 6 views reduced, 7 new components |
| Service extraction | Done | VideoImportService, RecordingSaveService, DetectorFactory |
| Build verification | Done | All 41 new files compile clean |

**Progress**: ██████████ 100%

### Deployment Preparation - Complete ✅

| Deliverable | Status | Notes |
|-------------|--------|-------|
| Relative path migration | Done | Prevents data loss on reinstall/restore |
| Thread safety (detectors) | Done | NSLock on PersonCropper, MotionGateService, wrapped state in both detectors |
| Save-before-delete | Done | RecordingSaveService, VideoImportService |
| Resource leak fixes | Done | ComparisonViewModel deinit, notification observer, savedVideo, export cleanup |
| @MainActor on ViewModels | Done | VideoPlayerViewModel, ComparisonViewModel |
| os.Logger migration | Done | 39 print() → AppLogger across 15 files |
| Dead code removal | Done | SwingPlaybackManager, CountdownManager deleted |
| FeatureAccess unlock | Done | All features free until paywall |
| Timer thread fix | Done | RecordingCoordinator timer on main run loop |
| Force unwrap guards | Done | CrossCorrelationRefiner |

**Progress**: ██████████ 100%

### Milestone 4: [Monetization] - Not Started

| Deliverable | Status | Notes |
|-------------|--------|-------|
| RevenueCat integration | Not Started | |
| Onboarding flow | Not Started | |
| Paywall | Not Started | |

**Progress**: ░░░░░░░░░░ 0%

---

## Recent Updates

### 2026-02-09 (Deployment Preparation — 20 Issues Fixed)
- Fixed 5 critical issues: relative path storage (data loss on reinstall), race conditions in 4 detector/service classes
- Fixed 5 high issues: ComparisonViewModel deinit leak, save-before-delete in 2 services, notification leak in SwingReplayView, savedVideo never cleared
- Fixed 6 medium issues: FeatureAccess always false in Release, @MainActor on ViewModels, export temp file cleanup, dead code removal, print→os.Logger, timer thread
- Fixed 4 low issues: force unwraps in CrossCorrelationRefiner, seekToImpact using contactTime2
- New services: AppLogger (unified os.Logger), VideoPathMigrationService (one-time path migration)
- Deleted: SwingPlaybackManager.swift, CountdownManager.swift (unused dead code)

### 2026-02-08 (10 Bug Fixes + Player UI Overhaul)
- Fixed 10 bugs in post-swing-detection flow:
  - Favorites lost on save, no navigation after save, redundant save confirmation dialog
  - Re-analysis wiping live-detected swings, SpeedButton non-functional
  - Comparison ignoring selected swing contact times, HomeView date grouping wrong sort order
  - Swing replay not looping, PiP showing wrong swing after swap, DateFormatter per render
- Fixed timeline swing markers rendering at wrong position (ZStack width issue)
- SingleVideoPlayerView: removed 16:9 constraint, video fills available space
- PlaybackControlsView: smaller buttons, subtler styling, transport left-aligned
- SwingDetectionPanel: split EDIT MANUALLY into EDIT (pencil) + ADD (plus) actions
- SwingThumbnailView: shrunk to 72x96, right-aligned with ScrollViewReader auto-scroll

### 2026-02-08 (Swing Detection & Recording UX Fixes)
- Fixed countdown lag when cancelling and re-starting recording (Task cancellation)
- Tightened swing bounds: pre/post buffers 1.5s→0.8s, max half-duration 2.0s cap
- Removed wasted bottom space in SwingDetectionPanel (Spacer removal)

### 2026-02-08 (Sandi Metz OOP Decomposition)
- Major refactoring: 11 files exceeding 200-line Sandi Metz limit decomposed
- 41 new focused files created, largest is 193 lines (CaptureSessionConfigurator)
- Strategy pattern for impact detection: 4 strategies as chain of responsibility
- Composite pattern for swing validation: 5 rules in pipeline
- Facade pattern for CameraService (5 collaborators)
- Orchestrator pattern for VideoSyncEngine, RecordingViewModel
- Key reductions: CameraService 824→313, VideoSyncEngine 796→248, ActionClassifierDetector 667→187
- Extracted shared services: VideoImportService, RecordingSaveService, DetectorFactory
- Extracted view components: SwingDetectionPanel, ComparisonTimelineSlider, ComparisonControlsView, 4 RecordingView components
- SwingNetDetector marked as deprecated (will be removed)
- All changes verified with successful build

### 2026-02-07 (v3 Model + 4-Strategy Detection + Recording UX)
- Trained GolfSwingClassifier v3 with fixed phase boundaries (backswing=toe_up→top)
- Expanded ActionClassifierDetector to 4 detection strategies for robust swing detection
  - Added downswing-decay (Strategy 3) for front-camera where follow_through isn't recognized
  - Added backswing-decay (Strategy 4) for very fast swings that skip downswing phase
- Added PositioningGuideOverlay: best practice rules shown on camera during idle state
- Added play/pause + mute controls on SwingReplayView
- Removed CameraTipsOverlay (replaced by positioning guide)
- Deleted v2 model from bundle, v3 is now the default

### 2026-02-06 (SwingNet Overhaul + Pose-Based Person Crop)
- Complete rewrite of SwingNetDetector with 6-layer validation pipeline
- Added pose-based person crop using VNDetectHumanBodyPoseRequest (every 60 frames)
- Bounding box from skeleton keypoints + 30% expansion for club arc
- Impact confidence restored to 30% threshold (person crop boosts to ~35%)
- Added MotionGateService for adaptive processing (idle/active/peak stride)
- Frame buffer switched to ContiguousArray<UInt8> for memory efficiency
- Added multi-swing detection: analyzeAllSwings() scans entire video
- Top-of-backswing extraction for sync enrichment
- Frame processing gate prevents OutOfBuffers from camera buffer exhaustion
- Recording UX: swing replay in PiP instead of replacing camera view
- PiP spring animation on appearance

### 2026-02-02 (ML-Only Swing Detection)
- Added GolfSwingClassifier.mlmodel (81% training / 79% validation accuracy)
- Created MLSwingDetector service for Core ML-based swing phase detection
- Integrated ML detector into RecordingViewModel as sole detection method
- ML detector tracks backswing → downswing → follow_through phases
- Removed heuristic velocity-based detector for cleaner codebase
- Removed audio impact detector (ML handles detection independently)

### 2026-02-01 (Tab Switching Performance)
- Optimized camera pause/resume for fast tab switching
- Added `isTabVisible` and `hasSetupCamera` flags to RecordingView
- Camera session now configured once, then paused/resumed on tab switches
- Audio session configuration cached to avoid redundant setup
- Scene phase handling now respects tab visibility

### 2026-02-01 (Production Camera Fixes)
- Complete rewrite of CameraService for production readiness
- Added app lifecycle handling (pause session on background, resume on foreground)
- Added AVAudioSession configuration for video recording
- Changed pixel format from BGRA to YUV420 (more efficient)
- Fixed session preset conflict (now uses `.inputPriority`)
- Added session interruption handling (phone calls, Siri, other apps)
- Added disk space validation (requires 500MB+ before recording)
- Added thermal state monitoring
- Added CameraError enum with user-friendly error descriptions
- Added background task for recording completion
- Fixed memory leak in LivePoseDetector with autoreleasepool
- Added interruption overlay UI in RecordingView
- Fixed swing switching in replay view with `.id()` modifier
- Created comprehensive camera optimization plan (`plans/camera-optimization-plan.md`)

### 2026-01-30 (Fast Swing Detection)
- Rewrote LiveSwingDetector for immediate impact detection (~300ms latency)
- Added velocity smoothing with moving average filter
- Added dual wrist tracking (auto-detects which hand is swinging)
- Updated LivePoseDetector with adaptive frame processing
- Moved pose processing to background queue for speed
- Fixed skeleton mirroring on front camera
- Fixed front camera resolution selection (now picks highest resolution)
- Added save/delete dialog that always shows after recording stops
- Created fast-swing-detection.md plan document

### 2026-01-30 (Milestone 3)
- Created CameraService for AVCaptureSession management
- Created LivePoseDetector for real-time body pose detection
- Created LiveSwingDetector for real-time swing detection
- Created RecordingViewModel state machine
- Created RecordingView with countdown, pose overlay, PiP replay
- Added Camera tab to MainTabView
- Added camera/microphone permissions
- Fixed camera positioning: front camera for countdown (user positioning), back camera for recording
- Added SwingReplayView for looping detected swings during recording
- PiP shows live camera feed with pose overlay while replay plays

### 2026-01-30 (Milestone 2)
- Created SwingDetector service using Vision body pose
- Created VideoSyncEngine for auto-sync calculation
- Implemented hybrid detection (pose + audio) for ~80-85% accuracy
- Added AUTO-DETECT button to SingleVideoPlayerView
- Added Auto-Sync button to ComparisonView
- Updated SwingMarker with isAutoDetected, detectionConfidence
- Updated SwingVideo with hasBeenAnalyzed, analysisDate
- Created comprehensive research document (milestone-2-research.md)

### 2026-01-30 (Milestone 1)
- Completed Milestone 1 MVP implementation
- Created all core views, models, services
- Added tab navigation (Compare, Recordings)

---

## Upcoming Work

- [ ] Test recording on real device (simulator doesn't have camera)
- [ ] Fine-tune real-time swing detection thresholds
- [ ] Add swing clip extraction from recording buffer
- [ ] Add recording review mode (Full Video / Swings Only)
- [ ] Implement drawing tools for annotations
- [ ] Add annotation overlay on video playback

---

## Known Issues

- VideoExportService uses deprecated AVFoundation APIs (iOS 18/26 deprecations)
- Export watermark disabled (was causing issues)
- Auto-detection accuracy depends on camera angle and lighting
- CrossCorrelation refinement is effectively dead code (velocity profiles always empty)
- Accessibility labels missing on custom controls (timeline, playback, recording)
