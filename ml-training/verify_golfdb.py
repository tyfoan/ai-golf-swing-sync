#!/usr/bin/env python3
"""
GolfDB Dataset Verification Script

Spot-checks 10 specific annotations against actual video files,
extracts key frames (TOP, pre-impact, IMPACT) as PNGs for visual review,
and runs dataset-wide quality checks.

Loads from golfDB.mat (scipy) to avoid pandas version incompatibility.
"""

import os
import sys
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
import scipy.io

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

BASE_DIR = Path(__file__).parent
GOLFDB_MAT = BASE_DIR / "golfdb_repo" / "data" / "golfDB.mat"
YOUTUBE_DIR = BASE_DIR / "youtube_videos"
TRAINING_DIR = BASE_DIR / "training_data_5class"
VERIFY_DIR = BASE_DIR / "verification_frames"

# GolfDB event indices (10 events per swing)
# 0:PRE  1:ADDR  2:TOE-UP  3:MID-BACK  4:TOP  5:MID-DOWN  6:IMPACT  7:MID-FOLLOW  8:FINISH  9:POST
EVENT_NAMES = [
    "PRE", "ADDRESS", "TOE-UP", "MID-BACK", "TOP",
    "MID-DOWN", "IMPACT", "MID-FOLLOW", "FINISH", "POST"
]

# IDs to spot-check (normal-speed, as specified by team lead)
SPOT_CHECK_IDS = [624, 448, 880, 867, 386, 1154, 713, 1331, 939, 136]


# ---------------------------------------------------------------------------
# Data loading from .mat file
# ---------------------------------------------------------------------------

@dataclass
class Annotation:
    id: int
    youtube_id: str
    player_name: str
    gender: str
    club: str
    view: str
    slow: int
    events: np.ndarray
    bbox: np.ndarray
    split: int

    @property
    def is_slow_motion(self):
        return self.slow == 1


def load_all_annotations():
    """Load all 1400 GolfDB annotations from the .mat file."""
    mat = scipy.io.loadmat(str(GOLFDB_MAT))
    raw = mat["golfDB"][0]  # shape (1400,) of structured arrays

    annotations = []
    for entry in raw:
        anno = Annotation(
            id=int(entry[0][0, 0]),
            youtube_id=str(entry[1][0]),
            player_name=str(entry[2][0]),
            gender=str(entry[3][0]),
            club=str(entry[4][0]),
            view=str(entry[5][0]),
            slow=int(entry[6][0, 0]),
            events=entry[7][0].astype(int),
            bbox=entry[8][0].astype(float),
            split=int(entry[9][0, 0]),
        )
        annotations.append(anno)

    return annotations


def find_annotation_by_id(annotations, target_id):
    """Find a single annotation by its ID."""
    for a in annotations:
        if a.id == target_id:
            return a
    return None


# ---------------------------------------------------------------------------
# Video helpers
# ---------------------------------------------------------------------------

def open_video(youtube_id):
    """Open a YouTube video file, trying multiple extensions."""
    for ext in ("mp4", "mkv", "webm"):
        path = YOUTUBE_DIR / f"{youtube_id}.{ext}"
        if path.exists():
            cap = cv2.VideoCapture(str(path))
            if cap.isOpened():
                return cap, path
            cap.release()
    return None, None


def extract_frame(cap, frame_num):
    """Extract a single frame from a video capture."""
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_num)
    ret, frame = cap.read()
    return frame if ret else None


def get_video_info(cap):
    """Get basic video metadata."""
    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    codec = int(cap.get(cv2.CAP_PROP_FOURCC))
    codec_str = "".join([chr((codec >> (8 * i)) & 0xFF) for i in range(4)])
    return {
        "fps": fps,
        "total_frames": total_frames,
        "width": width,
        "height": height,
        "codec": codec_str,
        "duration_s": total_frames / fps if fps > 0 else 0,
    }


# ---------------------------------------------------------------------------
# Individual video spot-check
# ---------------------------------------------------------------------------

def spot_check_one(anno, output_dir):
    """Spot-check a single annotation against its video file."""
    result = {
        "id": anno.id,
        "youtube_id": anno.youtube_id,
        "player": anno.player_name,
        "club": anno.club,
        "view": anno.view,
        "slow": anno.slow,
        "events": anno.events.tolist(),
    }

    # Phase durations (in frames)
    result["phase_durations"] = {
        "pre_to_address": anno.events[1] - anno.events[0],
        "address_to_toeup": anno.events[2] - anno.events[1],
        "backswing_full": anno.events[4] - anno.events[2],       # TOE-UP to TOP
        "downswing": anno.events[6] - anno.events[4],            # TOP to IMPACT
        "follow_through": anno.events[8] - anno.events[6],       # IMPACT to FINISH
        "finish_to_post": anno.events[9] - anno.events[8],
        "total_swing": anno.events[8] - anno.events[2],          # TOE-UP to FINISH
    }

    # Open video
    cap, video_path = open_video(anno.youtube_id)
    if cap is None:
        result["video_status"] = "NOT_FOUND"
        result["video_path"] = None
        print(f"  [SKIP] Video not found for {anno.youtube_id}")
        return result

    result["video_status"] = "OK"
    result["video_path"] = str(video_path)

    info = get_video_info(cap)
    result["video_info"] = info

    # Validate events within video bounds
    result["events_in_bounds"] = all(0 <= e < info["total_frames"] for e in anno.events)
    result["events_monotonic"] = all(anno.events[i] <= anno.events[i + 1] for i in range(9))

    # Extract key frames
    anno_dir = output_dir / f"id_{anno.id:04d}"
    anno_dir.mkdir(parents=True, exist_ok=True)

    frames_to_extract = {
        "top": anno.events[4],
        "pre_impact_minus2": anno.events[6] - 2,
        "impact": anno.events[6],
        "post_impact_plus2": anno.events[6] + 2,
    }

    result["extracted_frames"] = {}
    for name, frame_num in frames_to_extract.items():
        frame = extract_frame(cap, frame_num)
        if frame is not None:
            out_path = anno_dir / f"{name}_frame{frame_num}.png"
            cv2.imwrite(str(out_path), frame)
            result["extracted_frames"][name] = {
                "frame_num": int(frame_num),
                "time_s": round(frame_num / info["fps"], 3) if info["fps"] > 0 else 0,
                "saved_to": str(out_path),
            }
        else:
            result["extracted_frames"][name] = {"frame_num": int(frame_num), "error": "read_failed"}

    # Check if training clips exist for this annotation
    training_clips = {}
    for cls_name in ["backswing", "downswing", "impact", "follow_through", "no_swing"]:
        cls_dir = TRAINING_DIR / cls_name
        if cls_dir.exists():
            clips = list(cls_dir.glob(f"golfdb_{anno.id:04d}_*.mp4"))
            clip_details = []
            for clip_path in clips:
                clip_cap = cv2.VideoCapture(str(clip_path))
                if clip_cap.isOpened():
                    clip_info = {
                        "filename": clip_path.name,
                        "frames": int(clip_cap.get(cv2.CAP_PROP_FRAME_COUNT)),
                        "fps": clip_cap.get(cv2.CAP_PROP_FPS),
                        "size_kb": round(clip_path.stat().st_size / 1024, 1),
                    }
                    clip_cap.release()
                    clip_details.append(clip_info)
            training_clips[cls_name] = clip_details
    result["training_clips"] = training_clips

    # For impact clip: check if impact frame is near the center
    impact_clips = training_clips.get("impact", [])
    if impact_clips:
        clip = impact_clips[0]
        clip_frames = clip["frames"]
        # Impact should be at center of 15-frame clip = frame ~7
        # The clip starts at impact_frame - 7, so impact is at position 7
        result["impact_clip_analysis"] = {
            "clip_frames": clip_frames,
            "expected_impact_position": clip_frames // 2,
            "notes": "Impact frame should be near center of clip",
        }

    cap.release()
    return result


# ---------------------------------------------------------------------------
# Dataset-wide quality checks
# ---------------------------------------------------------------------------

def dataset_wide_checks(annotations):
    """Run dataset-wide quality checks across all 1400 annotations."""
    results = {
        "total_annotations": len(annotations),
        "normal_speed": 0,
        "slow_motion": 0,
        "non_monotonic": [],
        "impossibly_short_phases": [],
        "downswing_durations": [],
        "backswing_durations": [],
        "impact_to_finish_durations": [],
        "total_swing_durations": [],
        "missing_videos": 0,
        "available_videos": 0,
    }

    for anno in annotations:
        if anno.is_slow_motion:
            results["slow_motion"] += 1
        else:
            results["normal_speed"] += 1

        # Check monotonicity
        monotonic = all(anno.events[i] <= anno.events[i + 1] for i in range(9))
        if not monotonic:
            violations = []
            for i in range(9):
                if anno.events[i] > anno.events[i + 1]:
                    violations.append(f"{EVENT_NAMES[i]}({anno.events[i]})>{EVENT_NAMES[i+1]}({anno.events[i+1]})")
            results["non_monotonic"].append({
                "id": anno.id,
                "youtube_id": anno.youtube_id,
                "events": anno.events.tolist(),
                "violations": violations,
            })
            continue  # Skip duration stats for non-monotonic

        # Phase durations (only for normal-speed)
        if not anno.is_slow_motion:
            ds_dur = anno.events[6] - anno.events[4]  # TOP to IMPACT
            bs_dur = anno.events[4] - anno.events[2]  # TOE-UP to TOP
            ft_dur = anno.events[8] - anno.events[6]  # IMPACT to FINISH
            total_dur = anno.events[8] - anno.events[2]  # TOE-UP to FINISH

            results["downswing_durations"].append(ds_dur)
            results["backswing_durations"].append(bs_dur)
            results["impact_to_finish_durations"].append(ft_dur)
            results["total_swing_durations"].append(total_dur)

            # Check for impossibly short phases (<3 frames)
            phases = [
                ("address_to_toeup", anno.events[2] - anno.events[1]),
                ("backswing", bs_dur),
                ("downswing", ds_dur),
                ("follow_through", ft_dur),
            ]
            for phase_name, dur in phases:
                if 0 < dur < 3:
                    results["impossibly_short_phases"].append({
                        "id": anno.id,
                        "phase": phase_name,
                        "duration_frames": dur,
                    })

        # Check video availability
        video_found = False
        for ext in ("mp4", "mkv", "webm"):
            if (YOUTUBE_DIR / f"{anno.youtube_id}.{ext}").exists():
                video_found = True
                break
        if video_found:
            results["available_videos"] += 1
        else:
            results["missing_videos"] += 1

    return results


def print_dataset_report(checks):
    """Print a formatted dataset-wide quality report."""
    print("\n" + "=" * 70)
    print("DATASET-WIDE QUALITY CHECKS")
    print("=" * 70)

    print(f"\nTotal annotations:  {checks['total_annotations']}")
    print(f"Normal-speed:       {checks['normal_speed']}")
    print(f"Slow-motion:        {checks['slow_motion']}")
    print(f"Videos available:   {checks['available_videos']}")
    print(f"Videos missing:     {checks['missing_videos']}")

    # Non-monotonic events
    nm = checks["non_monotonic"]
    print(f"\n--- Non-Monotonic Events: {len(nm)} annotations ---")
    for entry in nm[:10]:
        print(f"  ID {entry['id']:04d}: {', '.join(entry['violations'])}")
    if len(nm) > 10:
        print(f"  ... and {len(nm) - 10} more")

    # Impossibly short phases
    short = checks["impossibly_short_phases"]
    print(f"\n--- Impossibly Short Phases (<3 frames): {len(short)} instances ---")
    phase_counts = {}
    for entry in short:
        phase_counts[entry["phase"]] = phase_counts.get(entry["phase"], 0) + 1
    for phase, count in sorted(phase_counts.items()):
        print(f"  {phase}: {count} annotations")
    if short:
        print("  Examples:")
        for entry in short[:5]:
            print(f"    ID {entry['id']:04d} {entry['phase']}: {entry['duration_frames']} frames")

    # Duration statistics (normal-speed only)
    print("\n--- Phase Duration Statistics (normal-speed, in frames @30fps) ---")
    for name, durations in [
        ("Backswing (toe-up to top)", checks["backswing_durations"]),
        ("Downswing (top to impact)", checks["downswing_durations"]),
        ("Follow-through (impact to finish)", checks["impact_to_finish_durations"]),
        ("Total swing (toe-up to finish)", checks["total_swing_durations"]),
    ]:
        if not durations:
            continue
        arr = np.array(durations)
        print(f"\n  {name}:")
        print(f"    Count:   {len(arr)}")
        print(f"    Median:  {np.median(arr):.0f} frames ({np.median(arr)/30*1000:.0f} ms)")
        print(f"    Mean:    {np.mean(arr):.1f} frames ({np.mean(arr)/30*1000:.0f} ms)")
        print(f"    Std:     {np.std(arr):.1f} frames")
        print(f"    Min:     {np.min(arr)} frames ({np.min(arr)/30*1000:.0f} ms)")
        print(f"    Max:     {np.max(arr)} frames ({np.max(arr)/30*1000:.0f} ms)")
        print(f"    P5/P95:  {np.percentile(arr, 5):.0f} / {np.percentile(arr, 95):.0f} frames")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 70)
    print("GolfDB DATASET VERIFICATION")
    print("=" * 70)

    # Load all annotations
    print("\nLoading annotations from .mat file...")
    annotations = load_all_annotations()
    print(f"Loaded {len(annotations)} annotations")

    # Create output directory
    VERIFY_DIR.mkdir(parents=True, exist_ok=True)

    # -----------------------------------------------------------------------
    # Part 1: Spot-check 10 specific videos
    # -----------------------------------------------------------------------
    print("\n" + "=" * 70)
    print("PART 1: SPOT-CHECKING 10 ANNOTATIONS")
    print("=" * 70)

    spot_results = []
    for target_id in SPOT_CHECK_IDS:
        anno = find_annotation_by_id(annotations, target_id)
        if anno is None:
            print(f"\n[ERROR] Annotation ID {target_id} not found!")
            continue

        print(f"\n--- ID {anno.id:04d} | {anno.player_name} | {anno.club} | {anno.view} | slow={anno.slow} ---")
        print(f"  YouTube: {anno.youtube_id}")
        print(f"  Events: {anno.events.tolist()}")

        result = spot_check_one(anno, VERIFY_DIR)
        spot_results.append(result)

        if result["video_status"] == "OK":
            info = result["video_info"]
            print(f"  Video: {info['width']}x{info['height']} @ {info['fps']:.1f}fps, "
                  f"{info['total_frames']} frames ({info['duration_s']:.1f}s), codec={info['codec']}")
            print(f"  Events in bounds: {result['events_in_bounds']}")
            print(f"  Events monotonic: {result['events_monotonic']}")

            durations = result["phase_durations"]
            print(f"  Downswing: {durations['downswing']} frames "
                  f"({durations['downswing']/info['fps']*1000:.0f}ms)")
            print(f"  Full swing: {durations['total_swing']} frames "
                  f"({durations['total_swing']/info['fps']*1000:.0f}ms)")

            # Report training clips
            clips = result["training_clips"]
            total_clips = sum(len(v) for v in clips.values())
            print(f"  Training clips: {total_clips} total")
            for cls_name, cls_clips in clips.items():
                if cls_clips:
                    for c in cls_clips:
                        print(f"    {cls_name}: {c['filename']} ({c['frames']}f, {c['size_kb']}KB)")

            # Report extracted frames
            for name, finfo in result["extracted_frames"].items():
                if "error" not in finfo:
                    print(f"  Frame [{name}]: frame#{finfo['frame_num']} "
                          f"@ {finfo['time_s']}s -> {Path(finfo['saved_to']).name}")

    # -----------------------------------------------------------------------
    # Part 2: Dataset-wide quality checks
    # -----------------------------------------------------------------------
    checks = dataset_wide_checks(annotations)
    print_dataset_report(checks)

    # -----------------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------------
    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)

    videos_found = sum(1 for r in spot_results if r["video_status"] == "OK")
    videos_total = len(spot_results)
    print(f"\nSpot-check: {videos_found}/{videos_total} videos found and inspected")

    all_monotonic = all(r.get("events_monotonic", False) for r in spot_results if r["video_status"] == "OK")
    all_in_bounds = all(r.get("events_in_bounds", False) for r in spot_results if r["video_status"] == "OK")
    print(f"All events monotonic: {all_monotonic}")
    print(f"All events in bounds: {all_in_bounds}")

    print(f"\nVerification frames saved to: {VERIFY_DIR}/")
    print(f"Non-monotonic annotations (dataset-wide): {len(checks['non_monotonic'])}")
    print(f"Impossibly short phases (<3 frames): {len(checks['impossibly_short_phases'])}")

    ds = checks["downswing_durations"]
    if ds:
        print(f"Median downswing duration (normal-speed): {np.median(ds):.0f} frames "
              f"({np.median(ds)/30*1000:.0f}ms)")

    print("\nDone!")


if __name__ == "__main__":
    main()
