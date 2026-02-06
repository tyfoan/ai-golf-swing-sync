#!/usr/bin/env python3
"""
GolfDB -> Create ML Action Classifier training data pipeline.

Converts GolfDB annotations + full-resolution videos into 4-class
video clips for Create ML Action Classification with impact detection.

Classes:
    backswing       - events[0] (address) to events[3] (top of backswing)
    downswing       - events[3] (top) to events[5] (impact)
    follow_through  - events[5] (impact) to events[8] (finish)
    no_swing        - pre-swing idle + post-swing standing

The downswing→follow_through transition = IMPACT FRAME (sync point).

Input:
    - GolfDB annotations (.pkl or .mat)
    - Full-resolution videos (Kaggle "GolfDB Entire Image" or youtube_videos/)

Output:
    training_data_action_classifier/
        backswing/       (~1400 clips)
        downswing/       (~1400 clips)
        follow_through/  (~1400 clips)
        no_swing/        (~1400 clips)

Prerequisites:
    pip install scipy numpy opencv-python tqdm pandas
"""

import os
import sys
import pickle
import subprocess
from pathlib import Path
from typing import Dict, List, Optional

# Paths
SCRIPT_DIR = Path(__file__).parent
ML_TRAINING_DIR = SCRIPT_DIR.parent / "ml-training"
GOLFDB_DIR = ML_TRAINING_DIR / "golfdb"
OUTPUT_DIR = ML_TRAINING_DIR / "training_data_action_classifier"

# Video source priority:
# 1. youtube_videos/ (full-resolution downloads)
# 2. golfdb/videos_160/ (160x160 preprocessed — fallback, less ideal for pose)
YOUTUBE_VIDEOS_DIR = ML_TRAINING_DIR / "youtube_videos"
VIDEOS_160_DIR = GOLFDB_DIR / "videos_160"

# Annotation sources
PKL_FILE = GOLFDB_DIR / "GolfDB.pkl"
MAT_FILE = GOLFDB_DIR / "golfDB.mat"

# GolfDB event indices (10 events total):
#   [0] address  [1] toe-up  [2] mid-backswing  [3] top
#   [4] mid-downswing  [5] impact  [6] mid-follow-through
#   [7] finish  [8] end-of-swing  [9] end-frame

# Phase boundaries (event indices):
PHASES = {
    "backswing":      (0, 3),   # address → top of backswing
    "downswing":      (3, 5),   # top → impact (KEY: very short ~150ms)
    "follow_through": (5, 8),   # impact → finish
}

# Config
MIN_CLIP_DURATION = 0.3   # seconds — Create ML minimum
MAX_CLIP_DURATION = 6.0   # seconds — cap long clips
NO_SWING_DURATION = 2.0   # seconds for idle clips
FPS_ASSUMED = 30


def load_annotations_pkl() -> List[Dict]:
    """Load annotations from GolfDB.pkl (pandas DataFrame)."""
    try:
        import pandas as pd
    except ImportError:
        print("  pandas not available, skipping .pkl")
        return []

    if not PKL_FILE.exists():
        return []

    print(f"  Loading {PKL_FILE.name}...")
    df = pd.read_pickle(str(PKL_FILE))

    annotations = []
    for _, row in df.iterrows():
        try:
            video_id = int(row.get("id", 0))
            youtube_id = str(row.get("youtube_id", ""))
            events = row.get("events", [])
            view = str(row.get("view", "unknown"))
            slow = int(row.get("slow", 0))

            if not isinstance(events, (list, tuple)):
                events = list(events)

            if len(events) < 10 or all(e == 0 for e in events):
                continue

            annotations.append({
                "id": video_id,
                "youtube_id": youtube_id,
                "events": [int(e) for e in events],
                "view": view,
                "slow": slow,
            })
        except Exception:
            continue

    return annotations


def load_annotations_mat() -> List[Dict]:
    """Load annotations from golfDB.mat (scipy)."""
    try:
        from scipy.io import loadmat
    except ImportError:
        print("  scipy not available, skipping .mat")
        return []

    if not MAT_FILE.exists():
        return []

    print(f"  Loading {MAT_FILE.name}...")
    data = loadmat(str(MAT_FILE))
    golfdb = data["golfDB"][0]

    annotations = []
    for entry in golfdb:
        try:
            video_id = int(entry["id"][0][0])
            events = entry["events"].flatten().tolist()
            youtube_id = str(entry["youtube_id"][0])
            view = str(entry["view"][0]) if "view" in entry.dtype.names else "unknown"
            slow = int(entry["slow"][0][0]) if "slow" in entry.dtype.names else 0

            if len(events) < 10 or all(e == 0 for e in events):
                continue

            annotations.append({
                "id": video_id,
                "youtube_id": youtube_id,
                "events": [int(e) for e in events],
                "view": view,
                "slow": slow,
            })
        except Exception:
            continue

    return annotations


def load_annotations() -> List[Dict]:
    """Load annotations from best available source."""
    print("Loading GolfDB annotations...")
    anns = load_annotations_pkl()
    if not anns:
        anns = load_annotations_mat()
    if not anns:
        print("  No annotations found!")
        return []
    print(f"  Loaded {len(anns)} annotations")
    return anns


def find_video(video_id: int, youtube_id: str) -> Optional[Path]:
    """Find video file from available sources."""
    if YOUTUBE_VIDEOS_DIR.exists():
        for ext in (".mp4", ".mkv", ".webm"):
            for name in (youtube_id, str(video_id), f"{video_id:04d}"):
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


def extract_clip(
    video_path: Path,
    start_frame: int,
    end_frame: int,
    output_path: Path,
    fps: float,
) -> bool:
    """Extract a clip from video using ffmpeg."""
    start_sec = max(0, start_frame / fps)
    duration = (end_frame - start_frame) / fps

    if duration < MIN_CLIP_DURATION:
        return False
    if duration > MAX_CLIP_DURATION:
        duration = MAX_CLIP_DURATION

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


def process_annotations(annotations: List[Dict]) -> Dict:
    """Extract 4-class clips from annotated videos."""
    for phase in list(PHASES.keys()) + ["no_swing"]:
        (OUTPUT_DIR / phase).mkdir(parents=True, exist_ok=True)

    stats = {phase: 0 for phase in list(PHASES.keys()) + ["no_swing"]}
    stats.update({"skipped_no_video": 0, "skipped_slow": 0, "errors": 0})
    view_counts: Dict[str, int] = {}

    try:
        from tqdm import tqdm
        iterator = tqdm(annotations, desc="Extracting clips")
    except ImportError:
        print("  (install tqdm for progress bar)")
        iterator = annotations

    for ann in iterator:
        video_id = ann["id"]
        youtube_id = ann["youtube_id"]
        events = ann["events"]
        view = ann["view"]
        slow = ann["slow"]

        if slow == 1:
            stats["skipped_slow"] += 1
            continue

        video_path = find_video(video_id, youtube_id)
        if video_path is None:
            stats["skipped_no_video"] += 1
            continue

        fps = get_video_fps(video_path)

        # Extract each swing phase
        for phase_name, (start_evt, end_evt) in PHASES.items():
            start_frame = events[start_evt]
            end_frame = events[end_evt]

            # Add small padding (2 frames) to avoid cutting exactly on boundaries
            padded_start = max(0, start_frame - 2)
            padded_end = end_frame + 2

            output = OUTPUT_DIR / phase_name / f"golfdb_{video_id:04d}_{phase_name}.mp4"
            if extract_clip(video_path, padded_start, padded_end, output, fps):
                stats[phase_name] += 1
                view_counts[view] = view_counts.get(view, 0) + 1
            else:
                stats["errors"] += 1

        # Extract no_swing: pre-swing idle (before address)
        address_frame = events[0]
        idle_frames = int(NO_SWING_DURATION * fps)
        idle_start = max(0, address_frame - idle_frames)
        idle_end = max(0, address_frame - 3)

        if idle_end > idle_start:
            output = OUTPUT_DIR / "no_swing" / f"golfdb_{video_id:04d}_pre.mp4"
            if extract_clip(video_path, idle_start, idle_end, output, fps):
                stats["no_swing"] += 1

        # Extract no_swing: post-swing standing (after finish)
        if len(events) > 9:
            finish_frame = events[8]
            post_end = finish_frame + int(NO_SWING_DURATION * fps)
            output = OUTPUT_DIR / "no_swing" / f"golfdb_{video_id:04d}_post.mp4"
            if extract_clip(video_path, finish_frame + 5, post_end, output, fps):
                stats["no_swing"] += 1

    stats["views"] = view_counts
    return stats


def print_stats(stats: Dict):
    """Print extraction statistics."""
    print("\n" + "=" * 60)
    print("Extraction Statistics")
    print("=" * 60)
    for phase in list(PHASES.keys()) + ["no_swing"]:
        print(f"  {phase:20s}: {stats.get(phase, 0)}")
    print(f"  {'skipped (no video)':20s}: {stats.get('skipped_no_video', 0)}")
    print(f"  {'skipped (slow-mo)':20s}: {stats.get('skipped_slow', 0)}")
    print(f"  {'errors':20s}: {stats.get('errors', 0)}")

    views = stats.get("views", {})
    if views:
        print("\n  View distribution:")
        for view, count in sorted(views.items(), key=lambda x: -x[1]):
            print(f"    {view}: {count}")

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
    print("GolfDB -> 4-Class Action Classifier Pipeline")
    print("  Classes: backswing, downswing, follow_through, no_swing")
    print("  Impact = downswing->follow_through transition")
    print("=" * 60)

    if not verify_ffmpeg():
        print("\nffmpeg is required. Install with: brew install ffmpeg")
        sys.exit(1)

    annotations = load_annotations()
    if not annotations:
        print("\nNo annotations found. Ensure golfDB.pkl or golfDB.mat exists in:")
        print(f"  {GOLFDB_DIR}")
        sys.exit(1)

    # Summary
    views = {}
    slow_count = 0
    for ann in annotations:
        views[ann["view"]] = views.get(ann["view"], 0) + 1
        if ann["slow"]:
            slow_count += 1

    print(f"\n  Total annotations: {len(annotations)}")
    print(f"  Slow-motion: {slow_count} (will skip)")
    print(f"  Views: {dict(sorted(views.items(), key=lambda x: -x[1]))}")

    stats = process_annotations(annotations)
    print_stats(stats)

    print("\nNext steps:")
    print("1. Record 20-30 front-camera clips per class -> add to folders")
    print("2. Open Create ML -> Action Classification -> train (300+ iterations)")
    print("3. Export GolfSwingClassifier_v2.mlmodel -> add to Xcode project")
    print("4. The downswing->follow_through transition = impact for sync")


if __name__ == "__main__":
    main()
