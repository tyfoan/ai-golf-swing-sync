# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added
- **Camera Recording**: Full recording workflow with countdown and real-time pose detection
- **CameraService**: AVCaptureSession management with video/audio capture
- **LivePoseDetector**: Real-time body pose detection on camera frames
- **LiveSwingDetector**: Real-time swing detection using wrist velocity analysis
- **RecordingView**: Recording UI with pose overlay, countdown, and PiP replay
- **Camera Tab**: New Camera tab in MainTabView for recording
- **Camera Permissions**: Added camera and microphone usage descriptions
- **Fast Swing Detection Plan**: Documented approach for <500ms swing detection

### Changed
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
- **RecordingViewModel**: Background pose processing for speed
  - Dedicated processing queue avoids main thread blocking
  - Passes both wrist positions to swing detector
  - UI updates on main thread only
- **CameraService**: Improved front camera resolution selection
  - Prioritizes highest resolution format supporting target FPS

### Fixed
- **Recording Camera Position**: Front camera now used during countdown so users can see themselves to position correctly, then switches to back camera for recording
- **Swing Replay**: When swing detected, main view shows looping replay while PiP shows live recording continuing
- **Swing Timestamps**: Now correctly file-relative by tracking recording start time
- **Skeleton Mirroring**: PoseOverlayView now correctly mirrors skeleton on front camera
- **Save/Delete Dialog**: Always shows after stopping recording (not just when swings detected)

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
