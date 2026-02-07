#!/usr/bin/env python3
"""
GolfDB -> Create ML Action Classifier v3 training data pipeline.

Fixes from v2:
  - backswing starts at toe_up (event[2]), not address — removes standing-still confusion
  - no_swing gains clips from pre-address, post-finish, AND address→toe_up
  - All clips padded to minimum 1.5s (75% of 2.0s prediction window)
  - Balanced classes (~1300 clips each)

Classes:
    backswing       - events[2] (toe_up) to events[4] (top)
    downswing       - events[4] (top) to events[6] (impact)
    follow_through  - events[6] (impact) to events[8] (finish)
    no_swing        - pre-address + post-finish + address→toe_up standing

GolfDB events (10 elements):
    [0]=video_start  [1]=address  [2]=toe_up  [3]=mid_backswing  [4]=top
    [5]=mid_downswing  [6]=impact  [7]=mid_follow  [8]=finish  [9]=video_end

Prerequisites:
    pip install scipy pandas tqdm
    brew install ffmpeg
"""

import os
import sys
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from collections import Counter

SCRIPT_DIR = Path(__file__).parent
ML_TRAINING_DIR = SCRIPT_DIR.parent / "ml-training"
GOLFDB_DIR = ML_TRAINING_DIR / "golfdb"
OUTPUT_DIR = ML_TRAINING_DIR / "training_data_v3"

YOUTUBE_VIDEOS_DIR = ML_TRAINING_DIR / "youtube_videos"
VIDEOS_160_DIR = GOLFDB_DIR / "videos_160"

PKL_FILE = GOLFDB_DIR / "GolfDB.pkl"

# Fixed class boundaries (event indices into 10-element array)
SWING_PHASES = {
    "backswing":      (2, 4),   # toe_up → top (actual club movement only)
    "downswing":      (4, 6),   # top → impact
    "follow_through": (6, 8),   # impact → finish
}

# no_swing sources — multiple segments per video
NO_SWING_SOURCES = [
    (0, 2),   # video_start → toe_up (standing/setup, longest segment)
    (8, 9),   # finish → video_end (post-swing standing)
    (1, 2),   # address → toe_up (standing still with club, bonus clips)
]

MIN_CLIP_DURATION = 1.5   # seconds — 75% of 2.0s prediction window
MAX_CLIP_DURATION = 4.0   # seconds — cap overly long clips
FPS_ASSUMED = 30


def load_annotations() -> List[Dict]:
    """Load GolfDB annotations from pickle file."""
    print("Loading GolfDB annotations...")

    try:
        import pandas as pd
    except ImportError:
        print("  pandas required: pip install pandas")
        sys.exit(1)

    if not PKL_FILE.exists():
        print(f"  Not found: {PKL_FILE}")
        sys.exit(1)

    df = pd.read_pickle(str(PKL_FILE))
    annotations = []

    for _, row in df.iterrows():
        try:
            video_id = int(row["id"])
            events = [int(e) for e in row["events"]]
            view = str(row.get("view", "unknown"))
            slow = int(row.get("slow", 0))

            if len(events) != 10:
                continue
            # Skip entries where events are all zero or invalid
            if all(e == 0 for e in events):
                continue

            annotations.append({
                "id": video_id,
                "events": events,
                "view": view,
                "slow": slow,
            })
        except Exception:
            continue

    print(f"  Loaded {len(annotations)} annotations")
    return annotations


def find_video(video_id: int) -> Optional[Path]:
    """Find video file, preferring full-resolution over 160x160."""
    if YOUTUBE_VIDEOS_DIR.exists():
        for ext in (".mp4", ".mkv", ".webm"):
            for name in (str(video_id), f"{video_id:04d}"):
                p = YOUTUBE_VIDEOS_DIR / f"{name}{ext}"
                if p.exists():
                    return p

    if VIDEOS_160_DIR.exists():
        for name in (f"{video_id}.mp4", f"{video_id:04d}.mp4"):
            p = VIDEOS_160_DIR / name
            if p.exists():
                return p

    return None


def get_video_fps(video_path: Path) -> float:
    """Get video FPS using ffprobe."""
    try:
        cmd = [
            "ffprobe", "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=r_frame_rate",
            "-of", "csv=p=0",
            str(video_path),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0 and "/" in result.stdout.strip():
            num, den = result.stdout.strip().split("/")
            return float(num) / float(den)
    except Exception:
        pass
    return FPS_ASSUMED


def get_video_frame_count(video_path: Path) -> Optional[int]:
    """Get total frame count using ffprobe."""
    try:
        cmd = [
            "ffprobe", "-v", "error",
            "-select_streams", "v:0",
            "-count_frames",
            "-show_entries", "stream=nb_read_frames",
            "-of", "csv=p=0",
            str(video_path),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return int(result.stdout.strip())
    except Exception:
        pass
    return None


def extract_clip(
    video_path: Path,
    start_sec: float,
    duration: float,
    output_path: Path,
) -> bool:
    """Extract a clip from video using ffmpeg."""
    if duration < 0.3:
        return False
    if duration > MAX_CLIP_DURATION:
        duration = MAX_CLIP_DURATION

    start_sec = max(0, start_sec)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-ss", f"{start_sec:.3f}",
        "-i", str(video_path),
        "-t", f"{duration:.3f}",
        "-c:v", "libx264",
        "-preset", "fast",
        "-crf", "23",
        "-an",
        str(output_path),
    ]

    try:
        subprocess.run(cmd, capture_output=True, timeout=30)
        return output_path.exists() and output_path.stat().st_size > 1000
    except Exception:
        return False


def pad_segment(
    center_start_sec: float,
    center_end_sec: float,
    min_duration: float,
    video_duration_sec: float,
) -> Tuple[float, float]:
    """Pad a short segment symmetrically to reach min_duration.

    Returns (padded_start, padded_end) in seconds.
    """
    actual = center_end_sec - center_start_sec
    if actual >= min_duration:
        return center_start_sec, center_end_sec

    needed = min_duration - actual
    pad_before = needed / 2.0
    pad_after = needed / 2.0

    padded_start = center_start_sec - pad_before
    padded_end = center_end_sec + pad_after

    # Clamp to video bounds
    if padded_start < 0:
        padded_end += -padded_start
        padded_start = 0
    if padded_end > video_duration_sec:
        padded_start -= padded_end - video_duration_sec
        padded_start = max(0, padded_start)
        padded_end = video_duration_sec

    return padded_start, padded_end


def process_annotations(annotations: List[Dict]) -> Dict:
    """Extract 4-class clips with fixed boundaries and padding."""
    all_classes = list(SWING_PHASES.keys()) + ["no_swing"]
    for cls in all_classes:
        (OUTPUT_DIR / cls).mkdir(parents=True, exist_ok=True)

    stats = {cls: 0 for cls in all_classes}
    stats.update({"skipped_no_video": 0, "skipped_slow": 0, "errors": 0})
    duration_stats = {cls: [] for cls in all_classes}

    try:
        from tqdm import tqdm
        iterator = tqdm(annotations, desc="Extracting clips")
    except ImportError:
        print("  (install tqdm for progress bar)")
        iterator = annotations

    for ann in iterator:
        video_id = ann["id"]
        events = ann["events"]
        slow = ann["slow"]

        if slow == 1:
            stats["skipped_slow"] += 1
            continue

        video_path = find_video(video_id)
        if video_path is None:
            stats["skipped_no_video"] += 1
            continue

        fps = get_video_fps(video_path)
        video_duration_sec = events[9] / fps + 1.0  # approximate

        # --- Extract swing phases ---
        for phase_name, (start_evt, end_evt) in SWING_PHASES.items():
            start_frame = events[start_evt]
            end_frame = events[end_evt]

            start_sec = start_frame / fps
            end_sec = end_frame / fps
            raw_duration = end_sec - start_sec

            # Pad short clips symmetrically
            padded_start, padded_end = pad_segment(
                start_sec, end_sec, MIN_CLIP_DURATION, video_duration_sec
            )
            clip_duration = padded_end - padded_start

            output = OUTPUT_DIR / phase_name / f"golfdb_{video_id:04d}_{phase_name}.mp4"
            if extract_clip(video_path, padded_start, clip_duration, output):
                stats[phase_name] += 1
                duration_stats[phase_name].append(clip_duration)
            else:
                stats["errors"] += 1

        # --- Extract no_swing segments ---
        for src_idx, (src_start_evt, src_end_evt) in enumerate(NO_SWING_SOURCES):
            start_frame = events[src_start_evt]
            end_frame = events[src_end_evt]

            start_sec = start_frame / fps
            end_sec = end_frame / fps
            raw_duration = end_sec - start_sec

            # Skip if the segment is too tiny even after padding would be meaningless
            if raw_duration < 0.1:
                continue

            # Pad short clips
            padded_start, padded_end = pad_segment(
                start_sec, end_sec, MIN_CLIP_DURATION, video_duration_sec
            )
            clip_duration = padded_end - padded_start

            # Cap long no_swing clips
            if clip_duration > MAX_CLIP_DURATION:
                # Take the last MAX_CLIP_DURATION seconds (closest to swing)
                padded_start = padded_end - MAX_CLIP_DURATION
                clip_duration = MAX_CLIP_DURATION

            suffix = ["pre", "post", "addr"][src_idx]
            output = OUTPUT_DIR / "no_swing" / f"golfdb_{video_id:04d}_no_swing_{suffix}.mp4"

            if extract_clip(video_path, padded_start, clip_duration, output):
                stats["no_swing"] += 1
                duration_stats["no_swing"].append(clip_duration)

    stats["duration_stats"] = duration_stats
    return stats


def print_stats(stats: Dict):
    """Print extraction statistics."""
    all_classes = list(SWING_PHASES.keys()) + ["no_swing"]

    print("\n" + "=" * 60)
    print("Extraction Statistics")
    print("=" * 60)

    for cls in all_classes:
        count = stats.get(cls, 0)
        durations = stats.get("duration_stats", {}).get(cls, [])
        if durations:
            avg_dur = sum(durations) / len(durations)
            min_dur = min(durations)
            max_dur = max(durations)
            short = sum(1 for d in durations if d < MIN_CLIP_DURATION)
            print(f"  {cls:20s}: {count:5d} clips  "
                  f"avg={avg_dur:.2f}s  min={min_dur:.2f}s  max={max_dur:.2f}s  "
                  f"(<{MIN_CLIP_DURATION}s: {short})")
        else:
            print(f"  {cls:20s}: {count:5d} clips")

    print(f"\n  {'skipped (no video)':20s}: {stats.get('skipped_no_video', 0)}")
    print(f"  {'skipped (slow-mo)':20s}: {stats.get('skipped_slow', 0)}")
    print(f"  {'errors':20s}: {stats.get('errors', 0)}")
    print(f"\n  Output: {OUTPUT_DIR}")


def verify_ffmpeg() -> bool:
    """Check ffmpeg is available."""
    try:
        result = subprocess.run(["ffmpeg", "-version"], capture_output=True)
        return result.returncode == 0
    except FileNotFoundError:
        return False


def main():
    print("=" * 60)
    print("GolfDB -> 4-Class Action Classifier v3 Pipeline")
    print("=" * 60)
    print()
    print("Fixed class boundaries:")
    print("  backswing:      toe_up → top (event 2→4)")
    print("  downswing:      top → impact (event 4→6)")
    print("  follow_through: impact → finish (event 6→8)")
    print("  no_swing:       pre-address (0→2) + post-finish (8→9) + address→toe_up (1→2)")
    print(f"  Min clip duration: {MIN_CLIP_DURATION}s (padded symmetrically)")
    print()

    if not verify_ffmpeg():
        print("ffmpeg is required. Install with: brew install ffmpeg")
        sys.exit(1)

    annotations = load_annotations()
    if not annotations:
        print("No annotations found.")
        sys.exit(1)

    # Summary
    slow_count = sum(1 for a in annotations if a["slow"])
    normal_count = len(annotations) - slow_count
    print(f"  Normal speed: {normal_count}, Slow-motion: {slow_count} (skipped)")

    stats = process_annotations(annotations)
    print_stats(stats)

    print("\nNext steps:")
    print("1. Open Create ML (Xcode -> Open Developer Tool -> Create ML)")
    print("2. Create Action Classification project")
    print(f"3. Drag '{OUTPUT_DIR}' as training data")
    print("4. Settings: prediction window=60 frames, frame rate=30fps, iterations=300+")
    print("5. Validate: no_swing accuracy should be >90%")
    print("6. Export as GolfSwingClassifier_v3.mlmodel")


if __name__ == "__main__":
    main()
