#!/usr/bin/env python3
"""
Download 50 diverse GolfDB test videos for expanded validation.

Selects a stratified sample across club types and camera views,
downloads from YouTube, trims to swing windows, and generates
ground_truth.json with impact timing.

Output: golf-sync-swingTests/youtube-tests/*.mp4 + ground_truth.json
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
import scipy.io

# Project paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
GOLFDB_MAT = os.path.join(SCRIPT_DIR, "golfdb_repo", "data", "golfDB.mat")
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "golf-sync-swingTests", "youtube-tests")

# Already in TestData/ — skip these
EXISTING_IDS = {"f1BWA5F87Jc", "iW323nsTGtU", "4HzLO88ryCU", "KR9Umr1GM-U", "tpv8QUM0G0E"}

EVENT_NAMES = [
    "pre", "address", "toe_up", "mid_backswing", "top",
    "mid_downswing", "impact", "mid_follow_through", "finish", "post",
]

TARGET_COUNT = 150


def load_candidates():
    """Load normal-speed GolfDB entries with valid events."""
    mat = scipy.io.loadmat(GOLFDB_MAT)
    db = mat["golfDB"][0]

    candidates = []
    for entry in db:
        if int(entry["slow"].flat[0]) == 1:
            continue
        yt_id = str(entry["youtube_id"].flat[0])
        events = entry["events"].flatten().tolist()
        if len(events) != 10 or any(e <= 0 for e in events):
            continue
        if yt_id in EXISTING_IDS:
            continue
        candidates.append({
            "golfdb_index": int(entry["id"].flat[0]),
            "youtube_id": yt_id,
            "player": str(entry["player"].flat[0]),
            "club": str(entry["club"].flat[0]),
            "view": str(entry["view"].flat[0]),
            "events_frames": events,
            "fps": 30,
        })
    return candidates


def select_diverse(candidates, count):
    """Stratified selection across club/view categories."""
    from collections import defaultdict

    by_category = defaultdict(list)
    for v in candidates:
        key = f"{v['club']}_{v['view']}"
        by_category[key].append(v)

    np.random.seed(42)
    selected = []

    for key in sorted(by_category.keys()):
        pool = by_category[key]
        proportion = len(pool) / len(candidates)
        n = max(1, round(proportion * count))
        np.random.shuffle(pool)
        selected.extend(pool[:n])

    np.random.shuffle(selected)

    if len(selected) > count:
        selected = selected[:count]
    elif len(selected) < count:
        selected_ids = {v["youtube_id"] for v in selected}
        remaining = [v for v in candidates if v["youtube_id"] not in selected_ids]
        np.random.shuffle(remaining)
        selected.extend(remaining[:count - len(selected)])

    return selected[:count]


def download_and_trim(video_info, output_dir):
    """Download YouTube video, trim to swing window, return ground truth."""
    yt_id = video_info["youtube_id"]
    fps = video_info["fps"]
    events = video_info["events_frames"]

    # GolfDB has 10 events: pre, address, ..., finish, post
    # Use address (idx 1) and finish (idx 8) for trim window
    address_frame = events[1]
    finish_frame = events[8]
    impact_frame = events[6]

    trim_start_sec = max(0, address_frame / fps - 1.0)
    trim_end_sec = finish_frame / fps + 1.0
    duration = trim_end_sec - trim_start_sec

    impact_time_in_clip = impact_frame / fps - trim_start_sec

    filename = f"golfdb_{yt_id}.mp4"
    output_path = os.path.join(output_dir, filename)

    if os.path.exists(output_path):
        print(f"  Already exists: {filename}")
    else:
        url = f"https://www.youtube.com/watch?v={yt_id}"
        print(f"  Downloading {yt_id} ({video_info['player']})...")

        tmp_dir = tempfile.mkdtemp()
        tmp_template = os.path.join(tmp_dir, "video.%(ext)s")

        try:
            result = subprocess.run(
                [
                    "yt-dlp",
                    "-f", "bestvideo[ext=mp4][height<=720]+bestaudio[ext=m4a]/best[ext=mp4][height<=720]",
                    "--merge-output-format", "mp4",
                    "-o", tmp_template,
                    "--no-playlist",
                    "--quiet",
                    url,
                ],
                capture_output=True,
                text=True,
            )

            if result.returncode != 0:
                print(f"  SKIP: download failed for {yt_id} — {result.stderr[:100]}")
                return None

            tmp_files = [f for f in os.listdir(tmp_dir) if f.endswith(".mp4")]
            if not tmp_files:
                print(f"  SKIP: no mp4 file for {yt_id}")
                return None
            tmp_path = os.path.join(tmp_dir, tmp_files[0])

            print(f"  Trimming {trim_start_sec:.2f}s-{trim_end_sec:.2f}s...")
            result = subprocess.run(
                [
                    "ffmpeg",
                    "-y",
                    "-ss", str(trim_start_sec),
                    "-i", tmp_path,
                    "-t", str(duration),
                    "-c:v", "libx264",
                    "-preset", "fast",
                    "-crf", "23",
                    "-an",
                    "-r", str(fps),
                    output_path,
                ],
                capture_output=True,
                text=True,
            )

            if result.returncode != 0:
                print(f"  SKIP: ffmpeg trim failed for {yt_id}")
                return None

            print(f"  Saved: {filename}")
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)

    ground_truth = {
        "filename": filename,
        "youtube_id": yt_id,
        "golfdb_index": video_info["golfdb_index"],
        "player": video_info["player"],
        "club": video_info["club"],
        "view": video_info["view"],
        "fps": fps,
        "trim_start_sec": round(trim_start_sec, 3),
        "trim_end_sec": round(trim_end_sec, 3),
        "impact_time_sec": round(impact_time_in_clip, 3),
        "events": {},
    }

    for i, name in enumerate(EVENT_NAMES):
        frame = events[i]
        time_in_clip = frame / fps - trim_start_sec
        ground_truth["events"][name] = {
            "original_frame": frame,
            "time_in_clip_sec": round(time_in_clip, 3),
        }

    return ground_truth


def main():
    if not os.path.exists(GOLFDB_MAT):
        print(f"ERROR: GolfDB annotations not found at {GOLFDB_MAT}")
        print("Run: cd ml-training && git clone https://github.com/wmcnally/golfdb golfdb_repo")
        sys.exit(1)

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Load existing ground truth to preserve already-downloaded entries
    gt_path = os.path.join(OUTPUT_DIR, "youtube_ground_truth.json")
    existing_gt = []
    if os.path.exists(gt_path):
        with open(gt_path) as f:
            existing_gt = json.load(f)
    existing_yt_ids = {e["youtube_id"] for e in existing_gt}

    print("Loading GolfDB annotations...")
    candidates = load_candidates()
    print(f"Found {len(candidates)} normal-speed candidates")
    print(f"Already have {len(existing_gt)} videos downloaded")

    selected = select_diverse(candidates, TARGET_COUNT)
    # Filter to only new videos
    new_selected = [v for v in selected if v["youtube_id"] not in existing_yt_ids]
    print(f"Selected {len(selected)} diverse videos, {len(new_selected)} new to download\n")

    new_ground_truth = []
    failed = 0

    for i, video_info in enumerate(new_selected):
        print(f"\n[{i+1}/{len(new_selected)}] GolfDB #{video_info['golfdb_index']}: "
              f"{video_info['player']} ({video_info['club']}, {video_info['view']})")
        gt = download_and_trim(video_info, OUTPUT_DIR)
        if gt:
            new_ground_truth.append(gt)
        else:
            failed += 1

    # Merge: existing + new
    all_ground_truth = existing_gt + new_ground_truth

    with open(gt_path, "w") as f:
        json.dump(all_ground_truth, f, indent=2)
    print(f"\nGround truth saved to {gt_path}")

    print(f"\n{'=' * 60}")
    print(f"Results: {len(existing_gt)} existing + {len(new_ground_truth)} new downloaded, {failed} failed")
    print(f"Total: {len(all_ground_truth)} videos")
    print(f"\nNew videos in {OUTPUT_DIR}:")
    for gt in new_ground_truth:
        path = os.path.join(OUTPUT_DIR, gt["filename"])
        size_mb = os.path.getsize(path) / 1024 / 1024 if os.path.exists(path) else 0
        print(f"  {gt['filename']} ({size_mb:.1f} MB) — "
              f"{gt['player']}, {gt['club']}, impact at {gt['impact_time_sec']:.3f}s")


if __name__ == "__main__":
    main()
