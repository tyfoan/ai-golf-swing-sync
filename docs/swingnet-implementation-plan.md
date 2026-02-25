# SwingNet Impact Detection — Implementation Plan

**Created:** 2026-02-25
**Status:** Phase 3 — Testing Complete, Ready for Phase 4 Refinements
**Verified by:** 9 expert agents across 3 research teams

---

## Decision: SwingNet (Primary) + Create ML (Fallback)

| Evidence | Verdict |
|----------|---------|
| SwingNet → CoreML conversion | **SUCCESS** (20.5MB .mlmodel, neuralnetwork format) |
| SwingNet output | Per-frame 9-class probabilities → `argmax` = exact impact frame |
| SwingNet accuracy | 98.4% PCE on GolfDB (published, verified from CVPR paper) |
| Create ML output | 1 label per clip window (needs probability curve workaround) |
| Create ML accuracy | 0% detection rate (bug-related, but architecture fundamentally weaker) |
| Dataset quality | 100/100 health score, 5,207 clips, only 1 bad annotation |
| iOS sync pipeline | Already works — just needs auto-detected `SwingTimeRange` inputs |

### Why SwingNet Over Create ML

| | Create ML Action Classifier | SwingNet |
|---|---|---|
| **Output** | 1 label per 15-frame window | 9 probabilities per frame |
| **Finding impact** | Probability curve workaround (crossover detection) | `argmax(probs[:, 5])` — direct, exact |
| **Proven accuracy** | Unknown (0% in our tests) | **98.4% within ±2 frames** |
| **Thresholds** | 10+ parameters to tune | **Zero** |
| **Detection strategies** | 4 (ImpactDetectionChain) | **One line of code** |
| **Pre-filter** | No-swing dominance (root cause of failure) | **None needed** |

---

## Phase 1: Download Pretrained Weights + Convert ✅ COMPLETE

### Steps
1. Download `swingnet_1800.pth.tar` from GolfDB Google Drive
2. Fix conversion script to load real weights
3. Run conversion: `./venv/bin/python3 convert_swingnet_v2.py --weights swingnet_1800.pth.tar`
4. Validate: compare PyTorch vs CoreML output on `test_video.mp4`

### Go/No-Go
- CoreML output matches PyTorch within ±2 frames on test_video.mp4 → **proceed**
- If not → **fall to Approach B** (Fix Create ML pipeline)

### Output
- `swingnet_full.mlmodel` (~20MB) with real trained weights

---

## Phase 2: Build iOS Detection Pipeline (3 New Swift Files) ✅ COMPLETE

### New files to create

#### 1. `Services/Detection/PersonCropper.swift` (~80 lines)
- Input: `CVPixelBuffer` (full camera frame)
- Output: `CVPixelBuffer` (160×160 person-centered crop)
- Uses `VNDetectHumanRectanglesRequest` for person bounding box
- Adds 20% padding, crops, resizes to 160×160
- Caches last bounding box for frames where detection fails

#### 2. `Services/Detection/SwingNetDetector.swift` (~120 lines)
- Input: `[(CVPixelBuffer, TimeInterval)]` — all frames with timestamps
- Output: `SwingDetectionResult` (impactTime, confidence, startTime, endTime)
- Loads `SwingNet.mlmodel` at init
- For each frame: normalize (ImageNet mean/std), create `MLMultiArray`
- Batch: feed 64 frames at a time (model's sequence length)
- Concatenate outputs → `[total_frames, 9]` probability matrix
- For each event column (0-7): argmax = frame index
- `events[5]` → impact frame → timestamp
- Return `SwingDetectionResult`
- **No thresholds. No heuristics. No pre-filters. Just argmax.**

#### 3. `Services/SwingNetAnalysisRunner.swift` (~70 lines)
- Input: `SwingVideo` + `ModelContext`
- Output: `[SwingMarker]`
- Uses `VideoFrameIterator` to extract ALL frames at 30fps
- `PersonCropper.crop` each frame to 160×160
- `SwingNetDetector.detect(frames)` → `SwingDetectionResult`
- Creates `SwingMarker(from: result)`
- Updates `SwingVideo.hasBeenAnalyzed = true`

### Files to modify

| File | Change |
|------|--------|
| `SingleVideoPlayerView.swift` | Add `SwingNetAnalysisRunner`, re-wire auto-analyze on open, connect `SwingDetectionPanel` |
| `AppLogger.swift` | Re-add `static let detection` category |

### Files that need ZERO changes
- All Models (SyncTypes, SwingMarker, SwingVideo, RecordingTypes, BodyJointMap)
- ComparisonViewModel, ComparisonView, HomeView
- ManualPlaybackSynchronizer, PlaybackSynchronizer
- VideoFrameIterator (used as-is for frame extraction)
- SwingDetectionPanel, AnalysisOverlayView (already built)

### Data flow (identical to previous architecture)
```
SingleVideoPlayerView
  → SwingNetAnalysisRunner.analyze(video:, context:)
    → VideoFrameIterator.forEachFrame (extract ALL frames at 30fps)
    → PersonCropper.crop (160×160 per frame)
    → SwingNetDetector.detect(frames:) → SwingDetectionResult
    → SwingMarker(from: result)
  → SwingVideo.swings updated
  → HomeView reads SwingMarker as SwingTimeRange
  → ComparisonView(video1, video2, swing1: SwingTimeRange, swing2: SwingTimeRange)
  → ComparisonViewModel: syncOffset = swing1.contactTime - swing2.contactTime
  → ManualPlaybackSynchronizer: drift-corrected playback
```

---

## Phase 3: Test on Real Videos ✅ COMPLETE

### Test 1: GolfDB known videos (ground truth) ✅
- **test_video.mp4**: Impact at 4.77s, detected within ±0.15s (0-frame error vs PyTorch)
- **CfCODKOZSg4** (ID 1331): Impact at frame 172, detected within ±0.25s
- **DN8F1bG76Vk** (ID 254): Impact at frame 227, detected within ±0.25s
- **BlDsHA-HNlI** (ID 45): Impact at frame 398, detected within ±0.25s
- **PASS:** All 4 videos detect impact within tolerance

### Test 2: End-to-end sync ✅
- test_video.mp4 (impact ~4.77s) + CfCODKOZSg4 (impact ~5.73s)
- Sync offset calculated: ~-0.96s (matches expected within 0.5s)
- **PASS:** Sync offset correct

### Test 3: User-recorded video
- Deferred — requires physical device with camera

### Test 4: Edge cases ✅
- Empty frames → returns no detection (impactTime=nil, confidence=0)
- Short video (10 blank frames, <64) → handled gracefully, no crash
- PersonCropper → produces valid 160×160 BGRA buffers
- **PASS:** All edge cases handled

---

## Phase 4: Refinements

| Enhancement | Effort | Impact |
|-------------|:------:|--------|
| FP16 quantization (20MB → ~10MB) | 1 hour | Halves model size |
| Wrist y-minimum refinement | 2 hours | ±100ms → ±33ms accuracy |
| Audio 2-4kHz spike confirmation | 3 hours | Sub-frame precision |
| Multi-swing detection in one video | 2 hours | Handles compilation videos |
| Real-time recording hint (simplified) | 4 hours | Show "swing detected" during recording |

---

## Fallback: If SwingNet CoreML Fails

```bash
# Restore Create ML pipeline from git
git checkout 1251854^ -- \
  golf-sync-swing/Services/ActionClassifierDetector.swift \
  golf-sync-swing/Services/SwingDetectorProtocol.swift \
  golf-sync-swing/Services/SwingAutoDetectionRunner.swift \
  golf-sync-swing/Services/VideoSyncEngine.swift \
  golf-sync-swing/Services/Detection/

# Retrain with 10-frame clips (77% purity vs 52% at 15-frame)
cd ml-training
./venv/bin/python3 extract_5class_dataset.py \
  --extract --from-youtube --stats --clean --clip-frames 10

# Train in Create ML app: 500+ iterations
# Disable no-swing dominance pre-filter in ActionClassifierDetector
# Lower all thresholds by 50%
```

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|:---:|:---:|------------|
| Pretrained weights unavailable | Low | Critical | Retrain SwingNet from scratch (training code exists) |
| CoreML output numerical drift | Low | High | Test on 10 known videos; BiLSTM on CPU is deterministic |
| PersonCropper fails on user videos | Medium | Medium | Center-crop fallback; 30% margin; last-known bbox cache |
| Model too large (20MB) | Low | Medium | FP16 → ~10MB; INT8 → ~5MB |
| Fails on amateur swings (pro-only training) | Medium | High | Collect user data; fallback to manual mode |
| 64-frame batch limit misses long swings | Low | Low | Overlapping 64-frame chunks, stitch results |

---

## Timeline

| Phase | What | Time |
|-------|------|:----:|
| 1. Weights + conversion | Download, convert, validate | 30 min |
| 2. iOS pipeline (3 files) | SwingNetDetector, PersonCropper, AnalysisRunner | 4 hrs |
| 3. Testing | 4 test categories | 2 hrs |
| 4. Refinement | Quantization, wrist, audio | 4-6 hrs |
| **Total to working app** | | **~7 hrs** |
| **Total with refinements** | | **~12 hrs** |

---

## Appendix: Verified Data Points

### GolfDB Dataset
- 1,400 annotations, 758 normal-speed, 580 YouTube videos (all downloaded)
- Only 1 bad annotation (ID 677, non-monotonic events)
- Phase durations (normal-speed): backswing=13.5f, downswing=7.9f, follow_through=21.4f

### Phase Purity (15-frame vs 10-frame clips)
| Class | 15-frame | 10-frame |
|-------|:--------:|:--------:|
| backswing | 84% | 99% |
| downswing | 52% | 77% |
| impact | 53% | 90% |
| follow_through | 99% | 100% |

### SwingNet Architecture
- MobileNetV2 (first 19 layers) + BiLSTM (1280→256, bidirectional) + Linear (512→9)
- 5.38M parameters, input [1, 64, 3, 160, 160], output [64, 9]
- 8 events: address, toe-up, mid-backswing, top, mid-downswing, impact, mid-follow-through, finish

### CoreML Conversion Results
- Full model: 20.5 MB (.mlmodel, neuralnetwork format) — **SUCCESS**
- CNN only: 8.4 MB — SUCCESS
- LSTM only: 12.0 MB — SUCCESS
- mlprogram format: fails on Python 3.14 (works on 3.11-3.12)
