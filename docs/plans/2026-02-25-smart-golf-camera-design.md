# Smart Golf Camera: Revised App Design

**Date**: 2026-02-25
**Status**: Approved

## Vision

A focused, minimalist smart golf camera. Record on front camera, auto-detect each swing, show instant slow-motion replay, save trimmed clips to Photos. Nothing else.

Users compare swings in a separate video-comparer app. This app does one thing perfectly: capture golf swings with automatic detection.

## Core User Flow

```
1. Open app → Camera view (front camera, phone on tripod)
2. Tap Record → 5-second countdown → Recording begins
3. Swing → App detects swing → Instant slow-mo replay (PiP)
4. Swing again → Another replay
5. Tap Save → Trimmed swing clips saved to Photos
6. Done. Compare in video-comparer app.
```

## Non-Goals

- No video comparison or side-by-side playback
- No video import or library
- No onboarding flow
- No paywall or subscriptions (monetization deferred)
- No drawing/annotation tools
- No pro swing library
- No cloud storage

## Technical Architecture

### Detection Pipeline

```
Front Camera (30fps, 1080p)
    |
    v
VNSequenceRequestHandler
    |-- VNDetectHumanBodyPoseRequest (~25ms on iPhone 12+)
    |       -> 18 joints with confidence scores
    |
    v
PoseRingBuffer (90 frames = 3 seconds)
    |
    |---> Strategy A: Create ML Action Classifier (primary)
    |       - STGCN model, trained on GolfDB
    |       - 15-frame sliding window
    |       - Binary: swing / not_swing
    |       - ~20ms inference on Neural Engine
    |
    |---> Strategy B: Pose Heuristics (fallback)
    |       - Wrist velocity relative to hip center
    |       - Hip rotation angle
    |       - Multi-joint coordination score
    |
    v
SwingStateMachine
    |
    States: idle -> swingDetected -> impactSearch -> replayReady -> cooldown -> idle
    |
    |  swingDetected:  Search pose buffer for wrist y-minimum = impact frame
    |  replayReady:    Extract clip, show slow-mo replay in PiP
    |  cooldown:       2-second ignore window (prevents re-trigger)
    |
    v
User taps "Save" -> PHAssetChangeRequest -> Photos library
```

### Why VNSequenceRequestHandler

Current code uses VNImageRequestHandler (new instance per frame). This discards temporal context between frames, causing joint position jitter. VNSequenceRequestHandler maintains inter-frame state and provides temporal smoothing, critical during fast motion like the downswing.

### Why Create ML Action Classifier (Primary Strategy)

The user previously attempted pure pose heuristics (wrist velocity thresholds) and found them brittle: random arm movements, walking, and club pickup triggered false positives. The STGCN classifier learns multi-joint temporal coordination patterns, not single-joint thresholds. A swing involves coordinated shoulder + hip rotation + wrist acceleration that random movements cannot replicate.

False positive rejection is the classifier's primary advantage over heuristics.

### Why Pose Heuristics (Fallback Strategy)

Provides a baseline for comparison during the TDD tuning loop. Both strategies consume the same pose input and produce the same output type (SwingEvent). Running both on the same test videos reveals which is more accurate. The heuristic strategy also serves as a fallback if the classifier model is unavailable.

### Impact Frame Detection

The lead wrist reaches its lowest y-position at the moment of ball impact. After a swing is detected, search the pose buffer for the frame with minimum wrist y-value. This uses the same pose data already extracted for swing detection. No extra computation.

Wrist detection confidence drops during peak downswing velocity (~200ms, 6 frames at 30fps) due to motion blur. The impact frame is at the velocity transition point (deceleration), where detection recovers. A +-100ms tolerance is acceptable (3 frames at 30fps).

### Instant Slow-Motion Replay

When a swing is detected, extract a clip from the recording buffer:
- Start: address position - 0.5 seconds
- End: finish position + 0.5 seconds
- Typical clip: ~2.5 seconds

Play the clip in a PiP overlay at reduced speed (0.25x-0.5x). Auto-loop. The existing SwingReplayView handles this.

### Save to Photos

Trimmed swing clips saved via PHAssetChangeRequest. No internal database. No SwiftData. No video library. The Photos app is the library.

## Training Data: GolfDB Dataset

### Dataset Overview

| Metric | Value |
|--------|-------|
| Total annotated swings | 1,400 |
| Unique YouTube videos | 580 (572 downloaded) |
| Normal speed swings | 758 (54.1%) |
| Slow motion swings | 642 (45.9%) |
| Face-on angle swings | 461 (32.9%) |
| All videos resolution | 1920x1080 |
| FPS distribution | 30fps: 58%, 60fps: 42% |

### Binary Classifier Training Data (15-frame clips, normal speed)

| Class | Clips Available |
|-------|----------------|
| swing | 2,561 |
| not_swing | 20,793 |
| Balanced (downsampled) | 2,561 each |

Well above Create ML minimum (50 per class) and recommended (500+ per class).

### Swing Timing Statistics (normal speed, n=743)

| Phase | Median Duration |
|-------|----------------|
| Full swing (address to finish) | 1,502ms |
| Backswing (address to top) | 701ms |
| Downswing (top to impact) | 200ms |
| Follow-through (impact to finish) | 534ms |
| Address to impact | 934ms |

Key insight: downswing is only 6 frames at 30fps. Binary classification (swing/not_swing) works with 15-frame windows. Multi-phase classification does not because downswing is too short.

## TDD Tuning Loop

### Concept

Treat detection tuning like test-driven development. Every false positive becomes a test case. You never regress.

### Test Data Sources

| Source | Purpose |
|--------|---------|
| GolfDB face-on clips (461) | True positives with ground truth timestamps |
| GolfDB inter-swing gaps | True negatives (walking, setup, commentary) |
| Custom front-camera recordings (~15 min) | Edge cases: waggles, practice swings, club pickup |
| Custom non-golf recordings (~5 min) | Hard negatives: stretching, arm waving, random motion |

### Automated Loop

```
1. Extract training clips from GolfDB
   swing/ (2,561 clips) + not_swing/ (2,561 clips, balanced)

2. Train via MLActionClassifier (Swift script, ~30 min)
   - predictionWindowSize: 15
   - targetFrameRate: 30
   - augmentations: [.horizontallyFlipped]

3. Run XCTest suite on labeled test videos
   - True positives: swing detected within +-0.5s of ground truth
   - True negatives: zero false triggers on non-swing video
   - Impact accuracy: impact frame within +-100ms of ground truth

4. On failure: dump raw pose data as JSON
   - Feed to Claude Code for analysis
   - "Analyze the false positive at 3.2s. What joint patterns triggered it?"
   - Claude suggests parameter/threshold changes

5. Apply changes, retrain if needed, re-run all tests

6. Repeat until all tests green
```

### Diagnostic Output Format

Each test run produces a JSON report per video:

```json
{
  "video": "waggle_test.mp4",
  "expected_swings": [],
  "detected_swings": [
    {"time": 1.2, "confidence": 0.7, "strategy": "classifier"}
  ],
  "result": "FAIL",
  "failure_reason": "false_positive at 1.2s",
  "pose_data": [
    {
      "frame": 36,
      "time": 1.2,
      "left_wrist": {"x": 0.45, "y": 0.32, "conf": 0.8},
      "right_wrist": {"x": 0.55, "y": 0.35, "conf": 0.7},
      "left_hip": {"x": 0.48, "y": 0.55, "conf": 0.9},
      "classifier_output": {"swing": 0.72, "not_swing": 0.28}
    }
  ]
}
```

## VNDetectHumanBodyPoseRequest: Performance Characteristics

### Latency by Device

| Device | Chip | Estimated Latency |
|--------|------|-------------------|
| iPhone 11 | A13 | ~40ms (measured) |
| iPhone 12 | A14 | ~25-30ms |
| iPhone 13 | A15 | ~18-22ms |
| iPhone 14+ | A16+ | ~15-20ms |

30fps real-time is feasible on iPhone 12+ (33ms frame budget).

### Joint Detection from Face-On Angle

| Joint | Confidence (Idle) | Confidence (Swing) | Useful? |
|-------|-------------------|--------------------| --------|
| Shoulders | 0.7-0.95 | 0.5-0.8 | Yes: rotation angle |
| Hips | 0.7-0.95 | 0.6-0.9 | Yes: rotation, stable |
| Wrists | 0.5-0.85 | 0.1-0.5 | Yes: velocity, y-min for impact |
| Elbows | 0.4-0.8 | 0.2-0.5 | Marginal |
| Neck | 0.7-0.95 | 0.6-0.9 | Yes: head stability |
| Ankles | 0.6-0.9 | 0.5-0.8 | Marginal |

Face-on angle is favorable for wrist detection (no torso occlusion). Wrist confidence drops during peak downswing but recovers at impact (deceleration point).

### Known Limitations

- Wrist detection degrades during the 6-frame downswing window (motion blur)
- Backlighting (afternoon sun behind golfer) reduces accuracy
- Multiple people in frame may confuse detection (use maximumObservations = 1)
- Rain gear or very loose clothing can degrade limb detection
- Thermal throttling possible after 10-15 min continuous processing in direct sunlight

### Mitigations

- Impact detection uses the deceleration point where wrist detection recovers
- User guidance: "Position phone with sun behind the camera"
- VNSequenceRequestHandler provides temporal smoothing during fast motion
- Ring buffer holds 3 seconds, so missed frames are interpolated from neighbors

## App File Structure

```
golf-sync-swing/
|-- App/
|   +-- golf_sync_swingApp.swift              ADAPT: remove onboarding/paywall
|-- Services/
|   |-- Camera/                                KEEP: 6 files, untouched
|   |   |-- CameraService.swift
|   |   |-- CaptureSessionConfigurator.swift
|   |   |-- RecordingCoordinator.swift
|   |   |-- CameraPermissionManager.swift
|   |   |-- CameraNotificationHandler.swift
|   |   +-- CameraError.swift
|   |-- Detection/
|   |   |-- PoseDetector.swift                 NEW: VNSequenceRequestHandler + ring buffer
|   |   |-- SwingClassifier.swift              NEW: Create ML Action Classifier wrapper
|   |   |-- PoseHeuristics.swift               NEW: fallback heuristic strategy
|   |   |-- SwingStateMachine.swift            NEW: idle->detected->replay->cooldown
|   |   |-- ImpactDetector.swift               NEW: wrist y-minimum from pose buffer
|   |   +-- PersonCropper.swift                KEEP: for SwingNet fallback if needed
|   |-- AppLogger.swift                        KEEP
|   +-- PhotosSaveService.swift                NEW: PHAssetChangeRequest
|-- ViewModels/
|   +-- RecordingViewModel.swift               ADAPT: simplified
|-- Views/
|   |-- RecordingView.swift                    ADAPT: simplified
|   |-- CameraPreviewView.swift                KEEP
|   |-- SwingReplayView.swift                  KEEP
|   |-- CountdownView.swift                    KEEP
|   +-- Components/
|       |-- RecordingControlsView.swift        KEEP
|       |-- RecordingTopBar.swift              KEEP
|       |-- PositioningGuideOverlay.swift      KEEP
|       +-- DetectionBorderView.swift          KEEP
|-- Models/
|   +-- RecordingTypes.swift                   KEEP
+-- Extensions/
    +-- Color+AppTeal.swift                    KEEP
```

~20 files total (down from 95). Delete ~52 files.

## Files to Delete

All comparison views and components:
- Views/ComparisonView.swift
- Views/HomeView.swift
- Views/VideoLibraryView.swift
- Views/VideoPickerView.swift
- Views/SingleVideoPlayerView.swift
- Views/HistoryView.swift
- Views/SwingEditorSheet.swift
- Views/Components/ (entire directory except what is kept above)

All paywall and onboarding:
- Views/Onboarding/ (entire directory)
- Views/Paywall/ (entire directory)
- Views/Settings/SettingsView.swift

All purchase and feature gating:
- Services/PurchaseService.swift
- Services/FeatureAccess.swift
- Services/OnboardingService.swift
- Services/ReviewPromptService.swift

All video management (replaced by Photos save):
- Services/VideoExportService.swift
- Services/VideoImportService.swift
- Services/VideoPathMigrationService.swift
- Services/ThumbnailService.swift
- Services/ScreenshotDataService.swift

All SwiftData models (no database):
- Models/SwingVideo.swift
- Models/SwingMarker.swift
- Models/ComparisonMode.swift
- Models/ComparisonSession.swift
- Models/SyncTypes.swift
- Models/BodyJointMap.swift
- Models/SchemaVersioning.swift

All comparison view models:
- ViewModels/ComparisonViewModel.swift
- ViewModels/VideoPlayerViewModel.swift
- ViewModels/PlaybackSynchronizer.swift
- ViewModels/ManualPlaybackSynchronizer.swift
- ViewModels/Recording/FrameProcessingGate.swift

All existing SwingNet detection files (replaced by new pose-based detection):
- Services/Detection/SwingNetDetector.swift
- Services/Detection/SwingNetInference.swift
- Services/Detection/SwingSegmenter.swift
- Services/Detection/WristRefinementService.swift
- Services/Detection/SwingNetAnalysisRunner.swift
- Services/Sync/VideoFrameIterator.swift

## Competitor Reference

Golf Swing Cam (by Heliogram Labs) is the primary reference for the recording + instant replay experience. Their detection approach is almost certainly VNDetectHumanBodyPoseRequest + heuristic rules on joint trajectories. Evidence: their wireframe overlay feature confirms they run body pose estimation; it works without ball or club (body-motion only); front camera on tripod is optimal for this API.

Our approach differs by using a trained STGCN classifier instead of hand-tuned heuristics, which should reduce false positives from waggles, walking, and random arm movements.

## Success Criteria

1. Zero false positives on standard non-swing activities (walking, waggle, setup, stretching)
2. Detection of 95%+ of real swings (face-on, front camera, 2-3m distance)
3. Impact frame accuracy within +-100ms of ground truth
4. Detection latency under 1 second from swing completion to replay trigger
5. App size under 30MB (no large ML models)
6. Battery life: 1+ hour continuous recording session

## Risk Mitigations

| Risk | Mitigation |
|------|------------|
| Classifier false positives on waggles | TDD loop with dedicated waggle test videos |
| Wrist detection fails during downswing | Impact = deceleration point where detection recovers |
| GolfDB training data is broadcast footage, not front-camera | Pose-based classifier is angle-agnostic (joints are joints); validate on custom front-camera clips |
| Thermal throttling during long sessions | Process every 2nd frame if device gets hot (15fps is still sufficient for swing detection) |
| Person too far from camera | PositioningGuideOverlay guides user to optimal 2-3m distance |
