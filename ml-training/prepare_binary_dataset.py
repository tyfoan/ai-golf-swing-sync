#!/usr/bin/env python3
"""
Prepare binary (swing / not_swing) training data from the 5-class dataset.

Mapping:
  backswing, downswing, impact, follow_through → swing
  no_swing → not_swing

Creates:
  training_data_binary/
    swing/       (balanced to match not_swing count)
    not_swing/

Create ML Action Classifier expects this directory layout.
"""

import os
import shutil
import random
from pathlib import Path

SOURCE = Path("training_data_5class")
DEST = Path("training_data_binary")

SWING_CLASSES = ["backswing", "downswing", "impact", "follow_through"]
NOT_SWING_CLASS = "no_swing"


def collect_clips():
    swing_clips = []
    for cls in SWING_CLASSES:
        cls_dir = SOURCE / cls
        if cls_dir.exists():
            clips = sorted(cls_dir.glob("*.mp4"))
            swing_clips.extend(clips)
            print(f"  {cls}: {len(clips)} clips")

    not_swing_dir = SOURCE / NOT_SWING_CLASS
    not_swing_clips = sorted(not_swing_dir.glob("*.mp4")) if not_swing_dir.exists() else []
    print(f"  {NOT_SWING_CLASS}: {len(not_swing_clips)} clips")

    return swing_clips, not_swing_clips


def balance_and_copy(swing_clips, not_swing_clips):
    # Balance: downsample the larger class
    target_count = min(len(swing_clips), len(not_swing_clips))
    print(f"\nBalancing to {target_count} clips per class")

    random.seed(42)
    if len(swing_clips) > target_count:
        swing_clips = random.sample(swing_clips, target_count)
    if len(not_swing_clips) > target_count:
        not_swing_clips = random.sample(not_swing_clips, target_count)

    # Create destination directories
    swing_dest = DEST / "swing"
    not_swing_dest = DEST / "not_swing"
    swing_dest.mkdir(parents=True, exist_ok=True)
    not_swing_dest.mkdir(parents=True, exist_ok=True)

    # Copy swing clips
    for i, clip in enumerate(swing_clips):
        dest = swing_dest / f"swing_{i:04d}.mp4"
        shutil.copy2(clip, dest)

    # Copy not_swing clips
    for i, clip in enumerate(not_swing_clips):
        dest = not_swing_dest / f"not_swing_{i:04d}.mp4"
        shutil.copy2(clip, dest)

    print(f"  swing/: {len(swing_clips)} clips")
    print(f"  not_swing/: {len(not_swing_clips)} clips")


def main():
    print("Preparing binary training data from 5-class dataset\n")

    if not SOURCE.exists():
        print(f"ERROR: Source directory '{SOURCE}' not found")
        return

    # Clean destination
    if DEST.exists():
        shutil.rmtree(DEST)

    print("Collecting clips:")
    swing_clips, not_swing_clips = collect_clips()
    print(f"\nTotal: {len(swing_clips)} swing, {len(not_swing_clips)} not_swing")

    balance_and_copy(swing_clips, not_swing_clips)

    print(f"\nDone! Training data ready at: {DEST}/")
    print("Next: Open Create ML, drag this folder, train Action Classifier")


if __name__ == "__main__":
    main()
