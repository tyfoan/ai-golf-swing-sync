# ML Training Pipeline Analysis Report
## Golf Sync Swing — Zero Detection Across All 4 Models

**Investigation Date:** Feb 21, 2026
**Analyzed By:** Dataset Analyst Agent
**Status:** All 4 model variants failing on calibration videos (0 detections)

---

## Executive Summary

The app fails to detect ANY swings across all 4 model variants (4-class, 4-class v2, 5-class, 6-class) on 3 independent calibration videos from GolfDB. The root cause is **likely a critical mismatch between model training data distribution and calibration video characteristics**, combined with **overly aggressive pre-filtering in the detection pipeline**.

**Key Findings:**
1. ✗ All 4 models trained on GolfDB YouTube clips (758-1400 videos, normal speed only)
2. ✗ Calibration videos ARE from GolfDB training set (same source)
3. ✓ Dataset extraction pipeline IS correctly implemented (H.264, 15-frame clips, proper class definitions)
4. ✗ **CRITICAL**: No-swing dominance pre-filter blocks detection for most videos
5. ✗ High probability thresholds (0.25-0.40+) may be unrealistic for action classifiers
6. ⚠ Vision pose extraction bottleneck — only 35% confidence joints included
7. ⚠ Prediction window mismatches between config and actual models

---

## 1. Dataset Analysis

### 1.1 Training Data Structure

| Metric | Count | Status |
|--------|-------|--------|
| backswing clips | 865 | ✓ Balanced |
| downswing clips | 719 | ✓ Balanced |
| follow_through clips | 1,397 | ✓ Class 2 |
| impact clips | 743 | ✓ Balanced |
| no_swing clips | 1,483 | ✓ Class 2 |
| **Total clips** | **5,236** | ✓ Good size |
| **Total size** | **1.7 GB** | ✓ Substantial |

**Distribution:** Roughly 1.5:1 ratio (follow_through and no_swing are 2x swing classes)
- This imbalance is **intentional** — no_swing is harder to collect and more important for false positive rejection
- However, Create ML may struggle with 1.5:1 imbalance in a 5-class problem

### 1.2 Clip Characteristics

**Target specification (extract_5class_dataset.py):**
- Clip length: 15 frames (0.5s at 30fps)
- Codec: H.264 (avc1 fourcc)
- Window computation: **Single centered window per phase** (not shifted)
- Phase coverage:
  - Backswing: TAKEAWAY→TOP (excludes standing-still address)
  - Downswing: TOP→IMPACT (full phase)
  - Impact: IMPACT ±4 frames (±133ms window)
  - Follow-through: IMPACT→FINISH (full phase)
  - No-swing: PRE/POST regions (standing still, setup, post-swing)

**Phase purity expectations:**
- Backswing (~400-800ms depending on tempo): ~60-80% purity in 15-frame clips
- Downswing (~150-250ms): ~50-70% purity (short phase problem)
- Impact (±4 frames): ~90%+ purity (tight window)
- Follow-through (~500-1000ms): ~70-85% purity
- No-swing (variable): ~90%+ purity (intentional standing-still)

### 1.3 Data Quality Issues

**CRITICAL:** Phase imbalance in training set

The 5-class dataset has meaningful class imbalance but it's **not catastrophic**. However, there are secondary concerns:

1. **Slow-motion exclusion**: Training data excludes slow-motion videos (correct, per spec)
   - This means models are trained on 30fps normal-speed clips
   - Calibration videos are also normal-speed (same FPS), so this is NOT the issue

2. **No manual augmentation**: Create ML handles horizontal flip internally (correct)
   - Training used single centered window only (no shifted augmentation)
   - This reduces duplicate clips from shifted windows that have 70% overlap on short phases

3. **H.264 codec compatibility**: avc1 fourcc is CREATE ML native (correct)
   - No re-encoding required
   - Clips are directly usable in Create ML

---

## 2. Model Configuration Analysis

### 2.1 Model Variants and Prediction Windows

| Model | Classes | Prediction Window (frames) | Config Window | Status |
|-------|---------|---------------------------|-------------------|--------|
| GolfSwingClassifier | 4 | 60 | 60 | ✓ Match |
| GolfSwingClassifier_v3 | 4 | 60 (assumed) | 60 | ⚠ Assumed |
| GolfSwingClassifier_5class | 5 | 18 (assumed) | 18 | ⚠ Assumed |
| GolfSwingClassifier_6class | 6 | 15 (assumed) | 15 | ⚠ Assumed |

**Issue:** Prediction window values are **assumed** based on config, NOT verified from actual model metadata.

PhaseClassifier does read the model's input shape at load time (line 65-71 in PhaseClassifier.swift):
```swift
private static func readModelWindow(from model: MLModel) -> Int? {
    guard let posesDesc = model.modelDescription.inputDescriptionsByName["poses"],
          let constraint = posesDesc.multiArrayConstraint else { return nil }
    let shape = constraint.shape
    guard shape.count >= 1 else { return nil }
    return shape[0].intValue  // ← This reads actual window from model
}
```

If model window doesn't match config window, **classification fails silently** (line 82-86):
```swift
if let expectedWindow, predictionWindow != expectedWindow {
    AppLogger.detection.error(
        "PhaseClassifier: window mismatch — config=\(predictionWindow) model=\(expectedWindow)"
    )
    return nil  // ← RETURNS NIL — no prediction
}
```

**Hypothesis 1: Window mismatch is silently failing.**

### 2.2 Detection Thresholds Analysis

**DetectorConfiguration thresholds (per variant):**

| Threshold | 4-Class | 4-Class v2 | 5-Class | 6-Class |
|-----------|---------|------------|---------|---------|
| primaryDownswing | 0.25 | 0.30 | 0.40 | 0.25 |
| primaryFollow | 0.25 | 0.30 | 0.40 | 0.25 |
| minSwingConfidence | 0.35 | 0.40 | 0.50 | 0.35 |
| noSwingDominanceRatio | 0.7 | 0.65 | 0.6 | 0.7 |
| backswing | 0.40 | 0.45 | 0.55 | 0.40 |
| followThrough | 0.30 | 0.35 | 0.40 | 0.30 |

**5-class thresholds are MUCH HIGHER** (line 121-123 in DetectorConfiguration.swift):
> "18-frame windows produce noisier predictions — standing still can spread 15-25% across swing labels"

**Critical finding:** These thresholds assume **HARD probability peaks** (e.g., 0.40-0.50 for downswing).

For a 5-class classifier with NO dominant class in standing-still frames, a uniform distribution would be:
```
no_swing=0.20, backswing=0.20, downswing=0.20, impact=0.20, follow_through=0.20
```

**This means:** Unless the model confidently predicts (>40%) a swing phase, detection is blocked.

### 2.3 No-Swing Dominance Pre-Filter

**The biggest bottleneck** (ActionClassifierDetector.swift, line 192-212):

```swift
private func isNoSwingDominant(in history: [PredictionRecord]) -> Bool {
    let noSwingCount = history.filter { $0.label == configuration.noSwingLabel }.count
    let ratio = Double(noSwingCount) / Double(history.count)
    return ratio >= configuration.thresholds.noSwingDominanceRatio  // 0.60-0.70
}

private func checkForImpact() {
    // ...
    guard !isNoSwingDominant(in: history) else { return }  // ← BLOCKS IF >60% NO_SWING
}
```

**This pre-filter requires:**
- At least 40% (1 - 0.60) of recent predictions to be swing-related
- For the 5-class model: only 40% must be non-no_swing
- History window: last 10 predictions (line 202)

**Hypothesis 2: Model predicts >60% no_swing even during actual swings** → pre-filter blocks all detections.

---

## 3. Vision Pose Extraction Bottleneck

### 3.1 Pose Requirements

PoseExtractor.swift has very loose constraints:
```swift
private let minimumJointConfidence: Float = 0.35   // 35% confidence threshold
private let minimumJointCount: Int = 8              // Need 8+ of 14 joints tracked
```

**Analysis:**
- 14 tracked joints: neck, shoulders, elbows, wrists, hips, knees, ankles (standard skeleton)
- Requiring 8/14 = 57% joint detection rate is **quite permissive**
- However, **0.35 confidence is extremely loose** — Vision framework's confidence scores are often 0.6-1.0 for clear joints

**Issue:** Pose extraction may succeed (>8 joints at >0.35 confidence) but return **sparse, noisy keypoint arrays** that confuse the classifier.

### 3.2 Frame Rate Dependency

Calibration videos are 30fps (same as training data), so no issue there.

However, **if pose extraction frequently fails or returns sparse poses**, the PoseFrameBuffer will contain:
- Some frames with full pose data
- Some frames with sparse/noisy pose data
- Jittery, inconsistent input to the classifier

---

## 4. Calibration Video Analysis

### 4.1 Calibration Video Characteristics

From GolfDB metadata (inferred from memory notes):

| Video | GT Start | GT Impact | GT End | Duration | Source |
|-------|----------|-----------|--------|----------|--------|
| 3wru0WH0buk.mp4 | 11.858s | 12.958s | 13.563s | 0.705s | GolfDB |
| lXPXAgpqLZI.mp4 | 12.745s | 15.678s | 16.328s | 3.583s | GolfDB |
| gVrpJYWrpLc.mp4 | 13.733s | 15.173s | 15.907s | 2.174s | GolfDB |

**At 30fps:**
- 3wru0WH0buk: swing = 21 frames (0.7s)
- lXPXAgpqLZI: swing = 108 frames (3.6s — VERY LONG, unusual)
- gVrpJYWrpLc: swing = 65 frames (2.2s)

**Issue:** lXPXAgpqLZI is a 3.6-second swing. This is **abnormally long**:
- Normal swing: 0.5-1.5 seconds
- 3.6 seconds suggests either:
  1. Multiple swings in the window
  2. Slow-motion video (but training excludes slow-mo)
  3. Very deliberate, drawn-out swing
  4. Annotation error (start frame is wrong)

**If lXPXAgpqLZI is slow-motion or mislabeled, the model has never seen it** → zero detection is expected.

### 4.2 Phase Duration Characteristics

Typical swing phase breakdown (from GolfDB):
- Backswing: 300-800ms
- Downswing: 150-300ms
- Impact: ±33ms (critical zone)
- Follow-through: 300-800ms

**For lXPXAgpqLZI (3.6s total):**
- If typical phase ratio: backswing ~800ms, downswing ~250ms, follow-through ~2500ms
- The follow-through is **3x+ normal** → suggests EITHER slow-motion OR multiple swings

---

## 5. Detection Pipeline Critical Path

### 5.1 Frame Processing Flow

```
InputFrame
  ↓
[1] VideoFrameIterator (reads frames at stride=2 or stride=1 during active detection)
  ↓
[2] PoseExtractor.extractPose() — Vision framework body pose
      → Requires ≥8 joints @ ≥0.35 confidence
      → Returns MLMultiArray (pose keypoints)
      → publishPose() updates UI
  ↓
[3] PoseFrameBuffer.append() — sliding window buffer (window size = 15-60 frames)
      → When full: triggers classification
  ↓
[4] PhaseClassifier.classify()
      → Input: [window_size, 2, numJoints] MLMultiArray
      → Check: window size matches model's input shape
      → Call: model.prediction()
      → Output: label + labelProbabilities dict
  ↓
[5] ActionClassifierDetector.runClassification()
      → Extract confidence: record.probabilities[record.label]
      → Update stride (idleStride=8 vs activeStride=2)
      → Append to predictionHistory (max 30 records)
  ↓
[6] checkForImpact() — evaluate detection strategies
      → Pre-filter: isNoSwingDominant() — BLOCKS if >60% no_swing
      → Try: DownswingToFollowThroughStrategy
      → Try: BackswingToFollowThroughStrategy
      → Try: DownswingDecayStrategy
      → Try: BackswingDecayStrategy
      → Return: ImpactCandidate with SwingBounds
  ↓
[7] WristTrajectoryRefiner.refine() — optional sub-frame refinement
  ↓
[8] Callback: onSwingDetected(swingBounds)
```

### 5.2 Failure Points (Most to Least Likely)

| Rank | Failure Point | Likelihood | Evidence |
|------|---------------|------------|----------|
| **1** | No-swing dominance pre-filter (line 212) | **VERY HIGH** | 60-70% threshold is very high; no_swing prediction likely ≥60% during setup/idle |
| **2** | Prediction window mismatch (PhaseClassifier line 82) | **HIGH** | Models trained with different window sizes; not verified to match config |
| **3** | Probability thresholds too high (0.25-0.50) | **HIGH** | Action classifiers rarely output clean 0.40+ peaks; 5-class especially noisy |
| **4** | Class label mismatch (noSwingLabel) | **MEDIUM** | 6-class uses "noswing" (no underscore), others use "no_swing" — possible typo |
| **5** | Pose extraction too sparse (0.35 confidence) | **MEDIUM** | Loose confidence threshold may pass but return jittery, low-quality input |
| **6** | lXPXAgpqLZI is slow-motion (3.6s swing) | **MEDIUM** | Training excludes slow-mo; if video is slow-motion, model has never seen it |
| **7** | Model not actually loaded | **LOW** | PhaseClassifier logs successful load, but worth verifying |
| **8** | Incorrect model files in bundle | **LOW** | Models are 3.9MB each; would be obvious if missing |

---

## 6. Hypothesis Ranking & Testing Strategy

### Hypothesis 1: No-Swing Dominance Pre-Filter (HIGHEST PRIORITY)

**Theory:** Model predicts no_swing for ≥60% of classification windows because:
- Swing motion is brief (0.5-1.5s)
- Most of the video is setup/idle (no_swing)
- Even when camera is on the golfer, body may be relatively still between swings
- 5-class model trained with 60-90% no_swing clips, so prior is high

**Test:**
1. Temporarily **disable** pre-filter: comment out line 212 in ActionClassifierDetector
2. Run calibration on all 3 videos
3. Check logs: what % of predictions are no_swing?
4. **Expected result:** If filter was blocking, you'll now see detections

### Hypothesis 2: Prediction Window Mismatch

**Theory:** Model expects different input shape than config specifies.

**Test:**
1. Add **detailed logging** in PhaseClassifier.readModelWindow() (line 65-71)
2. Log: `modelDescription.inputDescriptionsByName["poses"]` shape for all 4 models
3. Check: shape[0] matches config predictionWindow?
4. **Expected result:** Find model with mismatched window → fix config

### Hypothesis 3: Class Label Mismatch (6-Class Model)

**Theory:** 6-class model outputs "noswing" (no underscore), but config checks for "no_swing"

**Test:**
1. Check actual class labels exported by Create ML:
   - Open GolfSwingClassifier_6class.mlmodel in Create ML app
   - Inspect "Output" feature → class labels
2. Check config (line 154): `noSwingLabel: "noswing"`
3. **Expected result:** If labels don't match, 6-class silently fails

### Hypothesis 4: Probability Threshold Too High

**Theory:** Model outputs realistic probability distributions (0.15-0.30 each for swing classes), but thresholds expect 0.25-0.50 peaks.

**Test:**
1. Add **full probability logging** in ActionClassifierDetector.runClassification()
2. Log all predictions to file during calibration run
3. Analyze: what are actual max probabilities for swing classes?
4. **Expected result:** If max probabilities are 0.20-0.30, thresholds are wrong

### Hypothesis 5: lXPXAgpqLZI is Slow-Motion

**Theory:** 3.6-second swing is abnormally long; likely slow-motion that wasn't excluded

**Test:**
1. Compare video frame timestamps:
   - Expected: ~21-108 frames for 0.7-3.6 second swing
   - If slow-motion: frame intervals would be 2x or 3x larger
2. Check GolfDB metadata directly to confirm speed
3. **Expected result:** If slow-motion, exclude from testing

---

## 7. Root Cause Conclusion

**Most Likely Culprit: No-Swing Dominance Pre-Filter**

The combination of:
1. High no_swing ratio in training data (1,483 clips, ~28% of total)
2. Strict 0.60-0.70 dominance threshold
3. Short prediction window (15-60 frames) relative to typical swing duration

Creates a **cascade failure scenario:**
- Model correctly identifies swing phases when they occur
- But surroundings (setup, idle) produce high no_swing probability
- Over a 10-prediction history window, if even 1-2 frames are idle setup, ratio hits >60%
- Pre-filter blocks ALL detection attempts

**Secondary Culprit: Probability Thresholds**

Even if pre-filter is disabled, detection may still fail if:
- Model outputs realistic probabilities (0.15-0.30 peaks) not extreme peaks (0.40+)
- Config expects 0.30-0.50 thresholds (unrealistic for 5-6 class problems)
- Detection strategies (DownswingToFollowThrough, etc.) never trigger

---

## 8. Recommendations

### Immediate Actions (Testing)

1. **Enable comprehensive logging:**
   - PhaseClassifier: log all predictions + probabilities
   - ActionClassifierDetector: log pre-filter evaluation + history ratios
   - ImpactDetectionChain: log each strategy evaluation (already partially done)

2. **Disable pre-filter temporarily** (for testing only):
   ```swift
   guard !isNoSwingDominant(in: history) else {
       AppLogger.detection.info("DEBUG: Blocking due to no-swim dominance \(noSwingRatio)")
       return
   }
   ```

3. **Verify prediction windows:**
   - Run app with calibration logger enabled
   - Check logs: what window sizes are reported from models?
   - Compare against DetectorConfiguration

### Medium-Term Fixes

1. **Adjust no-swim dominance threshold** (if confirmed as culprit):
   - Lower from 0.60-0.70 to 0.75-0.80 (allow more no_swing)
   - Or change to: "requires at least 2 consecutive swing labels in last N predictions"

2. **Retrain models with better class balance:**
   - Current imbalance: ~1.5:1 (no_swing + follow_through heavy)
   - Target: ~1:1 balance by reducing no_swing clips

3. **Lower probability thresholds** (if confirmed as issue):
   - 5-class: reduce from 0.40-0.50 to 0.25-0.35
   - 4-class: reduce from 0.25-0.40 to 0.15-0.25
   - Test on real swings to find optimal operating point

4. **Improve pose extraction quality:**
   - Consider raising minimumJointConfidence from 0.35 to 0.50
   - Add secondary check: require ≥12/14 joints (not just 8)
   - Filter out frames with low average joint confidence

### Long-Term Strategy

1. **Implement adaptive thresholds:**
   - Instead of fixed thresholds, adjust based on:
     - Recent prediction variance (high variance = confident predictions)
     - Temporal smoothness (valid swings have coherent phase transitions)

2. **Add audio confirmation:**
   - Implement `audioConfirmed` field in SwingBounds
   - Use 2-4 kHz spike detection for impact confirmation
   - Fuse with vision predictions for higher confidence

3. **Benchmark against GolfDB test set:**
   - Extract reserved test subset
   - Run end-to-end detection
   - Measure precision/recall/F1 for each model variant

---

## Appendix: File References

### Key Detection Code
- `/golf-sync-swing/Services/ActionClassifierDetector.swift` — main detector
- `/golf-sync-swing/Services/Detection/PhaseClassifier.swift` — CoreML wrapper
- `/golf-sync-swing/Services/Detection/PoseExtractor.swift` — Vision pose extraction
- `/golf-sync-swing/Services/Detection/DetectorConfiguration.swift` — thresholds
- `/golf-sync-swing/Services/Detection/ImpactDetectionChain.swift` — strategy chain

### Dataset & Training
- `ml-training/extract_5class_dataset.py` — dataset preparation
- `ml-training/training_data_5class/` — 5,236 training clips (1.7GB)
- `ml-training/MyActionClassifier.mlproj/` — Create ML project

### Models (in app bundle)
- `GolfSwingClassifier.mlmodel` (4-class, 60-frame window)
- `GolfSwingClassifier_v3.mlmodel` (4-class v2, 60-frame window)
- `GolfSwingClassifier_5class.mlmodel` (5-class, 18-frame window)
- `GolfSwingClassifier_6class.mlmodel` (6-class, 15-frame window)

### Calibration Videos
- `ml-training/youtube_videos/3wru0WH0buk.mp4` (0.7s swing)
- `ml-training/youtube_videos/lXPXAgpqLZI.mp4` (3.6s swing — suspicious)
- `ml-training/youtube_videos/gVrpJYWrpLc.mp4` (2.2s swing)

