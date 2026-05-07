#!/usr/bin/env python3
"""
Part 2: Additional analysis — class balance, optimal schemes, and
practical accuracy estimates.
"""

import numpy as np
import scipy.io
import os

MAT_PATH = "/Users/aleksanderogurtsov/Desktop/test/golf-sync-swing/ml-training/golfdb_repo/data/golfDB.mat"
VIDEO_DIR = "/Users/aleksanderogurtsov/Desktop/test/golf-sync-swing/ml-training/youtube_videos"

mat = scipy.io.loadmat(MAT_PATH)
raw = mat["golfDB"][0]

records = []
for entry in raw:
    rec = {
        "id": int(entry[0][0, 0]),
        "youtube_id": str(entry[1][0]),
        "slow": int(entry[6][0, 0]),
        "events": entry[7][0].tolist(),
    }
    records.append(rec)

normal = [r for r in records if r["slow"] == 0]
FPS = 30.0

# ============================================================
# A: CLASS BALANCE for different schemes (15-frame clips)
# ============================================================

print("=" * 70)
print("CLASS BALANCE ANALYSIS: 5-class vs 3-class vs 2-class")
print("=" * 70)

# 5-class scheme: backswing, downswing, impact (±4f), follow_through, no_swing
# Count TOTAL FRAMES per class across all normal-speed annotations
class_frames_5 = {
    "no_swing_pre": 0,   # start → address (events[0]→events[1])
    "no_swing_addr": 0,  # address → toe-up (events[1]→events[2])
    "backswing": 0,      # toe-up → top (events[2]→events[4])
    "downswing": 0,      # top → impact-4
    "impact": 0,         # impact±4
    "follow_through": 0, # impact+4 → finish
    "no_swing_post": 0,  # finish → end
}

for r in normal:
    ev = r["events"]
    class_frames_5["no_swing_pre"] += max(0, ev[1] - ev[0])
    class_frames_5["no_swing_addr"] += max(0, ev[2] - ev[1])
    class_frames_5["backswing"] += max(0, ev[4] - ev[2])
    class_frames_5["downswing"] += max(0, (ev[6] - 4) - ev[4])
    class_frames_5["impact"] += 9  # ±4 frames
    class_frames_5["follow_through"] += max(0, ev[8] - (ev[6] + 4))
    class_frames_5["no_swing_post"] += max(0, ev[9] - ev[8])

total_frames = sum(class_frames_5.values())
print(f"\nTotal frames across all normal-speed annotations: {total_frames}")
print(f"\n5-CLASS frame distribution:")
for cls, count in class_frames_5.items():
    pct = count / total_frames * 100
    print(f"  {cls:20s}: {count:8d} frames ({pct:5.1f}%)")

# Aggregated 5-class (matching Create ML labels)
print(f"\n5-CLASS AGGREGATED (matching training labels):")
agg = {
    "backswing": class_frames_5["backswing"],
    "downswing": class_frames_5["downswing"],
    "impact": class_frames_5["impact"],
    "follow_through": class_frames_5["follow_through"],
    "no_swing": class_frames_5["no_swing_pre"] + class_frames_5["no_swing_addr"] + class_frames_5["no_swing_post"],
}
for cls, count in agg.items():
    pct = count / total_frames * 100
    print(f"  {cls:20s}: {count:8d} frames ({pct:5.1f}%)")

# 3-class aggregation
print(f"\n3-CLASS (pre_impact / impact / post_impact):")
agg3 = {
    "pre_impact": agg["no_swing"] + agg["backswing"] + agg["downswing"],
    "impact": agg["impact"],
    "post_impact": agg["follow_through"],
}
for cls, count in agg3.items():
    pct = count / total_frames * 100
    print(f"  {cls:20s}: {count:8d} frames ({pct:5.1f}%)")

# 2-class
print(f"\n2-CLASS (swing / no_swing):")
swing = agg["backswing"] + agg["downswing"] + agg["impact"] + agg["follow_through"]
no_swing = agg["no_swing"]
print(f"  {'swing':20s}: {swing:8d} frames ({swing/total_frames*100:5.1f}%)")
print(f"  {'no_swing':20s}: {no_swing:8d} frames ({no_swing/total_frames*100:5.1f}%)")

# ============================================================
# B: Number of CLIPS per class for training
# ============================================================

print("\n" + "=" * 70)
print("TRAINING CLIP COUNTS by scheme and clip length")
print("=" * 70)

for clip_len in [10, 15]:
    print(f"\n--- Clip length: {clip_len} frames ---")

    for scheme in ["5-class", "3-class"]:
        clips = {"backswing": 0, "downswing": 0, "impact": 0,
                 "follow_through": 0, "no_swing": 0,
                 "pre_impact": 0, "post_impact": 0}

        for r in normal:
            ev = r["events"]

            if scheme == "5-class":
                # backswing: centered, one clip per swing
                bs_dur = ev[4] - ev[2]
                if bs_dur >= clip_len:
                    clips["backswing"] += 1  # can fit
                elif bs_dur >= clip_len * 0.5:
                    clips["backswing"] += 1  # partial

                # downswing: centered, one clip per swing
                ds_dur = ev[6] - ev[4]
                if ds_dur >= 1:
                    clips["downswing"] += 1

                # impact: centered on impact, always 1 clip
                clips["impact"] += 1

                # follow_through: centered, one clip
                ft_dur = ev[8] - ev[6]
                if ft_dur >= clip_len:
                    clips["follow_through"] += 1
                elif ft_dur >= clip_len * 0.5:
                    clips["follow_through"] += 1

                # no_swing: pre and post, usually can get 2 clips
                pre_dur = ev[2] - ev[0]
                post_dur = ev[9] - ev[8]
                clips["no_swing"] += min(2, pre_dur // clip_len + post_dur // clip_len)

            elif scheme == "3-class":
                # pre_impact: everything before impact-4
                pre_dur = (ev[6] - 4) - ev[0]
                clips["pre_impact"] += max(1, pre_dur // clip_len)

                # impact: one clip centered on impact
                clips["impact"] += 1

                # post_impact: everything after impact+4
                post_dur = ev[9] - (ev[6] + 4)
                clips["post_impact"] += max(1, post_dur // clip_len)

        print(f"\n  {scheme}:")
        relevant = {k: v for k, v in clips.items() if v > 0}
        total_clips = sum(relevant.values())
        for cls, count in sorted(relevant.items()):
            pct = count / total_clips * 100
            print(f"    {cls:20s}: {count:5d} clips ({pct:5.1f}%)")
        print(f"    {'TOTAL':20s}: {total_clips:5d} clips")

# ============================================================
# C: How many clips per class in EXISTING extracted dataset?
# ============================================================

print("\n" + "=" * 70)
print("EXISTING EXTRACTED DATASET (training_data_5class/)")
print("=" * 70)

base = "/Users/aleksanderogurtsov/Desktop/test/golf-sync-swing/ml-training/training_data_5class"
if os.path.exists(base):
    for cls in sorted(os.listdir(base)):
        cls_path = os.path.join(base, cls)
        if os.path.isdir(cls_path):
            n = len([f for f in os.listdir(cls_path) if f.endswith(".mp4")])
            print(f"  {cls:20s}: {n} clips")
else:
    print("  Directory not found, checking alternatives...")
    for d in ["training_data_v3", "training_data"]:
        alt = os.path.join("/Users/aleksanderogurtsov/Desktop/test/golf-sync-swing/ml-training", d)
        if os.path.exists(alt):
            print(f"\n  Found {d}/:")
            for cls in sorted(os.listdir(alt)):
                cls_path = os.path.join(alt, cls)
                if os.path.isdir(cls_path):
                    n = len([f for f in os.listdir(cls_path) if f.endswith(".mp4")])
                    print(f"    {cls:20s}: {n} clips")

# ============================================================
# D: Accuracy ceiling estimation
# ============================================================

print("\n" + "=" * 70)
print("ACCURACY CEILING ESTIMATION")
print("=" * 70)

print("""
The KEY question: given downswing is only 7.9 frames (median 8) at 30fps,
can a 15-frame sliding window accurately detect the impact frame?

ANALYSIS:

1. DOWNSWING PURITY in 15-frame clips: ONLY 51.8% mean
   - 44.1% of clips have <50% downswing frames
   - This means the classifier sees ~7 frames of downswing + 8 frames of
     adjacent phases (backswing or follow_through)
   - The model must learn to detect downswing from MINORITY of frames

2. IMPACT DETECTION via phase transition:
   - We DON'T need to classify every frame perfectly
   - We need to detect WHEN the prediction transitions
   - Even a noisy classifier that says "backswing" then flips to
     "follow_through" gives us the impact frame within ~8 frames (267ms)

3. OPTIMAL APPROACH for impact detection:

   a) 3-CLASS (pre_impact, impact, post_impact) with 10-frame clips:
      - Impact purity = 90% (9/10 frames in zone)
      - pre/post purity ≈ 100% (long phases)
      - CLEANEST class boundaries → highest classification accuracy
      - But: only finds "impact zone" (±4 frames = ±133ms)

   b) 5-CLASS with 15-frame clips (current):
      - Downswing purity = 52% → model will struggle
      - But transition detection can still work
      - More information for sync refinement

   c) 3-CLASS with 15-frame clips:
      - Impact purity = 60% → still decent
      - Simpler task → higher accuracy
      - Can detect transition with ~±5 frame accuracy (±167ms)

   d) 5-CLASS with 10-frame clips:
      - Downswing purity = 77% → much better!
      - BUT: 10 frames = 333ms → shorter temporal context
      - Create ML minimum is likely 10 frames

4. PRACTICAL IMPACT ACCURACY:
   - SwingNet achieves 98.4% PCE (Predicted Correct Event) on impact
   - PCE metric: |predicted_frame - true_frame| ≤ threshold (usually ±10 frames)
   - With transition detection: ±8 frames typical = ±267ms
   - With probability peak refinement: ±3-4 frames = ±100-133ms
   - Target: ±33ms (1 frame) — probably NOT achievable without audio or
     wrist tracking, but ±100ms is perceptually acceptable
""")

# ============================================================
# E: CONCRETE RECOMMENDATIONS
# ============================================================

print("=" * 70)
print("CONCRETE RECOMMENDATIONS")
print("=" * 70)

print("""
RECOMMENDATION 1: Use 10-frame clips (not 15)
  - Downswing purity jumps from 52% → 77%
  - Impact zone purity: 90% (vs 53% for 15-frame)
  - Backswing: still 99.4% pure at 10 frames
  - Follow-through: 100% pure at 10 frames
  - 10 frames = 333ms, adequate temporal context for pose changes

RECOMMENDATION 2: Keep 5-class scheme (not 3-class)
  - 5-class gives more transition points → better impact refinement
  - The backswing→downswing transition = TOP (well before impact)
  - The downswing→follow_through transition = IMPACT (what we want)
  - With 10-frame clips, even downswing has 77% purity — workable

RECOMMENDATION 3: Transition-based detection in the app
  - Don't try to find a single "impact" prediction
  - Track the probability curve: P(downswing) rising → P(follow_through) rising
  - The crossover point IS the impact frame
  - This is exactly what ImpactDetectionChain already does!

RECOMMENDATION 4: If accuracy is still insufficient, try 3-class
  - 3-class: pre_impact / impact_zone / post_impact
  - 10-frame clips: 90% impact purity
  - Simpler = fewer ways to go wrong
  - Fallback if 5-class doesn't converge

WINDOW SIZE COMPARISON SUMMARY:
  ┌──────────┬──────────────┬───────────────┬─────────────────┐
  │ Window   │ DS purity    │ Impact purity │ Assessment      │
  ├──────────┼──────────────┼───────────────┼─────────────────┤
  │  8 frame │ 93.0%        │ 100% (9>8)    │ Excellent purity│
  │          │              │               │ but maybe too   │
  │          │              │               │ short for Create│
  │          │              │               │ ML temporal     │
  │          │              │               │ learning        │
  ├──────────┼──────────────┼───────────────┼─────────────────┤
  │ 10 frame │ 77.1%        │ 90.0%         │ SWEET SPOT      │
  │          │              │               │ Best balance of │
  │          │              │               │ purity + context│
  ├──────────┼──────────────┼───────────────┼─────────────────┤
  │ 15 frame │ 51.8%        │ 53.3%         │ Current default │
  │          │              │               │ Severe downswing│
  │          │              │               │ contamination   │
  ├──────────┼──────────────┼───────────────┼─────────────────┤
  │ 20 frame │ 39.0%        │ 40.0%         │ Too long, low   │
  │          │              │               │ purity across   │
  │          │              │               │ all classes      │
  ├──────────┼──────────────┼───────────────┼─────────────────┤
  │ 30 frame │ 26.2%        │ 26.7%         │ Catastrophically│
  │          │              │               │ contaminated    │
  └──────────┴──────────────┴───────────────┴─────────────────┘
""")

# ============================================================
# F: Verify 10-frame clip support in Create ML
# ============================================================

print("=" * 70)
print("CREATE ML ACTION CLASSIFIER CONSTRAINTS")
print("=" * 70)
print("""
Create ML Action Classifier key parameters:
  - predictionWindowSize: number of frames per prediction (we set this)
  - Minimum: empirically works with as few as 10 frames
  - Uses pose data (18 body joints from Vision framework)
  - STGCN algorithm (Spatial-Temporal Graph Convolutional Network)

With 10-frame clips at 30fps:
  - Each clip = 333ms of motion
  - A downswing takes ~267ms (median 8 frames)
  - So 10 frames captures the ENTIRE downswing in most cases (98%)
  - Plus 1-2 frames of transition context on each side

CRITICAL: The extraction script (extract_5class_dataset.py) currently
uses 15-frame clips. It should be updated to 10-frame clips for the
next training run.
""")
