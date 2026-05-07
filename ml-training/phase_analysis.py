#!/usr/bin/env python3
"""
GolfDB Phase Duration & Dataset Quality Analysis
Analyzes phase statistics from the GolfDB annotations to inform
optimal Create ML Action Classifier training parameters.
"""

import numpy as np
import scipy.io
import os
import json

# ============================================================
# PART 1: Load and parse GolfDB annotations
# ============================================================

MAT_PATH = "/Users/aleksanderogurtsov/Desktop/test/golf-sync-swing/ml-training/golfdb_repo/data/golfDB.mat"
VIDEO_DIR = "/Users/aleksanderogurtsov/Desktop/test/golf-sync-swing/ml-training/youtube_videos"

mat = scipy.io.loadmat(MAT_PATH)
raw = mat["golfDB"][0]

# Parse all 1400 annotations into structured records
records = []
for entry in raw:
    rec = {
        "id": int(entry[0][0, 0]),
        "youtube_id": str(entry[1][0]),
        "player": str(entry[2][0]),
        "sex": str(entry[3][0]),
        "club": str(entry[4][0]),
        "view": str(entry[5][0]),
        "slow": int(entry[6][0, 0]),
        "events": entry[7][0].tolist(),  # 10 frame numbers
        "bbox": entry[8][0].tolist(),
        "split": int(entry[9][0, 0]),
    }
    records.append(rec)

total = len(records)
normal_speed = [r for r in records if r["slow"] == 0]
slow_motion = [r for r in records if r["slow"] == 1]

print("=" * 70)
print("GOLFDB DATASET OVERVIEW")
print("=" * 70)
print(f"Total annotations: {total}")
print(f"Normal speed (slow=0): {len(normal_speed)}")
print(f"Slow motion (slow=1): {len(slow_motion)}")

# GolfDB 8 events (0-indexed into events array):
# 0: start_frame, 1: address, 2: toe-up (takeaway), 3: mid-backswing,
# 4: top, 5: mid-downswing, 6: impact, 7: mid-follow-through,
# 8: finish, 9: end_frame
#
# Our phases:
#   backswing  = events[2] → events[4] (toe-up → top)
#   downswing  = events[4] → events[6] (top → impact)
#   follow_through = events[6] → events[8] (impact → finish)

# ============================================================
# PART 2: Phase duration distributions (NORMAL SPEED ONLY)
# ============================================================

print("\n" + "=" * 70)
print("PART 2: PHASE DURATION DISTRIBUTIONS (Normal Speed Only, N={})".format(len(normal_speed)))
print("=" * 70)

FPS = 30.0

phase_defs = {
    "backswing":      (2, 4),  # toe-up → top
    "downswing":      (4, 6),  # top → impact
    "follow_through": (6, 8),  # impact → finish
    "full_swing":     (2, 8),  # toe-up → finish (for context)
}

phase_frames = {}
for phase_name, (start_idx, end_idx) in phase_defs.items():
    durations = []
    for r in normal_speed:
        ev = r["events"]
        d = ev[end_idx] - ev[start_idx]
        if d > 0:  # sanity check
            durations.append(d)
    phase_frames[phase_name] = np.array(durations)

for phase_name, frames in phase_frames.items():
    ms = frames / FPS * 1000
    print(f"\n--- {phase_name.upper()} ({len(frames)} valid annotations) ---")
    print(f"  Frames:  mean={frames.mean():.1f}  median={np.median(frames):.1f}  "
          f"std={frames.std():.1f}  min={frames.min()}  max={frames.max()}")
    print(f"  Millis:  mean={ms.mean():.0f}ms  median={np.median(ms):.0f}ms  "
          f"std={ms.std():.0f}ms  min={ms.min():.0f}ms  max={ms.max():.0f}ms")
    pcts = np.percentile(frames, [5, 25, 75, 95])
    print(f"  Percentiles (frames):  5th={pcts[0]:.0f}  25th={pcts[1]:.0f}  "
          f"75th={pcts[2]:.0f}  95th={pcts[3]:.0f}")
    pcts_ms = pcts / FPS * 1000
    print(f"  Percentiles (ms):      5th={pcts_ms[0]:.0f}  25th={pcts_ms[1]:.0f}  "
          f"75th={pcts_ms[2]:.0f}  95th={pcts_ms[3]:.0f}")

# ============================================================
# PART 3: Phase purity analysis for 15-frame clips
# ============================================================

print("\n" + "=" * 70)
print("PART 3: PHASE PURITY ANALYSIS")
print("=" * 70)

for clip_len in [8, 10, 15, 20, 30]:
    print(f"\n{'='*50}")
    print(f"CLIP LENGTH: {clip_len} frames ({clip_len/FPS*1000:.0f}ms)")
    print(f"{'='*50}")

    for phase_name, (start_idx, end_idx) in phase_defs.items():
        if phase_name == "full_swing":
            continue

        purities = []
        for r in normal_speed:
            ev = r["events"]
            phase_start = ev[start_idx]
            phase_end = ev[end_idx]
            phase_dur = phase_end - phase_start
            if phase_dur <= 0:
                continue

            # Center clip on the phase midpoint
            mid = (phase_start + phase_end) / 2.0
            clip_start = mid - clip_len / 2.0
            clip_end = clip_start + clip_len

            # Count frames in clip that actually belong to this phase
            overlap_start = max(clip_start, phase_start)
            overlap_end = min(clip_end, phase_end)
            overlap = max(0, overlap_end - overlap_start)
            purity = overlap / clip_len
            purities.append(purity)

        purities = np.array(purities)
        below_50 = np.sum(purities < 0.50)
        below_30 = np.sum(purities < 0.30)
        above_80 = np.sum(purities >= 0.80)
        print(f"\n  {phase_name}: N={len(purities)}")
        print(f"    Purity: mean={purities.mean():.3f}  median={np.median(purities):.3f}  "
              f"min={purities.min():.3f}  max={purities.max():.3f}")
        print(f"    <30% purity: {below_30} ({below_30/len(purities)*100:.1f}%)")
        print(f"    <50% purity: {below_50} ({below_50/len(purities)*100:.1f}%)")
        print(f"    >=80% purity: {above_80} ({above_80/len(purities)*100:.1f}%)")

# ============================================================
# PART 3b: Impact-zone purity (±4 frames centered on impact)
# ============================================================

print("\n" + "=" * 70)
print("PART 3b: IMPACT ZONE PURITY (±4 frames = 9-frame zone)")
print("=" * 70)

for clip_len in [8, 10, 15, 20, 30]:
    impact_purities = []
    IMPACT_HALF = 4  # ±4 frames around impact
    for r in normal_speed:
        ev = r["events"]
        impact_frame = ev[6]
        zone_start = impact_frame - IMPACT_HALF
        zone_end = impact_frame + IMPACT_HALF

        # Center clip on impact
        clip_start = impact_frame - clip_len / 2.0
        clip_end = clip_start + clip_len

        overlap_start = max(clip_start, zone_start)
        overlap_end = min(clip_end, zone_end)
        overlap = max(0, overlap_end - overlap_start)
        # Purity = what fraction of the clip is "impact zone"
        purity = overlap / clip_len
        impact_purities.append(purity)

    ip = np.array(impact_purities)
    print(f"\n  Clip={clip_len}f: Impact zone purity: mean={ip.mean():.3f}  "
          f"median={np.median(ip):.3f}  min={ip.min():.3f}  max={ip.max():.3f}")


# ============================================================
# PART 4: Sliding window simulation on real videos
# ============================================================

print("\n" + "=" * 70)
print("PART 4: SLIDING WINDOW SIMULATION ON REAL VIDEOS")
print("=" * 70)

# Find 5 normal-speed videos that we have locally
video_annotations = {}
for r in normal_speed:
    vid = r["youtube_id"]
    if vid not in video_annotations:
        video_annotations[vid] = []
    video_annotations[vid].append(r)

available_videos = []
for vid in video_annotations:
    path = os.path.join(VIDEO_DIR, f"{vid}.mp4")
    if os.path.exists(path):
        available_videos.append(vid)

print(f"\nAvailable normal-speed videos with local files: {len(available_videos)}")
print(f"Selecting first 5 for simulation...")

selected = available_videos[:5]

for window_size in [10, 15, 20]:
    stride = 2
    print(f"\n--- Window={window_size} frames, Stride={stride} ---")

    total_windows_all = 0
    impact_windows_all = 0

    for vid in selected:
        annotations = video_annotations[vid]
        # Get video length from annotations (max event frame)
        max_frame = max(r["events"][-1] for r in annotations)

        # Generate all windows
        windows = list(range(0, max_frame - window_size + 1, stride))
        total_windows = len(windows)

        # For each swing, find windows that "contain" impact ±4 frames
        impact_windows = set()
        for r in annotations:
            impact_frame = r["events"][6]
            impact_zone = range(impact_frame - 4, impact_frame + 5)

            for w_start_idx, w_start in enumerate(windows):
                w_end = w_start + window_size
                # Check if any impact zone frame is in this window
                for iz_frame in impact_zone:
                    if w_start <= iz_frame < w_end:
                        impact_windows.add(w_start_idx)
                        break

        n_impact = len(impact_windows)
        ratio = n_impact / total_windows if total_windows > 0 else 0

        print(f"  Video {vid}: {len(annotations)} swings, "
              f"{total_windows} total windows, "
              f"{n_impact} impact windows ({ratio:.4f} = {ratio*100:.2f}%)")

        total_windows_all += total_windows
        impact_windows_all += n_impact

    overall_ratio = impact_windows_all / total_windows_all if total_windows_all > 0 else 0
    print(f"  OVERALL: {total_windows_all} total, {impact_windows_all} impact "
          f"({overall_ratio:.4f} = {overall_ratio*100:.2f}%)")

# ============================================================
# PART 5: Detailed downswing analysis — THE key question
# ============================================================

print("\n" + "=" * 70)
print("PART 5: DOWNSWING DEEP ANALYSIS (The Critical Phase)")
print("=" * 70)

ds = phase_frames["downswing"]
print(f"\nDownswing duration distribution (N={len(ds)}):")
for threshold in [3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20]:
    count = np.sum(ds <= threshold)
    print(f"  <= {threshold:2d} frames ({threshold/FPS*1000:5.0f}ms): "
          f"{count} ({count/len(ds)*100:.1f}%)")

# What fraction of downswings fit entirely within various clip sizes?
print(f"\nDownswings that fit entirely within clip:")
for clip_len in [8, 10, 12, 15, 20, 30]:
    fits = np.sum(ds <= clip_len)
    print(f"  {clip_len:2d}-frame clip: {fits}/{len(ds)} ({fits/len(ds)*100:.1f}%)")

# For a 15-frame clip centered on TOP: what % is downswing vs backswing?
print(f"\nFor 15-frame clip centered on TOP of backswing:")
contamination = []
for r in normal_speed:
    ev = r["events"]
    top_frame = ev[4]
    ds_dur = ev[6] - ev[4]  # downswing
    bs_dur = ev[4] - ev[2]  # backswing
    if ds_dur <= 0 or bs_dur <= 0:
        continue

    clip_start = top_frame - 7  # 15//2
    clip_end = top_frame + 8

    # Frames that are backswing (before top)
    bs_in_clip = max(0, min(top_frame, clip_end) - max(ev[2], clip_start))
    # Frames that are downswing (after top)
    ds_in_clip = max(0, min(ev[6], clip_end) - max(top_frame, clip_start))

    contamination.append({
        "bs_frac": bs_in_clip / 15,
        "ds_frac": ds_in_clip / 15,
        "ds_dur": ds_dur,
    })

bs_fracs = np.array([c["bs_frac"] for c in contamination])
ds_fracs = np.array([c["ds_frac"] for c in contamination])
print(f"  Backswing fraction: mean={bs_fracs.mean():.3f} ({bs_fracs.mean()*15:.1f} frames)")
print(f"  Downswing fraction: mean={ds_fracs.mean():.3f} ({ds_fracs.mean()*15:.1f} frames)")
print(f"  => A 'downswing' clip centered on phase midpoint is ~{ds_fracs.mean()*100:.0f}% pure")

# ============================================================
# PART 6: OPTIMAL STRATEGY RECOMMENDATIONS
# ============================================================

print("\n" + "=" * 70)
print("PART 6: QUANTITATIVE RECOMMENDATIONS")
print("=" * 70)

# What if we use the entire downswing as the clip (variable length)?
print("\n--- Approach A: Fixed 15-frame clips (current) ---")
ds_purity_15 = []
for r in normal_speed:
    ev = r["events"]
    ds_dur = ev[6] - ev[4]
    if ds_dur <= 0:
        continue
    purity = min(ds_dur, 15) / 15
    ds_purity_15.append(purity)
ds_purity_15 = np.array(ds_purity_15)
print(f"  Downswing purity in 15-frame clips: mean={ds_purity_15.mean():.3f}")
print(f"  Clips with <50% downswing: {np.sum(ds_purity_15 < 0.5)/len(ds_purity_15)*100:.1f}%")

# 3-class scheme analysis
print("\n--- 3-class scheme: pre_impact, impact_zone, post_impact ---")
print("  Impact zone = ±4 frames around impact (9 frames total)")
print("  pre_impact = everything before impact-4")
print("  post_impact = everything after impact+4")
for clip_len in [10, 15, 20]:
    # Impact zone is always 9 frames
    purity = min(9, clip_len) / clip_len
    print(f"  {clip_len}-frame clip impact purity: {purity:.3f} "
          f"({'GOOD' if purity >= 0.5 else 'BAD'})")

    # pre_impact and post_impact are LONG phases → always high purity
    pre_durs = []
    post_durs = []
    for r in normal_speed:
        ev = r["events"]
        pre = ev[6] - 4 - ev[0]
        post = ev[9] - (ev[6] + 4)
        if pre > 0:
            pre_durs.append(pre)
        if post > 0:
            post_durs.append(post)
    pre_durs = np.array(pre_durs)
    post_durs = np.array(post_durs)
    # These phases are always > clip_len, so purity = 1.0
    pre_fits = np.sum(pre_durs >= clip_len) / len(pre_durs) * 100
    post_fits = np.sum(post_durs >= clip_len) / len(post_durs) * 100
    print(f"  pre_impact  >= {clip_len}f: {pre_fits:.1f}%  (median={np.median(pre_durs):.0f}f)")
    print(f"  post_impact >= {clip_len}f: {post_fits:.1f}%  (median={np.median(post_durs):.0f}f)")


# What about transition-based detection (no classification needed)?
print("\n--- Alternative: Transition-based detection ---")
print("  Instead of classifying individual clips,")
print("  detect the TRANSITION point where predictions flip")
print("  from 'backswing' to 'follow_through'")

# How many frames between top and impact?
top_to_impact = []
for r in normal_speed:
    ev = r["events"]
    t2i = ev[6] - ev[4]
    if t2i > 0:
        top_to_impact.append(t2i)
top_to_impact = np.array(top_to_impact)
print(f"\n  Top→Impact gap: mean={top_to_impact.mean():.1f}f ({top_to_impact.mean()/FPS*1000:.0f}ms)")
print(f"  This is the 'transition zone' where classifier flips")
print(f"  Even with ±3 frame error, impact detection within ±{3/FPS*1000:.0f}ms")

# ============================================================
# PART 7: Summary stats as JSON for machine consumption
# ============================================================

summary = {
    "dataset": {
        "total": total,
        "normal_speed": len(normal_speed),
        "slow_motion": len(slow_motion),
    },
    "phase_durations_normal_speed": {},
    "optimal_clip_length": None,
    "recommendations": [],
}

for phase_name, frames in phase_frames.items():
    summary["phase_durations_normal_speed"][phase_name] = {
        "mean_frames": float(frames.mean()),
        "median_frames": float(np.median(frames)),
        "std_frames": float(frames.std()),
        "min_frames": int(frames.min()),
        "max_frames": int(frames.max()),
        "mean_ms": float(frames.mean() / FPS * 1000),
        "median_ms": float(np.median(frames) / FPS * 1000),
        "p5_frames": float(np.percentile(frames, 5)),
        "p25_frames": float(np.percentile(frames, 25)),
        "p75_frames": float(np.percentile(frames, 75)),
        "p95_frames": float(np.percentile(frames, 95)),
    }

# Save summary
out_path = "/Users/aleksanderogurtsov/Desktop/test/golf-sync-swing/ml-training/phase_analysis_results.json"
with open(out_path, "w") as f:
    json.dump(summary, f, indent=2)
print(f"\n\nResults saved to: {out_path}")
print("ANALYSIS COMPLETE.")
