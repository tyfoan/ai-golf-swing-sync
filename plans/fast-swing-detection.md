# Fast Real-Time Swing Detection Plan

## Goal
Achieve Golf Swing Cam-like instant swing detection (<1 second) using the front camera, with immediate replay feedback.

## Research Findings

### How Golf Swing Cam Works
Based on research from [App Store](https://apps.apple.com/us/app/golf-swing-cam-slow-motion/id6458876528) and similar apps:

1. **Immediate Detection**: Swings are detected at the moment of impact (peak velocity), not after follow-through
2. **Velocity Peak Detection**: The downswing reaches maximum speed at/near ball contact - this is the trigger
3. **2-Second Clips**: Apps like Swing Profile capture only "2-second vital swing motion"
4. **No Wait for Completion**: Detection fires at impact, end time is estimated/padded

### Technical Approaches from Research
- [GolfPose](https://ieeexplore.ieee.org/document/9859415/) uses temporal-based 2D pose estimation optimized for mobile
- [MediaPipe](https://dev.to/aws-builders/pose-estimation-in-action-visualizing-the-golf-swing-frame-by-frame-2hmg) provides 33 keypoints with real-time tracking
- Edge processing with Savitzky-Golay filtering compensates for noise
- Detection accuracy: ~79% for real-time vs 72% for slow-motion

---

## Current Implementation Issues

### 1. Detection Latency (~2-3 seconds)
- **Problem**: Current detector waits for `postImpactDuration` (0.5s) PLUS deceleration confirmation
- **Problem**: Swing end detection adds additional delay
- **Solution**: Fire detection immediately at velocity peak, estimate end time

### 2. Frame Processing Rate
- **Problem**: Processing every 2nd frame at 30fps = 15 pose samples/sec
- **Problem**: At peak swing speed, wrist moves significantly between samples
- **Solution**: Process every frame during active swing detection

### 3. Front Camera Wrist Selection
- **Problem**: Code prefers right wrist, but front camera mirrors the view
- **Problem**: User's actual right hand appears on LEFT side of frame
- **Solution**: Detect golfer handedness or track BOTH wrists, use the one with more motion

### 4. Main Thread Blocking
- **Problem**: `processFrame` dispatches to MainActor, adding latency
- **Solution**: Process pose detection on background queue, only update UI on main

### 5. Velocity Calculation Noise
- **Problem**: Raw velocity from frame-to-frame is noisy
- **Solution**: Use smoothed velocity (moving average or Savitzky-Golay filter)

---

## Implementation Plan

### Phase 1: Immediate Impact Detection (Priority: HIGH)

#### Task 1.1: Detect at Velocity Peak
```
Current Flow:
  Downswing detected → Track peak → Wait for deceleration → Wait post-impact → Fire

New Flow:
  Downswing detected → Track peak → Peak confirmed (2-3 frames) → Fire immediately
```

**Changes to `LiveSwingDetector.swift`:**
- Detect impact when velocity magnitude drops below 80% of peak (instead of 60%)
- Remove `postImpactDuration` wait - estimate end time as `impactTime + 0.6s`
- Fire `onSwingDetected` immediately when peak is confirmed

#### Task 1.2: Faster Peak Confirmation
- Confirm peak after just 2-3 frames of deceleration (not 0.05-0.3s range)
- At 30fps, 3 frames = 100ms confirmation time
- Total detection latency: ~200-300ms after impact

### Phase 2: Improved Pose Processing (Priority: HIGH)

#### Task 2.1: Background Processing Pipeline
```swift
// Current (slow):
cameraService.onFrameCaptured = { pixelBuffer, timestamp in
    Task { @MainActor in  // ← Waits for main thread
        self?.processFrame(pixelBuffer, timestamp: timestamp)
    }
}

// New (fast):
cameraService.onFrameCaptured = { pixelBuffer, timestamp in
    // Process on dedicated queue
    poseProcessingQueue.async {
        let pose = poseDetector.detectPose(in: pixelBuffer, at: timestamp)
        if let wristY = pose?.wristPosition?.y {
            swingDetector.addPose(timestamp: relativeTime, wristY: wristY)
        }
        // Only update UI on main thread
        DispatchQueue.main.async {
            self?.currentPose = pose
        }
    }
}
```

#### Task 2.2: Adaptive Frame Processing
- Process EVERY frame when swing motion is detected (not every 2nd)
- Return to every-2nd-frame when idle (battery saving)
- Signal from SwingDetector: `isTrackingSwing` flag

### Phase 3: Front Camera Optimization (Priority: MEDIUM)

#### Task 3.1: Smart Wrist Selection
```swift
// Track both wrists, use the one moving faster
var wristPosition: CGPoint? {
    let leftWrist = joints[VNHumanBodyPoseObservation.JointName.leftWrist...]
    let rightWrist = joints[VNHumanBodyPoseObservation.JointName.rightWrist...]

    // If we have history, prefer the wrist with more vertical movement
    // This auto-detects handedness based on which arm is swinging
    return selectActiveWrist(left: leftWrist, right: rightWrist)
}
```

#### Task 3.2: Track Both Wrists in SwingDetector
- Feed both wrist positions to detector
- Detect swing on whichever wrist shows the velocity signature
- Avoids left/right confusion from front camera mirroring

### Phase 4: Velocity Smoothing (Priority: MEDIUM)

#### Task 4.1: Moving Average Filter
```swift
// Smooth velocity over last 3-5 samples
private var velocityBuffer: [Double] = []
private let smoothingWindow = 4

private func smoothedVelocity(_ rawVelocity: Double) -> Double {
    velocityBuffer.append(rawVelocity)
    if velocityBuffer.count > smoothingWindow {
        velocityBuffer.removeFirst()
    }
    return velocityBuffer.reduce(0, +) / Double(velocityBuffer.count)
}
```

#### Task 4.2: Threshold Tuning for Front Camera
- Front camera has different field of view and resolution
- May need different velocity thresholds
- Add configuration: `SwingDetectorConfig` with front/back presets

### Phase 5: Audio Detection Backup (Priority: LOW)

#### Task 5.1: Impact Sound Detection
- Golf ball impact creates distinctive audio spike
- Can detect even when pose detection misses
- Use as confirmation/backup for pose-based detection

```swift
// Monitor audio levels during recording
// Sudden spike (>20dB above baseline) within 200ms of velocity peak = confirmed impact
```

---

## File Changes Summary

### `Services/LiveSwingDetector.swift`
- [ ] Remove post-impact wait delay
- [ ] Fire detection at velocity peak confirmation (2-3 frames)
- [ ] Add dual-wrist tracking support
- [ ] Add velocity smoothing filter
- [ ] Add `isTrackingSwing` flag for adaptive processing
- [ ] Estimate end time instead of waiting

### `Services/LivePoseDetector.swift`
- [ ] Add method to get both wrist positions
- [ ] Add adaptive frame skip (configurable at runtime)
- [ ] Optimize for speed (reduce joints tracked during swing)

### `ViewModels/RecordingViewModel.swift`
- [ ] Move pose processing to background queue
- [ ] Pass both wrists to swing detector
- [ ] Enable adaptive frame processing based on swing state

### `Services/CameraService.swift`
- [ ] Add audio level monitoring (optional)
- [ ] Ensure frame callback doesn't block

---

## Expected Results

| Metric | Current | Target |
|--------|---------|--------|
| Detection latency | 2-3 sec | <500ms |
| False positive rate | Low | Low |
| Detection rate | ~60% | >80% |
| Frame processing | 15/sec | 30/sec (during swing) |

---

## Testing Plan

1. **Latency Test**: Time from actual impact to replay showing
2. **Accuracy Test**: Count detected vs actual swings
3. **Front Camera Test**: Both left and right-handed swings
4. **Continuous Swings**: Multiple swings in quick succession (<3 sec apart)

---

## Sources
- [Golf Swing Cam App Store](https://apps.apple.com/us/app/golf-swing-cam-slow-motion/id6458876528)
- [GolfPose: IEEE Paper on Mobile Pose Estimation](https://ieeexplore.ieee.org/document/9859415/)
- [Pose Estimation for Golf Analysis](https://dev.to/aws-builders/pose-estimation-in-action-visualizing-the-golf-swing-frame-by-frame-2hmg)
- [Golf Swing Sequencing Research](https://www.researchgate.net/publication/358900228_Golf_Swing_Sequencing_using_Computer_Vision)
