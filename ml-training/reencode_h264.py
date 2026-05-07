#!/usr/bin/env python3
"""Re-encode all clips from mp4v (MPEG-4 Part 2) to H.264 for CreateML compatibility.

Usage:
  python reencode_h264.py                         # defaults to training_data_5class
  python reencode_h264.py --dir training_data_v3   # specify custom directory
"""

import argparse
import subprocess
import sys
from multiprocessing import Pool, cpu_count
from pathlib import Path


def reencode(clip_path: str) -> tuple[str, bool]:
    clip = Path(clip_path)
    tmp = clip.with_suffix(".tmp.mp4")

    try:
        result = subprocess.run(
            ["ffmpeg", "-y", "-i", str(clip),
             "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18",
             "-pix_fmt", "yuv420p", "-an",
             str(tmp)],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0 and tmp.exists() and tmp.stat().st_size > 0:
            tmp.replace(clip)
            return (clip_path, True)
        else:
            tmp.unlink(missing_ok=True)
            return (clip_path, False)
    except Exception as e:
        tmp.unlink(missing_ok=True)
        return (clip_path, False)


def main():
    parser = argparse.ArgumentParser(description="Re-encode clips to H.264 for CreateML")
    parser.add_argument("--dir", type=str, default="training_data_5class",
                        help="Dataset directory to re-encode (default: training_data_5class)")
    args = parser.parse_args()

    base = Path(args.dir)
    if not base.exists():
        print(f"Error: directory '{base}' not found")
        sys.exit(1)

    clips = []
    for cls_dir in sorted(base.iterdir()):
        if not cls_dir.is_dir():
            continue
        for clip in cls_dir.glob("*.mp4"):
            clips.append(str(clip))

    print(f"Re-encoding {len(clips)} clips in '{base}' to H.264 (ultrafast preset)")
    print(f"Using {cpu_count()} workers\n")

    done, failed = 0, 0
    workers = min(cpu_count(), 8)

    with Pool(workers) as pool:
        for path, ok in pool.imap_unordered(reencode, clips, chunksize=10):
            if ok:
                done += 1
            else:
                failed += 1
                print(f"  FAIL: {path}")

            if done % 500 == 0 and done > 0:
                print(f"  Progress: {done}/{len(clips)} done")

    print(f"\nComplete: {done} re-encoded, {failed} failed out of {len(clips)}")


if __name__ == "__main__":
    main()
