#!/usr/bin/env python3
"""
Download and trim GolfDB test videos for swing detection validation.

Uses GolfDB ground truth annotations to produce short clips (~5s each)
containing exactly one swing with known impact frame timing.

Output: golf-sync-swingTests/TestData/*.mp4 + ground_truth.json
"""

import json
import os
import subprocess
import sys
import tempfile

# Project root (one level up from ml-training/)
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "golf-sync-swingTests", "TestData")

# 5 diverse GolfDB test videos (non-slow-motion, test split)
# Events order: address, toe-up, mid-backswing, top, mid-downswing, impact, mid-follow-through, finish
TEST_VIDEOS = [
    {
        "youtube_id": "f1BWA5F87Jc",
        "golfdb_index": 0,
        "player": "Sandra Gal",
        "club": "driver",
        "view": "down-the-line",
        "events_frames": [408, 455, 473, 476, 490, 495, 498, 501],
        "fps": 30,
    },
    {
        "youtube_id": "iW323nsTGtU",
        "golfdb_index": 19,
        "player": "Hyo Joo Kim",
        "club": "driver",
        "view": "face-on",
        "events_frames": [271, 310, 328, 333, 344, 348, 352, 355],
        "fps": 30,
    },
    {
        "youtube_id": "4HzLO88ryCU",
        "golfdb_index": 47,
        "player": "Tiger Woods",
        "club": "iron",
        "view": "down-the-line",
        "events_frames": [426, 458, 470, 473, 481, 485, 488, 490],
        "fps": 30,
    },
    {
        "youtube_id": "KR9Umr1GM-U",
        "golfdb_index": 59,
        "player": "Rory McIlroy",
        "club": "iron",
        "view": "other",
        "events_frames": [366, 388, 399, 403, 410, 414, 417, 419],
        "fps": 30,
    },
    {
        "youtube_id": "tpv8QUM0G0E",
        "golfdb_index": 31,
        "player": "Paula Creamer",
        "club": "driver",
        "view": "other",
        "events_frames": [151, 172, 188, 193, 201, 204, 207, 210],
        "fps": 30,
    },
]

EVENT_NAMES = [
    "address", "toe_up", "mid_backswing", "top",
    "mid_downswing", "impact", "mid_follow_through", "finish",
]


def download_and_trim(video_info: dict, output_dir: str) -> dict:
    """Download YouTube video, trim to swing window, return ground truth."""
    yt_id = video_info["youtube_id"]
    fps = video_info["fps"]
    events = video_info["events_frames"]

    address_frame = events[0]
    finish_frame = events[7]
    impact_frame = events[5]

    # Trim window: 1s before address to 1s after finish
    trim_start_sec = max(0, address_frame / fps - 1.0)
    trim_end_sec = finish_frame / fps + 1.0
    duration = trim_end_sec - trim_start_sec

    # Impact time relative to trimmed clip
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
            # Download best mp4 ≤720p
            subprocess.run(
                [
                    "yt-dlp",
                    "-f", "bestvideo[ext=mp4][height<=720]+bestaudio[ext=m4a]/best[ext=mp4][height<=720]",
                    "--merge-output-format", "mp4",
                    "-o", tmp_template,
                    "--no-playlist",
                    "--quiet",
                    url,
                ],
                check=True,
            )

            # Find the downloaded file
            tmp_files = [f for f in os.listdir(tmp_dir) if f.endswith(".mp4")]
            if not tmp_files:
                raise RuntimeError(f"No mp4 file found in {tmp_dir}")
            tmp_path = os.path.join(tmp_dir, tmp_files[0])

            # Trim with ffmpeg (re-encode for accurate seeking)
            print(f"  Trimming {trim_start_sec:.2f}s-{trim_end_sec:.2f}s...")
            subprocess.run(
                [
                    "ffmpeg",
                    "-y",
                    "-ss", str(trim_start_sec),
                    "-i", tmp_path,
                    "-t", str(duration),
                    "-c:v", "libx264",
                    "-preset", "fast",
                    "-crf", "23",
                    "-an",  # no audio needed for pose detection
                    "-r", str(fps),
                    output_path,
                ],
                check=True,
                capture_output=True,
            )
            print(f"  Saved: {filename}")
        finally:
            import shutil
            shutil.rmtree(tmp_dir, ignore_errors=True)

    # Build ground truth with times relative to the trimmed clip
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
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    all_ground_truth = []
    for video_info in TEST_VIDEOS:
        print(f"\nProcessing GolfDB #{video_info['golfdb_index']}: {video_info['player']}...")
        gt = download_and_trim(video_info, OUTPUT_DIR)
        all_ground_truth.append(gt)

    # Save ground truth JSON
    gt_path = os.path.join(OUTPUT_DIR, "ground_truth.json")
    with open(gt_path, "w") as f:
        json.dump(all_ground_truth, f, indent=2)
    print(f"\nGround truth saved to {gt_path}")

    # Summary
    print("\n" + "=" * 60)
    print("Test videos ready:")
    for gt in all_ground_truth:
        path = os.path.join(OUTPUT_DIR, gt["filename"])
        size_mb = os.path.getsize(path) / 1024 / 1024 if os.path.exists(path) else 0
        print(f"  {gt['filename']} ({size_mb:.1f} MB) — impact at {gt['impact_time_sec']:.3f}s")


if __name__ == "__main__":
    main()
