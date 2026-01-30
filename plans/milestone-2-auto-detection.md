# Milestone 2: Auto-Detection & Sync

**Goal**: Automatic swing phase detection and impact sync (100% offline)

**Status**: Not Started

**Depends on**: Milestone 1 ✅

**Research**: See [milestone-2-research.md](./milestone-2-research.md) for detailed analysis

---

## Approach

**Primary Solution**: Apple Vision Framework body pose detection with velocity heuristics
- Uses `VNDetectHumanBodyPoseRequest` (built-in, no external models)
- Tracks 19 body keypoints including wrists, elbows, shoulders, hips
- Detects impact by analyzing wrist velocity and deceleration
- Runs on Neural Engine, ~30 FPS, 100% offline

**Why this approach**:
- No ML model training required
- No external dependencies
- Apple-optimized for iPhone Neural Engine
- Privacy-preserving (all on-device)

---

## Tasks

### 2.1 SwingDetector Service Foundation
- [ ] Create `Services/SwingDetector.swift`
- [ ] Set up `VNDetectHumanBodyPoseRequest` for frame analysis
- [ ] Create `SwingPhase` enum: `.address`, `.backswing`, `.top`, `.downswing`, `.impact`, `.followThrough`, `.finish`
- [ ] Process video frames using `AVAssetImageGenerator`
- [ ] Extract key joints per frame: rightWrist, leftWrist, rightShoulder, leftShoulder, rightHip, leftHip
- [ ] Store pose history for velocity calculations
- [ ] Handle async processing with progress callback

### 2.2 Impact Detection Algorithm (Priority)
- [ ] Track wrist Y-position over consecutive frames
- [ ] Calculate velocity: `v = (y[n] - y[n-2]) / (t[n] - t[n-2])`
- [ ] Calculate acceleration: `a = (v[n] - v[n-1]) / dt`
- [ ] Detect impact: maximum negative velocity + sudden positive acceleration
- [ ] Add confidence scoring based on:
  - Velocity magnitude (higher = more confident)
  - Clear deceleration pattern
  - Wrist at low Y position
- [ ] Return impact frame timestamp with confidence score

### 2.3 Start/End Detection
- [ ] **Swing Start**: Detect first significant wrist movement from stationary position
  - Wrist velocity crosses threshold (e.g., > 0.02 normalized units/frame)
  - Preceded by stable period (< 5 frames of low movement)
- [ ] **Swing End**: Detect when wrist returns to stable position after follow-through
  - Wrist velocity drops below threshold
  - Wrist Y-position stabilizes at high position
- [ ] Store as `SwingMarker.startTime` and `SwingMarker.endTime`

### 2.4 Full Phase Detection (Optional Enhancement)
- [ ] **Address**: Wrists stationary, both shoulders visible, hips square
- [ ] **Backswing**: Wrist moving upward, right shoulder higher than left (for RH golfer)
- [ ] **Top**: Wrist at maximum Y, velocity crosses zero
- [ ] **Downswing**: Wrist moving downward with increasing velocity
- [ ] **Impact**: See 2.2 above
- [ ] **Follow-through**: Wrist moving upward after impact
- [ ] **Finish**: Wrists stationary at high position

### 2.5 Update Data Models
- [ ] Add `detectedPhases: [DetectedPhase]` to SwingVideo or SwingMarker
- [ ] Create `DetectedPhase` struct: `phase`, `timestamp`, `confidence`
- [ ] Add `isAutoDetected: Bool` flag to SwingMarker
- [ ] Add `detectionConfidence: Double` to SwingMarker

### 2.6 Auto-Detection on Import
- [ ] Trigger swing detection after video import
- [ ] Show "Analyzing swing..." progress indicator
- [ ] Create SwingMarker automatically if impact detected with high confidence
- [ ] Mark as `isAutoDetected = true`
- [ ] Allow user to adjust/delete if incorrect

### 2.7 Phase Timeline UI
- [ ] Create `PhaseMarkerView` component for timeline
- [ ] Show colored markers: green (start/end), orange (impact)
- [ ] Add confidence indicator (solid = high, dashed = low)
- [ ] Tap marker to jump to timestamp
- [ ] Long-press to edit/delete phase marker

### 2.8 Auto-Sync Engine
- [ ] Create `VideoSyncEngine` service
- [ ] Input: two SwingVideos with detected impact times
- [ ] Calculate sync offset: `offset = video1.impactTime - video2.impactTime`
- [ ] Apply offset to ComparisonSession
- [ ] Add "Auto-sync at impact" button in ComparisonView
- [ ] Show sync status indicator

### 2.9 Processing UX
- [ ] Show analysis progress with frame count
- [ ] Cache detection results (don't re-analyze)
- [ ] Add "Re-analyze" button for re-detection
- [ ] Graceful fallback: show manual editor if detection fails
- [ ] Display confidence: "Impact detected (87% confidence)"

---

## Technical Implementation

### Key Code Structure

```swift
// Services/SwingDetector.swift
import Vision

final class SwingDetector {
    struct DetectionResult {
        let impactTime: TimeInterval?
        let impactConfidence: Double
        let startTime: TimeInterval?
        let endTime: TimeInterval?
        let allPhases: [DetectedPhase]
    }

    func analyzeVideo(_ url: URL, progress: @escaping (Float) -> Void) async throws -> DetectionResult

    private func extractPoses(from url: URL) async throws -> [(time: TimeInterval, joints: PoseJoints)]
    private func detectImpact(from poses: [(TimeInterval, PoseJoints)]) -> (time: TimeInterval, confidence: Double)?
    private func detectSwingBounds(from poses: [(TimeInterval, PoseJoints)], impact: TimeInterval) -> (start: TimeInterval, end: TimeInterval)?
}
```

### Body Joints to Track

```swift
let golfKeyJoints: [VNHumanBodyPoseObservation.JointName] = [
    .rightWrist,      // Primary - club hand position
    .leftWrist,       // Secondary - lead hand
    .rightElbow,
    .leftElbow,
    .rightShoulder,   // Rotation tracking
    .leftShoulder,
    .rightHip,        // Weight shift
    .leftHip,
    .nose             // Head stability
]
```

### Impact Detection Algorithm

```
For each frame n (where n >= 2):
  1. wrist_velocity[n] = (wrist_y[n] - wrist_y[n-2]) / (time[n] - time[n-2])
  2. acceleration[n] = (velocity[n] - velocity[n-1]) / dt

Impact candidates where:
  - velocity[n] < -VELOCITY_THRESHOLD (moving down fast)
  - acceleration[n] > ACCEL_THRESHOLD (sudden deceleration)
  - wrist_y[n] < LOW_POSITION_THRESHOLD (hands are low)

Select candidate with highest |velocity| as impact frame
Confidence = normalize(|velocity|) * normalize(acceleration) * position_factor
```

### Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| 10s @ 30fps video | < 3 seconds | ~300 frames |
| 10s @ 60fps video | < 5 seconds | ~600 frames |
| 10s @ 240fps video | < 15 seconds | Sample every 4th frame |
| Memory usage | < 100 MB | Release frames after processing |
| Baseline device | iPhone 12 | A14 Bionic Neural Engine |

### Frame Sampling Strategy

```swift
// Adaptive sampling based on video frame rate
let sampleInterval: Int
switch video.fps {
case 0..<45:    sampleInterval = 1   // Process every frame
case 45..<90:   sampleInterval = 2   // Every 2nd frame
case 90..<180:  sampleInterval = 3   // Every 3rd frame
default:        sampleInterval = 4   // Every 4th frame for 240fps
}
```

---

## Definition of Done

- [ ] Impact frame detected automatically on video import
- [ ] Detection accuracy > 85% (within 3 frames of actual impact)
- [ ] Start/end times detected for each swing
- [ ] Phase markers visible on timeline with confidence
- [ ] "Auto-sync at impact" works for comparison view
- [ ] Processing time < 5 seconds for 30fps 10-second video
- [ ] Manual correction available if auto-detect is wrong
- [ ] Works 100% offline (no network required)
- [ ] Tested on iPhone 12 as baseline

---

## Future Enhancements (Post-MVP)

- [ ] Train CreateML Action Classifier for higher accuracy
- [ ] Add audio impact detection as secondary signal
- [ ] Support 3D body pose (iOS 17+) for better analysis
- [ ] Add pro swing library for comparison
- [ ] Analyze swing metrics (tempo, rotation angles)
