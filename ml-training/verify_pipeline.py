#!/usr/bin/env python3
"""
End-to-end verification of the GolfDB -> Create ML 5-class pipeline.

Validates:
  1. GolfDB annotation integrity (all 1400 rows)
  2. Extracted clip quality (frame count, codec, resolution)
  3. Phase purity for extracted clips (annotation-based)
  4. Sliding window inference simulation on real videos
  5. Health score summary -> verification_report.json

Usage:
  cd ml-training && python3 verify_pipeline.py
"""

import json
import random
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
import pandas as pd


# ---------------------------------------------------------------------------
# Constants (mirrored from extract_5class_dataset.py)
# ---------------------------------------------------------------------------

GOLFDB_PKL = "golfdb_repo/data/golfDB.pkl"
DATASET_DIR = "training_data_5class"
YOUTUBE_DIR = "youtube_videos"
REPORT_FILE = "verification_report.json"

TARGET_FPS = 30
TARGET_CLIP_FRAMES = 15
MIN_CLIP_FRAMES = 8
IMPACT_BUFFER = 4
NUM_EVENTS = 10

EXPECTED_CLASSES = ["backswing", "downswing", "follow_through", "impact", "no_swing"]

EVT_PRE = 0
EVT_ADDR = 1
EVT_TAKEAWAY = 2
EVT_TOP = 4
EVT_IMPACT = 6
EVT_FINISH = 8
EVT_POST = 9

RANGE_PHASES = {
    "backswing":      (EVT_TAKEAWAY, EVT_TOP),
    "downswing":      (EVT_TOP, EVT_IMPACT),
    "follow_through": (EVT_IMPACT, EVT_FINISH),
}


# ---------------------------------------------------------------------------
# Result accumulator
# ---------------------------------------------------------------------------

@dataclass
class VerificationReport:
    annotation_checks: dict = field(default_factory=dict)
    clip_checks: dict = field(default_factory=dict)
    purity_checks: dict = field(default_factory=dict)
    inference_simulation: dict = field(default_factory=dict)
    health_score: float = 0.0
    errors: list = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "annotation_checks": self.annotation_checks,
            "clip_checks": self.clip_checks,
            "purity_checks": self.purity_checks,
            "inference_simulation": self.inference_simulation,
            "health_score": self.health_score,
            "errors": self.errors,
        }


# ---------------------------------------------------------------------------
# 1. Annotation validation
# ---------------------------------------------------------------------------

def validate_annotations(report: VerificationReport) -> Optional[pd.DataFrame]:
    """Load and validate ALL GolfDB annotations."""
    print("\n" + "=" * 65)
    print("STEP 1: GolfDB Annotation Validation")
    print("=" * 65)

    pkl_path = Path(GOLFDB_PKL)
    if not pkl_path.exists():
        msg = f"GolfDB pickle not found: {pkl_path}"
        print(f"  FAIL: {msg}")
        report.errors.append(msg)
        report.annotation_checks = {"status": "FAIL", "reason": msg}
        return None

    df = pd.read_pickle(pkl_path)
    total_rows = len(df)
    print(f"  Loaded {total_rows} annotations")

    required_columns = ["id", "youtube_id", "events", "bbox", "slow", "view", "club"]
    missing_cols = [c for c in required_columns if c not in df.columns]
    if missing_cols:
        msg = f"Missing columns: {missing_cols}"
        print(f"  FAIL: {msg}")
        report.errors.append(msg)
        report.annotation_checks = {"status": "FAIL", "reason": msg}
        return df

    valid_count = 0
    invalid_count = 0
    slow_count = 0
    normal_count = 0
    event_length_errors = 0
    monotonic_errors = 0
    negative_frame_errors = 0
    sample_issues = []

    for _, row in df.iterrows():
        events = row["events"]
        row_id = int(row["id"])

        if row["slow"] == 1:
            slow_count += 1
        else:
            normal_count += 1

        if len(events) != NUM_EVENTS:
            event_length_errors += 1
            invalid_count += 1
            if len(sample_issues) < 3:
                sample_issues.append(f"ID {row_id}: {len(events)} events (expected {NUM_EVENTS})")
            continue

        if any(e < 0 for e in events):
            negative_frame_errors += 1
            invalid_count += 1
            if len(sample_issues) < 3:
                sample_issues.append(f"ID {row_id}: negative frame index")
            continue

        is_monotonic = all(events[i] <= events[i + 1] for i in range(NUM_EVENTS - 1))
        if not is_monotonic:
            monotonic_errors += 1
            invalid_count += 1
            if len(sample_issues) < 3:
                sample_issues.append(f"ID {row_id}: non-monotonic events")
            continue

        valid_count += 1

    usable_normal = sum(
        1 for _, r in df.iterrows()
        if r["slow"] != 1
        and len(r["events"]) == NUM_EVENTS
        and all(r["events"][i] <= r["events"][i + 1] for i in range(NUM_EVENTS - 1))
    )

    unique_videos = df["youtube_id"].nunique()

    results = {
        "status": "PASS" if valid_count > 0 else "FAIL",
        "total_annotations": total_rows,
        "valid": valid_count,
        "invalid": invalid_count,
        "normal_speed": normal_count,
        "slow_motion": slow_count,
        "usable_normal_speed": usable_normal,
        "unique_youtube_ids": unique_videos,
        "event_length_errors": event_length_errors,
        "monotonic_errors": monotonic_errors,
        "negative_frame_errors": negative_frame_errors,
    }

    if sample_issues:
        results["sample_issues"] = sample_issues

    report.annotation_checks = results

    print(f"  Valid:         {valid_count}/{total_rows}")
    print(f"  Invalid:       {invalid_count} (events: {event_length_errors}, "
          f"monotonic: {monotonic_errors}, negative: {negative_frame_errors})")
    print(f"  Normal speed:  {normal_count} | Slow-mo: {slow_count}")
    print(f"  Usable (norm): {usable_normal}")
    print(f"  Unique videos: {unique_videos}")
    print(f"  Status:        {results['status']}")

    return df


# ---------------------------------------------------------------------------
# 2. Clip quality checks
# ---------------------------------------------------------------------------

def check_clip_quality(report: VerificationReport) -> None:
    """Sample 10 random clips and verify frame count, codec, resolution."""
    print("\n" + "=" * 65)
    print("STEP 2: Extracted Clip Quality (10 random clips)")
    print("=" * 65)

    dataset = Path(DATASET_DIR)
    if not dataset.exists():
        msg = f"Dataset directory not found: {dataset}"
        print(f"  FAIL: {msg}")
        report.errors.append(msg)
        report.clip_checks = {"status": "FAIL", "reason": msg}
        return

    all_clips = []
    class_counts = {}
    for cls_dir in sorted(dataset.iterdir()):
        if not cls_dir.is_dir():
            continue
        clips = list(cls_dir.glob("*.mp4"))
        class_counts[cls_dir.name] = len(clips)
        all_clips.extend(clips)

    missing_classes = [c for c in EXPECTED_CLASSES if c not in class_counts]
    if missing_classes:
        msg = f"Missing classes: {missing_classes}"
        report.errors.append(msg)

    total_clips = len(all_clips)
    print(f"  Total clips: {total_clips}")
    for cls, count in sorted(class_counts.items()):
        print(f"    {cls:20s}: {count}")

    if total_clips == 0:
        report.clip_checks = {"status": "FAIL", "reason": "No clips found"}
        return

    sample_size = min(10, total_clips)
    sampled = random.sample(all_clips, sample_size)

    passed = 0
    failed = 0
    clip_details = []

    for clip_path in sampled:
        cap = cv2.VideoCapture(str(clip_path))
        detail = {"file": str(clip_path.relative_to(dataset)), "checks": {}}

        if not cap.isOpened():
            detail["checks"]["readable"] = False
            failed += 1
            clip_details.append(detail)
            continue

        detail["checks"]["readable"] = True

        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        fps = cap.get(cv2.CAP_PROP_FPS)
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fourcc_int = int(cap.get(cv2.CAP_PROP_FOURCC))
        fourcc_str = "".join([chr((fourcc_int >> (8 * i)) & 0xFF) for i in range(4)])

        detail["frame_count"] = frame_count
        detail["fps"] = round(fps, 1)
        detail["resolution"] = f"{width}x{height}"
        detail["fourcc"] = fourcc_str

        frame_ok = MIN_CLIP_FRAMES <= frame_count <= TARGET_CLIP_FRAMES + 2
        detail["checks"]["frame_count"] = frame_ok

        fps_ok = 25 <= fps <= 35
        detail["checks"]["fps_in_range"] = fps_ok

        res_ok = width >= 160 and height >= 120
        detail["checks"]["resolution_ok"] = res_ok

        ret, frame = cap.read()
        detail["checks"]["first_frame_readable"] = ret
        if ret:
            detail["checks"]["frame_not_black"] = float(np.mean(frame)) > 5.0

        cap.release()

        all_ok = all(v for v in detail["checks"].values())
        detail["overall"] = "PASS" if all_ok else "FAIL"

        if all_ok:
            passed += 1
        else:
            failed += 1

        clip_details.append(detail)

        status_char = "+" if all_ok else "X"
        print(f"  [{status_char}] {detail['file']} | {frame_count}f @ {fps:.0f}fps | "
              f"{width}x{height} | {fourcc_str}")

    results = {
        "status": "PASS" if failed == 0 else "WARN" if failed <= 2 else "FAIL",
        "total_clips": total_clips,
        "class_counts": class_counts,
        "missing_classes": missing_classes,
        "sampled": sample_size,
        "passed": passed,
        "failed": failed,
        "details": clip_details,
    }

    report.clip_checks = results
    print(f"  Result: {passed}/{sample_size} passed")


# ---------------------------------------------------------------------------
# 3. Phase purity estimation
# ---------------------------------------------------------------------------

def check_phase_purity(report: VerificationReport, df: Optional[pd.DataFrame]) -> None:
    """Estimate phase purity for extracted clips using GolfDB annotations."""
    print("\n" + "=" * 65)
    print("STEP 3: Phase Purity Estimation")
    print("=" * 65)

    if df is None:
        msg = "Skipped: no annotation data"
        print(f"  {msg}")
        report.purity_checks = {"status": "SKIP", "reason": msg}
        return

    dataset = Path(DATASET_DIR)
    if not dataset.exists():
        msg = "Skipped: dataset directory missing"
        print(f"  {msg}")
        report.purity_checks = {"status": "SKIP", "reason": msg}
        return

    anno_map = {}
    for _, row in df.iterrows():
        events = row["events"]
        if len(events) != NUM_EVENTS:
            continue
        anno_map[int(row["id"])] = events

    purity_by_class = {}

    for cls_name in EXPECTED_CLASSES:
        cls_dir = dataset / cls_name
        if not cls_dir.exists():
            continue

        clips = list(cls_dir.glob("*.mp4"))
        sample = random.sample(clips, min(20, len(clips)))

        purities = []
        for clip in sample:
            purity = _estimate_clip_purity(clip, cls_name, anno_map)
            if purity is not None:
                purities.append(purity)

        if purities:
            avg = float(np.mean(purities))
            med = float(np.median(purities))
            mn = float(np.min(purities))
            mx = float(np.max(purities))
        else:
            avg = med = mn = mx = 0.0

        purity_by_class[cls_name] = {
            "sampled": len(sample),
            "computed": len(purities),
            "avg_purity": round(avg, 3),
            "median_purity": round(med, 3),
            "min_purity": round(mn, 3),
            "max_purity": round(mx, 3),
        }

        quality = "GOOD" if avg >= 0.5 else "ACCEPTABLE" if avg >= 0.3 else "LOW"
        print(f"  {cls_name:20s}: avg={avg:.1%} med={med:.1%} "
              f"min={mn:.1%} max={mx:.1%} [{quality}]")

    overall_avg = np.mean([v["avg_purity"] for v in purity_by_class.values()]) if purity_by_class else 0.0
    status = "PASS" if overall_avg >= 0.4 else "WARN" if overall_avg >= 0.25 else "FAIL"

    report.purity_checks = {
        "status": status,
        "overall_avg_purity": round(float(overall_avg), 3),
        "by_class": purity_by_class,
    }
    print(f"  Overall avg purity: {overall_avg:.1%} -> {status}")


def _estimate_clip_purity(clip_path: Path, cls_name: str,
                          anno_map: dict) -> Optional[float]:
    """Estimate what fraction of a clip's frames belong to the labeled class.

    Uses GolfDB event annotations to compute purity.  For range-based classes
    (backswing, downswing, follow_through), purity = overlap(clip_window,
    phase_range) / clip_length.  For impact, purity = overlap(clip_window,
    impact +/- buffer) / clip_length.  For no_swing, purity = 1 - overlap
    with any swing phase.
    """
    stem = clip_path.stem
    parts = stem.split("_")
    if len(parts) < 2:
        return None

    try:
        anno_id = int(parts[1])
    except (ValueError, IndexError):
        return None

    if anno_id not in anno_map:
        return None

    events = anno_map[anno_id]

    cap = cv2.VideoCapture(str(clip_path))
    if not cap.isOpened():
        return None
    clip_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    cap.release()

    if clip_frames <= 0:
        return None

    total_video_frames = int(events[EVT_POST]) + 50

    if cls_name in RANGE_PHASES:
        s_evt, e_evt = RANGE_PHASES[cls_name]
        phase_start = int(events[s_evt])
        phase_end = int(events[e_evt])
        phase_dur = phase_end - phase_start
        if phase_dur <= 0:
            return None

        center = (phase_start + phase_end) // 2
        ws = max(0, center - TARGET_CLIP_FRAMES // 2)
        we = min(total_video_frames, ws + TARGET_CLIP_FRAMES)
        ws = max(0, we - TARGET_CLIP_FRAMES)

        overlap_start = max(ws, phase_start)
        overlap_end = min(we, phase_end)
        overlap = max(0, overlap_end - overlap_start)
        clip_len = we - ws
        return overlap / clip_len if clip_len > 0 else 0.0

    if cls_name == "impact":
        ef = int(events[EVT_IMPACT])
        impact_start = ef - IMPACT_BUFFER
        impact_end = ef + IMPACT_BUFFER
        ws = max(0, ef - TARGET_CLIP_FRAMES // 2)
        we = ws + TARGET_CLIP_FRAMES

        overlap_start = max(ws, impact_start)
        overlap_end = min(we, impact_end)
        overlap = max(0, overlap_end - overlap_start)
        clip_len = we - ws
        return overlap / clip_len if clip_len > 0 else 0.0

    if cls_name == "no_swing":
        swing_start = int(events[EVT_TAKEAWAY])
        swing_end = int(events[EVT_FINISH])
        pre_end = int(events[EVT_TAKEAWAY])
        post_start = int(events[EVT_FINISH])

        pre_center = (int(events[EVT_PRE]) + pre_end) // 2
        post_center = (post_start + int(events[EVT_POST])) // 2

        if "pre" in stem:
            ws = max(0, pre_center - TARGET_CLIP_FRAMES // 2)
            we = ws + TARGET_CLIP_FRAMES
            overlap_start = max(ws, swing_start)
            overlap_end = min(we, swing_end)
            swing_overlap = max(0, overlap_end - overlap_start)
        elif "post" in stem:
            ws = max(0, post_center - TARGET_CLIP_FRAMES // 2)
            we = ws + TARGET_CLIP_FRAMES
            overlap_start = max(ws, swing_start)
            overlap_end = min(we, swing_end)
            swing_overlap = max(0, overlap_end - overlap_start)
        else:
            return None

        clip_len = we - ws
        return 1.0 - (swing_overlap / clip_len) if clip_len > 0 else 0.0

    return None


# ---------------------------------------------------------------------------
# 4. Sliding window inference simulation
# ---------------------------------------------------------------------------

def simulate_inference(report: VerificationReport, df: Optional[pd.DataFrame]) -> None:
    """Simulate sliding window inference on 3 real YouTube videos."""
    print("\n" + "=" * 65)
    print("STEP 4: Sliding Window Inference Simulation")
    print("=" * 65)

    yt_dir = Path(YOUTUBE_DIR)
    if not yt_dir.exists():
        msg = "YouTube videos directory not found"
        print(f"  SKIP: {msg}")
        report.inference_simulation = {"status": "SKIP", "reason": msg}
        return

    if df is None:
        msg = "Skipped: no annotation data"
        print(f"  {msg}")
        report.inference_simulation = {"status": "SKIP", "reason": msg}
        return

    normal_rows = df[(df["slow"] != 1)].copy()
    normal_rows = normal_rows[normal_rows["events"].apply(lambda e: len(e) == NUM_EVENTS)]

    available_ids = set()
    for f in yt_dir.glob("*.mp4"):
        available_ids.add(f.stem)

    candidates = normal_rows[normal_rows["youtube_id"].isin(available_ids)]
    if len(candidates) == 0:
        msg = "No matching YouTube videos for annotations"
        print(f"  SKIP: {msg}")
        report.inference_simulation = {"status": "SKIP", "reason": msg}
        return

    sample_rows = candidates.sample(n=min(3, len(candidates)), random_state=42)
    video_results = []

    for _, row in sample_rows.iterrows():
        yt_id = row["youtube_id"]
        events = row["events"]
        anno_id = int(row["id"])

        video_path = yt_dir / f"{yt_id}.mp4"
        result = _simulate_one_video(video_path, events, anno_id)
        video_results.append(result)

        status_label = "PASS" if result["impact_detected"] else "MISS"
        print(f"  [{status_label}] ID={anno_id:04d} ({yt_id}) | "
              f"windows={result['total_windows']} | "
              f"swing_windows={result['swing_windows']} | "
              f"gt_impact_f={int(events[EVT_IMPACT])}")
        if result["impact_detected"]:
            err = result["impact_error_frames"]
            print(f"         Impact detected at window {result['detected_window_idx']}, "
                  f"error={err}f ({err/TARGET_FPS*1000:.0f}ms)")

    detected = sum(1 for r in video_results if r["impact_detected"])
    total = len(video_results)

    status = "PASS" if detected == total else "WARN" if detected > 0 else "FAIL"

    report.inference_simulation = {
        "status": status,
        "videos_tested": total,
        "impacts_detected": detected,
        "detection_rate": round(detected / total, 3) if total > 0 else 0.0,
        "videos": video_results,
    }
    print(f"  Detection rate: {detected}/{total} -> {status}")


def _simulate_one_video(video_path: Path, events: np.ndarray, anno_id: int) -> dict:
    """Simulate sliding window classification on a single video.

    Instead of running a real model, we simulate "oracle" classification:
    for each window, compute which phase has the highest overlap fraction
    and return that as the predicted label.  This tests whether the sliding
    window geometry can successfully find the impact region.
    """
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return {
            "anno_id": anno_id,
            "youtube_id": video_path.stem,
            "error": "Could not open video",
            "impact_detected": False,
            "total_windows": 0,
            "swing_windows": 0,
        }

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    cap.release()

    gt_impact = int(events[EVT_IMPACT])
    gt_takeaway = int(events[EVT_TAKEAWAY])
    gt_finish = int(events[EVT_FINISH])

    swing_region_start = max(0, gt_takeaway - 30)
    swing_region_end = min(total_frames, gt_finish + 30)

    window_size = TARGET_CLIP_FRAMES
    stride_idle = 8
    stride_active = 2

    predictions = []
    current_stride = stride_idle
    in_swing_region = False
    pos = swing_region_start

    while pos + window_size <= swing_region_end:
        ws = pos
        we = pos + window_size

        label, probs = _oracle_classify(ws, we, events)
        predictions.append({
            "window_start": ws,
            "window_end": we,
            "label": label,
            "probabilities": probs,
        })

        is_swing_label = label in ("backswing", "downswing", "impact", "follow_through")
        if is_swing_label and not in_swing_region:
            in_swing_region = True
            current_stride = stride_active
        elif not is_swing_label and in_swing_region:
            in_swing_region = False
            current_stride = stride_idle

        pos += current_stride

    swing_windows = sum(1 for p in predictions if p["label"] != "no_swing")
    impact_windows = [p for p in predictions if p["label"] == "impact"]
    downswing_windows = [p for p in predictions if p["label"] == "downswing"]

    impact_detected = False
    detected_window_idx = -1
    impact_error_frames = -1

    if impact_windows:
        best = impact_windows[0]
        detected_center = (best["window_start"] + best["window_end"]) // 2
        impact_error_frames = abs(detected_center - gt_impact)
        impact_detected = True
        detected_window_idx = predictions.index(best)
    elif downswing_windows:
        last_ds = downswing_windows[-1]
        detected_center = last_ds["window_end"]
        impact_error_frames = abs(detected_center - gt_impact)
        impact_detected = impact_error_frames <= TARGET_CLIP_FRAMES
        detected_window_idx = predictions.index(last_ds)

    return {
        "anno_id": anno_id,
        "youtube_id": video_path.stem,
        "total_frames": total_frames,
        "fps": round(fps, 1),
        "gt_impact_frame": gt_impact,
        "total_windows": len(predictions),
        "swing_windows": swing_windows,
        "impact_windows": len(impact_windows),
        "impact_detected": impact_detected,
        "detected_window_idx": detected_window_idx,
        "impact_error_frames": impact_error_frames,
    }


def _oracle_classify(ws: int, we: int, events: np.ndarray) -> tuple:
    """Oracle classifier: returns label based on max overlap with ground truth phases."""
    phases = {
        "backswing":      (int(events[EVT_TAKEAWAY]), int(events[EVT_TOP])),
        "downswing":      (int(events[EVT_TOP]), int(events[EVT_IMPACT])),
        "impact":         (int(events[EVT_IMPACT]) - IMPACT_BUFFER,
                           int(events[EVT_IMPACT]) + IMPACT_BUFFER),
        "follow_through": (int(events[EVT_IMPACT]), int(events[EVT_FINISH])),
    }

    clip_len = we - ws
    overlaps = {}
    total_swing_overlap = 0

    for label, (ps, pe) in phases.items():
        overlap = max(0, min(we, pe) - max(ws, ps))
        frac = overlap / clip_len if clip_len > 0 else 0.0
        overlaps[label] = frac
        total_swing_overlap += overlap

    no_swing_frac = 1.0 - (total_swing_overlap / clip_len) if clip_len > 0 else 1.0
    overlaps["no_swing"] = max(0.0, no_swing_frac)

    total = sum(overlaps.values())
    probs = {k: round(v / total, 3) if total > 0 else 0.2 for k, v in overlaps.items()}

    best_label = max(overlaps, key=overlaps.get)
    return best_label, probs


# ---------------------------------------------------------------------------
# 5. Health score computation
# ---------------------------------------------------------------------------

def compute_health_score(report: VerificationReport) -> float:
    """Compute an overall pipeline health score (0-100)."""
    score = 0.0
    weights = {
        "annotations": 25.0,
        "clips": 25.0,
        "purity": 25.0,
        "inference": 25.0,
    }

    anno = report.annotation_checks
    if anno.get("status") == "PASS":
        usable = anno.get("usable_normal_speed", 0)
        if usable >= 700:
            score += weights["annotations"]
        elif usable >= 400:
            score += weights["annotations"] * 0.7
        else:
            score += weights["annotations"] * 0.3

    clips = report.clip_checks
    if clips.get("status") == "PASS":
        score += weights["clips"]
    elif clips.get("status") == "WARN":
        score += weights["clips"] * 0.6
    elif clips.get("total_clips", 0) > 0:
        score += weights["clips"] * 0.3

    purity = report.purity_checks
    if purity.get("status") == "PASS":
        avg_p = purity.get("overall_avg_purity", 0)
        score += weights["purity"] * min(1.0, avg_p / 0.6)
    elif purity.get("status") == "WARN":
        score += weights["purity"] * 0.5

    inference = report.inference_simulation
    if inference.get("status") == "PASS":
        score += weights["inference"]
    elif inference.get("status") == "WARN":
        rate = inference.get("detection_rate", 0)
        score += weights["inference"] * rate

    return round(score, 1)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    start_time = time.time()
    random.seed(42)

    print("=" * 65)
    print("  GolfDB -> Create ML 5-Class Pipeline Verification")
    print("=" * 65)

    report = VerificationReport()

    df = validate_annotations(report)
    check_clip_quality(report)
    check_phase_purity(report, df)
    simulate_inference(report, df)

    report.health_score = compute_health_score(report)

    elapsed = time.time() - start_time

    print("\n" + "=" * 65)
    print("  VERIFICATION SUMMARY")
    print("=" * 65)
    print(f"  Annotations:  {report.annotation_checks.get('status', 'N/A')}")
    print(f"  Clip quality: {report.clip_checks.get('status', 'N/A')}")
    print(f"  Phase purity: {report.purity_checks.get('status', 'N/A')}")
    print(f"  Inference:    {report.inference_simulation.get('status', 'N/A')}")
    print(f"  Health score: {report.health_score}/100")
    print(f"  Elapsed:      {elapsed:.1f}s")

    if report.errors:
        print(f"  Errors:       {len(report.errors)}")
        for err in report.errors:
            print(f"    - {err}")

    output = report.to_dict()
    output["elapsed_seconds"] = round(elapsed, 1)

    report_path = Path(REPORT_FILE)
    with open(report_path, "w") as f:
        json.dump(output, f, indent=2)
    print(f"\n  Report saved to {report_path}")
    print("=" * 65)

    return 0 if report.health_score >= 50 else 1


if __name__ == "__main__":
    sys.exit(main())
