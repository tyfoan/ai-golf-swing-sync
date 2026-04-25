# Golf Swing Detection & Video Sync — SOTA Research Report

> **Date**: February 15, 2026
> **Team**: ML Engineer, Biomechanics Engineer, Apple ML Engineer, Video Sync Engineer, iOS Architect
> **Scope**: SOTA golf swing detection, impact point detection, video synchronization, Create ML capabilities

---

## Executive Summary

Impact detection in golf swing video is **effectively a solved problem** at the accuracy level needed for video sync. GolfDB's SwingNet achieves **98.4% impact detection accuracy** (highest of all 8 swing events). Our current Create ML Action Classifier approach with probability curve analysis is architecturally sound and aligns with SOTA. The biggest opportunities are: (1) expanding to 8 phases with more training data, (2) adding audio-based impact confirmation, and (3) adopting iOS 26's `AVPlaybackCoordinationMedium` for drift-free synchronized playback. A ±33ms sync accuracy (1 frame at 30fps) is **perceptually sufficient** — humans cannot reliably detect sync errors below ~40ms in side-by-side video.

---

## 1. SOTA Landscape

### GolfDB Dataset (CVPR Workshop 2019)
- **1,400 videos**, 390k+ frames, 8 labeled swing events
- Events: Address, Toe-up, Mid-backswing, Top, Mid-downswing, **Impact**, Mid-follow-through, Finish
- SwingNet baseline: **76.1% overall** (91.8% excluding Address/Finish), **98.4% impact PCE**
- Impact is the EASIEST event to detect — clear visual signal when clubhead is nearest ball
- Address (31.7%) and Finish (26.5%) are hardest due to subjective labeling

### Key Models & Benchmarks

| Method | Year | Architecture | Impact Acc | Params | Mobile? |
|--------|------|-------------|-----------|--------|---------|
| SwingNet | 2019 | MobileNetV2 + BiLSTM | 98.4% PCE | 5.38M | Yes |
| Fine-tuned SwingNet | 2025 | Same + tuning | ~98%+ | ~5.4M | Yes |
| Create ML Action Clf | 2020 | Pose + proprietary | Phase-level | <500KB | **Yes (native)** |
| MoViNet-A0 | 2021 | NAS 3D CNN | N/A (general) | ~3M | Yes |
| MLPFormer | 2023 | Attention + Transformer | Improved | Medium | Borderline |
| T-DEED | 2024 | Transformer enc-dec | SOTA sports | 16.4M | No |

### Recent Advances (2023-2025)
- **CaddieSet** (CVPR 2025): 924 shots with ball trajectory → swing video predicts ball outcome
- **MLPFormer** (IJCNN 2023): Gaussian soft labels for temporal event boundaries
- **T-DEED** (CVPR 2024): Frame-level precise event spotting, best for fine-grained detection
- **GolfPose** (ICPR 2024): Domain adaptation from regular → golf-specific poses

---

## 2. Biomechanics: What Signals Detect Impact

### Swing Phase Timing
| Phase | Duration | Frames @30fps |
|-------|----------|---------------|
| Backswing | 750-900ms | 22-27 |
| Top transition | ~150ms | ~4-5 |
| **Downswing** | **233-300ms** | **7-9** |
| **Impact (contact)** | **~0.5ms** | **<1** |
| Follow-through | 300-400ms | 9-12 |

The 3:1 backswing:downswing ratio is consistent across skill levels (PGA: 847ms:264ms).

### Impact Detection Signal Reliability (Ranked)

**Tier 1 — Most Reliable for iOS:**
1. **ML Phase Classification** (P(downswing)→P(follow_through) transition) — works at 30fps, robust
2. **Wrist Position Trajectory** — lead wrist reaches lowest y-position at impact, detectable at 30fps
3. **Hip/Torso Rotation Velocity** — hips peak BEFORE impact, torso peaks AT impact (kinematic sequence)

**Tier 2 — Supplementary:**
4. **Audio Signature** — impact peak at 2.75-4 kHz, sub-frame precision (~1ms), unreliable outdoors
5. **Optical Flow Magnitude** — motion spike at impact, affected by motion blur

**Tier 3 — Unreliable at Standard FPS:**
6. **Ball Detection** — too small (42.7mm), often occluded
7. **Club Head Tracking** — moves 29" between 30fps frames at 100mph, impossible without 240fps+

### Frame Rate Impact
| FPS | Impact Precision | Practical Use |
|-----|-----------------|---------------|
| 30fps | ±33ms (sufficient for sync) | Standard recording |
| 60fps | ±17ms (better phase boundaries) | **Recommended capture** |
| 120fps | ±8ms (smooth slo-mo) | Premium slow motion |
| 240fps | ±4ms (club visible) | Not needed for detection |

**Key insight**: At 30fps, the downswing spans only 7-9 frames. Impact can be localized to ±1 frame (±33ms) using pose analysis — sufficient for video sync. Humans cannot detect sync errors below ~40ms.

---

## 3. Create ML: Capabilities & Workflow

### Architecture
Create ML Action Classifier uses a **two-stage pipeline**:
1. **Vision Pose Extraction**: `VNDetectHumanBodyPoseRequest` → 18 landmarks × (x, y, confidence) per frame
2. **Temporal Classification**: Sliding window of pose sequences → clip-level class prediction

**Critical limitation**: Create ML does **clip-level classification only** — it assigns ONE label to the entire prediction window. It cannot pinpoint the exact impact frame within the window. Our probability curve analysis is the correct workaround.

### Model Characteristics
- **Size**: 100-500 KB (extremely lightweight — pose features, not pixels)
- **Inference**: <20ms per prediction (Neural Engine optimized)
- **Training data**: 50-100 videos per class minimum
- **Augmentation**: Horizontal flip built-in (right↔left handed golfer)

### Create ML Components (Most Interesting Path Forward)
Composable pipeline building blocks:
- `HumanBodyPoseExtractor` → `SlidingWindowTransformer` → custom classifier
- `VideoReader` provides `AsyncSequence` of frames
- Allows custom temporal logic while staying in Apple's ecosystem
- Could enable per-frame confidence scoring (beyond clip-level)

### Training Workflow for Golf
```
1. Collect: 100+ videos/class + GolfDB conversion (1400 videos)
2. Label: Folder-based or JSON annotation (start_time, end_time, label)
3. Train: Create ML App → Action Classifier → 2.0s action duration → flip augmentation
4. Export: .mlmodel → copy to source dir → Xcode auto-compiles
5. Integrate: Update PhaseClassifier if interface changes
6. Iterate: Analyze confusion matrix, add data for weak classes
```

### GolfDB → Create ML Conversion
Map 8 GolfDB phases to our classes:
- Address, Takeaway → `no_swing`
- Backswing, Top → `backswing`
- Downswing, Impact → `downswing`
- Follow-through, Finish → `follow_through`

Alternative (8-class model): Keep all 8 phases for finer temporal resolution.

### Create ML vs Custom PyTorch + CoreML

| Aspect | Create ML | Custom PyTorch |
|--------|-----------|----------------|
| Training effort | Minutes-hours | Days-weeks |
| Temporal precision | Clip-level | Frame-level possible |
| Model size | 100-500 KB | 5-100 MB |
| Impact detection | Indirect (probability curves) | Direct frame-level |
| When to use | Phase classification (our case) | If probability curves prove insufficient |

---

## 4. Video Sync: Algorithms & Recommendations

### Current Approach
```swift
syncOffset = swing1.contactTime - swing2.contactTime
```
Simple one-time subtraction. No refinement. Drift corrected at 40ms threshold during playback.

### Sync Algorithm Options

| Approach | Complexity | Accuracy | When to Use |
|----------|-----------|----------|-------------|
| **Direct offset from classifier** (current) | O(1) | ±1-2 frames | Impact-only sync |
| **Cross-correlation on wrist velocity** | O(n) | ±0.5 frames | Refined impact sync |
| **Per-phase DTW on pose trajectories** | O(n×m)/phase | Sub-frame | Full swing alignment |
| **Non-linear warping from DTW path** | O(n×m) total | Sub-frame | Tempo-normalized playback |

### AVPlaybackCoordinationMedium (iOS 26+ — MAJOR FINDING)
```swift
let coordinationMedium = AVPlaybackCoordinationMedium()
try player1.playbackCoordinator.coordinate(using: coordinationMedium)
try player2.playbackCoordinator.coordinate(using: coordinationMedium)
```
- **~3 lines of code** to synchronize multiple AVPlayers
- Automatically handles: rate changes, time jumps, stalling, startup sync
- Handles different frame rates automatically
- **Eliminates need for manual drift correction**
- Available on our target (iOS 26.1)

### Perceptual Thresholds
| Sync Error | At 30fps | Perception |
|-----------|----------|------------|
| ±8ms | <1 frame | Imperceptible |
| ±33ms | ±1 frame | Threshold of detection |
| ±67ms | ±2 frames | Clearly noticeable |
| ±100ms | ±3 frames | Distracting |

**Target**: ±1 frame at source FPS. At impact where club moves ~1.5m in 33ms, even 1-frame error is visible. During slower phases, ±2-3 frames is acceptable.

### Commercial App Landscape
- **Most consumer golf apps do NOT auto-detect impact** — this is a differentiator
- **Onform**: Auto-sync at impact (premium), most advanced
- **Swing Profile**: AI-powered auto-sync (patent-pending)
- **V1 Golf, Hudl Technique**: Manual sync only
- **Golf Swing Cam**: Manual alignment

---

## 5. Current Codebase Gap Analysis

### What's Working Well
- **ImpactDetectionChain** (Chain of Responsibility) — excellent extensible design
- **PoseFrameBuffer** — thread-safe ring buffer with NSLock
- **FrameProcessingGate** — smart backpressure on camera frames
- **Dependency injection** throughout detection pipeline
- **Probability curve analysis** — pragmatic approach that works

### Critical Gaps

| Gap | Current | SOTA | Impact | Priority |
|-----|---------|------|--------|----------|
| Phase granularity | 4 classes | 8 phases (GolfDB) | Limits impact precision | P0 |
| Audio detection | `audioConfirmed` field exists, always false | Sub-frame precision possible | 5-10x sync accuracy improvement | P0 |
| Temporal resolution | 60-frame window, stride=8 (~267ms between predictions) | Per-frame classification | Limits to ~100-200ms accuracy | P1 |
| Playback sync | Manual dual-AVPlayer + 40ms drift correction | AVPlaybackCoordinationMedium | Eliminates drift, simplifies code | P1 |
| Wrist velocity analysis | Not implemented | Lead wrist y-min = impact | ±1 frame refinement | P1 |
| 3D pose | 2D only (VNDetectHumanBodyPoseRequest) | 3D available (iOS 17+) | Better angle independence | P2 |
| Cross-correlation refinement | Removed in b26a2b1 cleanup | Refine offset ±5 frames around detected impact | Sub-frame sync | P2 |
| High FPS support | Hardcoded 30fps | 60-120fps capture | Better UX + detection precision | P2 |

### Technical Debt
- `AutoDetectModel.swift` still references removed SwingNet (dead code)
- `SwingDetectionResult.topOfBackswingTime` always nil (never populated)
- `PoseExtractor` creates new `VNImageRequestHandler` per frame (minor inefficiency)
- `stepFrame` uses hardcoded 1/30s (ignores actual video FPS)
- No unit tests for impact detection strategies

---

## 6. Recommended Approach

### Strategy: Incremental Enhancement of Create ML Pipeline

The current Create ML pose-based approach is the RIGHT architecture. Don't switch to a fundamentally different model (SwingNet, MoViNet) — instead, enhance what exists.

**Rationale**:
- Create ML models are 100-500 KB vs 15-100 MB for custom models
- Native iOS integration, Neural Engine optimized, no conversion overhead
- Probability curve analysis already compensates for clip-level limitation
- 98.4% impact PCE on GolfDB shows the problem is tractable at our accuracy needs
- Our ±33ms target is achievable with the current architecture + improvements

### Phase 1: Quick Wins (1-2 weeks)

1. **Adopt AVPlaybackCoordinationMedium** — replace manual drift correction with native iOS 26 multi-player sync. ~3 lines of code, eliminates entire drift correction system.

2. **Expand training data via GolfDB** — convert 1400 GolfDB videos to Create ML format, retrain model. Map 8 phases → 4 classes (or experiment with 8 classes).

3. **Clean up technical debt** — remove `AutoDetectModel.swingNet` dead code, remove or implement `topOfBackswingTime`, fix hardcoded FPS in `stepFrame`.

### Phase 2: Accuracy Enhancement (2-4 weeks)

4. **Audio impact detection** — implement spectral analysis on video audio track. Detect energy spike in 2-4 kHz band. Use as confirmation signal alongside visual classifier. Could improve sync accuracy from ~100ms to ~10ms.

5. **Wrist velocity refinement** — track lead wrist y-position from existing PoseExtractor data. Minimum y-position = impact frame. Refine classifier output by ±1 frame.

6. **Cross-correlation refinement** — after ML-based impact detection, cross-correlate wrist velocity curves in ±5 frame window around detected impact for sub-frame precision.

### Phase 3: Model Improvement (4-8 weeks)

7. **8-phase model** — retrain Create ML Action Classifier with full GolfDB 8-phase labels. Explicit "impact" class eliminates interpolation guesswork.

8. **Create ML Components pipeline** — build custom pipeline with `HumanBodyPoseExtractor` → `SlidingWindowTransformer` → custom classifier for finer temporal control.

9. **60fps camera capture** — support higher frame rate recording for better phase boundaries and smoother slow-motion.

### Phase 4: Future / Premium (8+ weeks)

10. **Per-phase DTW alignment** — segment swings into phases, DTW-align each independently. Premium "tempo-normalized" comparison mode.

11. **3D pose estimation** — upgrade to `VNDetectHumanBodyPose3DRequest` for angle-independent detection.

12. **SwingNet as secondary validator** — train on GolfDB, convert to CoreML via coremltools, use as offline validation alongside Create ML classifier.

---

## 7. Training Data Strategy

### Sources
1. **GolfDB** (1,400 videos) — primary dataset, 8-phase annotations, free
2. **CaddieSet** (924 shots) — newer dataset with ball trajectory data
3. **Custom recordings** — fill gaps in camera angles, lighting, body types
4. **YouTube golf lessons** — additional training data (check licensing)

### Labeling Workflow
1. Convert GolfDB annotations to Create ML JSON format (Python script)
2. For custom recordings: use Create ML App's annotation interface
3. Target: 100+ videos per class minimum
4. Apply horizontal flip augmentation (right↔left handed)
5. Ensure consistent 30fps across all training data

### Class Mapping Options

**Option A — Enhanced 4-class (conservative):**
- backswing (GolfDB: takeaway + backswing + top)
- downswing (GolfDB: downswing + impact)
- follow_through (GolfDB: follow-through + finish)
- no_swing (GolfDB: address + non-swing footage)

**Option B — 8-class (ambitious, recommended):**
- address, takeaway, backswing, top, downswing, impact, follow_through, finish
- Explicit impact class = direct detection, no interpolation needed
- Higher data requirements per class

---

## 8. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| 8-class model insufficient accuracy | Medium | High | Fall back to 4-class + probability curves |
| Audio detection unreliable outdoors | High | Medium | Use as supplementary signal only, not primary |
| GolfDB data insufficient diversity | Medium | Medium | Supplement with custom recordings |
| AVPlaybackCoordinationMedium limitations | Low | Medium | Keep manual sync as fallback |
| Create ML temporal resolution ceiling | Medium | High | Move to Create ML Components or custom PyTorch |
| Different camera angles degrade accuracy | Medium | Medium | 3D pose estimation (Phase 4), diverse training data |

---

## 9. Key Takeaways

1. **Impact detection is the easiest swing event to detect** (98.4% PCE on GolfDB). Our problem is tractable.

2. **±33ms sync accuracy is perceptually sufficient**. Humans can't reliably detect sync errors below ~40ms.

3. **Our current architecture is sound** — Create ML pose-based classifier + probability curve analysis is the right approach for iOS.

4. **Biggest improvement opportunity is audio** — the `audioConfirmed` field exists but was never implemented. Sub-frame precision possible.

5. **AVPlaybackCoordinationMedium is a game-changer** — native iOS 26 multi-player sync eliminates drift correction complexity.

6. **Don't switch architectures** — enhance incrementally. Create ML → more data → audio → 8 phases → DTW.

7. **Most golf apps don't auto-detect impact** — this remains a differentiating feature.

---

## Sources & References

- McNally et al., "GolfDB: A Video Database for Golf Swing Sequencing" (CVPR Workshop 2019)
- Jung et al., "CaddieSet" (CVPR Workshop 2025)
- Zhang et al., "Multi-Scale Temporal MLPFormer" (IJCNN 2023)
- Xarles et al., "T-DEED: Temporal-Discriminability Enhancer Encoder-Decoder" (CVPR 2024)
- Cuturi & Blondel, "Soft-DTW: Differentiable Dynamic Time Warping" (ICML 2017)
- Apple, "Detecting Human Body Poses in Images" (Vision Framework Documentation)
- Apple, "Creating an Action Classifier Model" (Create ML Documentation)
- Apple, "WWDC 2022 — Compose Advanced Models with Create ML Components"
- Apple, "WWDC 2025 — AVPlaybackCoordinationMedium" (AVFoundation)
- TPI, "Measuring Golf Swing Timing from Video"
- PMC, "Golf Swing Biomechanics Systematic Review" (2022)
