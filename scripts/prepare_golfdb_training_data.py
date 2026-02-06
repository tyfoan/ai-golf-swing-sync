#!/usr/bin/env python3
"""
GolfDB -> Create ML Action Classifier training data pipeline.

Converts GolfDB annotations + full-resolution videos into two-class
(swing / idle) video clips suitable for Create ML Action Classification.

Input:
    - GolfDB annotations (.pkl or .mat)
    - Full-resolution videos (Kaggle "GolfDB Entire Image" or youtube_videos/)

Output:
    training_data_action_classifier/
        swing/          (~1400 clips, 1.5-4s each)
        idle/           (~1400 clips from non-swing segments)

Prerequisites:
    pip install scipy numpy opencv-python tqdm pandas
"""

import os
import sys
import pickle
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Paths
SCRIPT_DIR = Path(__file__).parent
ML_TRAINING_DIR = SCRIPT_DIR.parent / "ml-training"
GOLFDB_DIR = ML_TRAINING_DIR / "golfdb"
OUTPUT_DIR = ML_TRAINING_DIR / "training_data_action_classifier"

# Video source priority:
# 1. youtube_videos/ (full-resolution downloads)
# 2. golfdb/videos_160/ (160x160 preprocessed -- fallback, not ideal for pose)
YOUTUBE_VIDEOS_DIR = ML_TRAINING_DIR / "youtube_videos"
VIDEOS_160_DIR = GOLFDB_DIR / "videos_160"

# Annotation sources
PKL_FILE = GOLFDB_DIR / "GolfDB.pkl"
MAT_FILE = GOLFDB_DIR / "golfDB.mat"

# Config
MIN_CLIP_DURATION = 0.5   # seconds -- Create ML minimum
MAX_CLIP_DURATION = 6.0   # seconds -- cap very long swings
IDLE_CLIP_DURATION = 2.5  # seconds for idle clips
FPS_ASSUMED = 30           # GolfDB default


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

            # Need at least address (index 0) and end (index 9) for swing bounds
            if len(events) < 10:
                continue

            # Skip entries where events are all zeros
            if all(e == 0 for e in events):
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
    # Priority 1: full-resolution youtube downloads
    if YOUTUBE_VIDEOS_DIR.exists():
        for ext in (".mp4", ".mkv", ".webm"):
            # Try youtube_id-based naming
            p = YOUTUBE_VIDEOS_DIR / f"{youtube_id}{ext}"
            if p.exists():
                return p
            # Try video_id-based naming
            p = YOUTUBE_VIDEOS_DIR / f"{video_id}{ext}"
            if p.exists():
                return p
            p = YOUTUBE_VIDEOS_DIR / f"{video_id:04d}{ext}"
            if p.exists():
                return p

    # Priority 2: 160x160 preprocessed (fallback)
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


def process_annotations(annotations: List[Dict]) -> Dict[str, int]:
    """Extract swing and idle clips from annotated videos."""
    swing_dir = OUTPUT_DIR / "swing"
    idle_dir = OUTPUT_DIR / "idle"
    swing_dir.mkdir(parents=True, exist_ok=True)
    idle_dir.mkdir(parents=True, exist_ok=True)

    stats = {"swing": 0, "idle": 0, "skipped_no_video": 0, "skipped_slow": 0, "errors": 0}
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

        # Skip slow-motion clips (different frame timing)
        if slow == 1:
            stats["skipped_slow"] += 1
            continue

        video_path = find_video(video_id, youtube_id)
        if video_path is None:
            stats["skipped_no_video"] += 1
            continue

        fps = get_video_fps(video_path)

        # --- Swing clip: events[0] (address) to events[9] (end) ---
        address_frame = events[0]
        end_frame = events[9] if len(events) > 9 else events[-1]

        swing_output = swing_dir / f"golfdb_{video_id:04d}_swing.mp4"
        if extract_clip(video_path, address_frame, end_frame, swing_output, fps):
            stats["swing"] += 1
            view_counts[view] = view_counts.get(view, 0) + 1
        else:
            stats["errors"] += 1

        # --- Idle clip: 2-3s before address (pre-swing setup) ---
        idle_frames = int(IDLE_CLIP_DURATION * fps)
        idle_start = max(0, address_frame - idle_frames)
        idle_end = max(0, address_frame - 3)  # end a few frames before swing

        if idle_end > idle_start:
            idle_output = idle_dir / f"golfdb_{video_id:04d}_idle_pre.mp4"
            if extract_clip(video_path, idle_start, idle_end, idle_output, fps):
                stats["idle"] += 1

        # --- Bonus idle: post-swing (after finish) ---
        if len(events) > 9:
            finish_frame = events[9]
            post_idle_end = finish_frame + int(IDLE_CLIP_DURATION * fps)
            post_output = idle_dir / f"golfdb_{video_id:04d}_idle_post.mp4"
            if extract_clip(video_path, finish_frame + 5, post_idle_end, post_output, fps):
                stats["idle"] += 1

    return {**stats, "views": view_counts}


def print_stats(stats: Dict):
    """Print extraction statistics."""
    print("\n" + "=" * 60)
    print("Extraction Statistics")
    print("=" * 60)
    print(f"  Swing clips:        {stats.get('swing', 0)}")
    print(f"  Idle clips:         {stats.get('idle', 0)}")
    print(f"  Skipped (no video): {stats.get('skipped_no_video', 0)}")
    print(f"  Skipped (slow-mo):  {stats.get('skipped_slow', 0)}")
    print(f"  Errors:             {stats.get('errors', 0)}")

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
    print("GolfDB -> Create ML Action Classifier Pipeline")
    print("=" * 60)

    if not verify_ffmpeg():
        print("\nffmpeg is required. Install with: brew install ffmpeg")
        sys.exit(1)

    annotations = load_annotations()
    if not annotations:
        print("\nNo annotations found. Ensure golfDB.pkl or golfDB.mat exists in:")
        print(f"  {GOLFDB_DIR}")
        sys.exit(1)

    # Show annotation summary
    views = {}
    slow_count = 0
    for ann in annotations:
        v = ann["view"]
        views[v] = views.get(v, 0) + 1
        if ann["slow"]:
            slow_count += 1

    print(f"\n  Total annotations: {len(annotations)}")
    print(f"  Slow-motion: {slow_count} (will skip)")
    print(f"  Views: {dict(sorted(views.items(), key=lambda x: -x[1]))}")

    # Process
    stats = process_annotations(annotations)
    print_stats(stats)

    print("\nNext steps:")
    print("1. Record 20-30 front-camera swings -> add to swing/ folder")
    print("2. Record 20-30 front-camera idle clips -> add to idle/ folder")
    print("3. Open Create ML -> Action Classification -> train on this data")
    print("4. Export GolfSwingClassifier.mlmodel -> add to Xcode project")


if __name__ == "__main__":
    main()
