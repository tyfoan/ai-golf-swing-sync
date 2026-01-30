# Milestone 2: Auto-Detection & Sync

**Goal**: Automatic swing phase detection and impact sync

**Status**: Not Started

**Depends on**: Milestone 1

---

## Tasks

### 2.1 Vision Framework Integration
- [ ] Create `SwingDetector` service
- [ ] Set up VNDetectHumanBodyPoseRequest
- [ ] Process video frames at intervals (e.g., every 3rd frame for speed)
- [ ] Extract body joint positions per frame
- [ ] Handle async processing with progress callback

### 2.2 Phase Detection Algorithm
- [ ] Define `SwingPhase` model with confidence scores
- [ ] Implement address detection (stable stance, club at rest)
- [ ] Implement backswing detection (club moving up/back)
- [ ] Implement top-of-swing detection (hands highest point)
- [ ] Implement downswing detection (club moving down)
- [ ] Implement impact detection (hands lowest + fastest motion)
- [ ] Implement follow-through detection (club past ball)

### 2.3 Impact Frame Detection (Priority)
- [ ] Focus on impact as primary sync point
- [ ] Detect rapid velocity change in wrist joints
- [ ] Cross-reference with hip rotation speed
- [ ] Calculate confidence score for impact frame
- [ ] Allow manual correction if auto-detect is wrong

### 2.4 Phase Timeline UI
- [ ] Create `PhaseMarkerView` for timeline
- [ ] Show colored markers for each phase
- [ ] Tap marker to jump to that timestamp
- [ ] Show confidence indicator (solid vs dotted line)

### 2.5 Auto-Sync Engine
- [ ] Create `VideoSyncEngine` service
- [ ] Input: two SwingVideo objects with detected phases
- [ ] Calculate offset to align impact frames
- [ ] Apply offset to ComparisonSession
- [ ] Show "synced at impact" indicator

### 2.6 Processing UX
- [ ] Show "Analyzing swing..." with progress
- [ ] Cache detection results in SwingVideo model
- [ ] Re-detect option if user thinks it's wrong
- [ ] Graceful fallback if detection fails

---

## Technical Notes

### Pose Detection Points
```
Key joints for golf swing:
- rightWrist / leftWrist (club position proxy)
- rightElbow / leftElbow (arm angles)
- rightShoulder / leftShoulder (rotation)
- rightHip / leftHip (rotation, weight shift)
- nose (head position, staying down)
```

### Impact Detection Heuristics
```
Impact frame characteristics:
1. Wrist velocity peaks then rapidly decelerates
2. Hands at lowest vertical position
3. Hip rotation ~45° open to target
4. Weight shifted to front foot (hip position)
```

### Performance Targets
- Process 10-second 60fps video in <5 seconds
- Process 10-second 240fps video in <15 seconds
- Test on iPhone 12 as baseline device

---

## Definition of Done
- [ ] Swing phases detected automatically on import
- [ ] Phase markers visible on timeline
- [ ] Impact frame detected with >90% accuracy
- [ ] Two videos auto-sync at impact with one tap
- [ ] Processing time <5 seconds for typical video
- [ ] Manual override available for incorrect detections
