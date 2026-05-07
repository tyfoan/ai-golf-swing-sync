#!/usr/bin/env python3
"""
Extract optimized 5-class golf swing dataset for CreateML Action Classifier.

Designed based on expert team research findings:
- GolfDB PCE data: impact=98.4%, address=31.7%, finish=26.5%
- Phase purity analysis: short phases (<6 frames) contaminate 30-frame clips
- Create ML Action Classifier is pose-based (Vision body pose, NOT pixels)
- Shorter prediction windows (15 frames / 0.5s) double purity for short phases

Classes:
  1. backswing       (TAKEAWAY -> TOP)   Actual swing movement (address excluded)
  2. downswing       (TOP -> IMPACT)     Full downswing (merged early/late)
  3. impact          (IMPACT ±4 frames)  Ball contact zone — 98.4% PCE
  4. follow_through  (IMPACT -> FINISH)  Full follow-through (merged early/late)
  5. no_swing        (PRE/POST regions)  Non-swing (absorbs address + finish)

Key optimizations:
  - Backswing starts at TAKEAWAY (event 2), not ADDRESS — removes standing-still clips
  - Max 2 sliding windows per phase — reduces class imbalance (3.4x -> ~2x)
  - 15-frame clips (0.5s) — doubles phase purity vs 30-frame clips
  - H.264 output (avc1 fourcc) — no re-encode step needed
  - No manual horizontal flip — let CreateML handle augmentation
  - Excludes slow-motion by default — wrong temporal dynamics
  - Impact ±4 frames (not ±8) — tighter = purer class boundary

Usage:
  # From YouTube (recommended — 758 normal-speed annotations):
  python extract_5class_dataset.py --extract --from-youtube --stats

  # From existing training_data_v3 clips (no download needed):
  python extract_5class_dataset.py --extract --from-existing --stats

  # Download YouTube videos first (if not already cached):
  python extract_5class_dataset.py --download

Requirements:
  pip install pandas opencv-python numpy
  brew install yt-dlp  (for YouTube download only)
"""

import argparse
import json
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
import pandas as pd


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

GOLFDB_PKL = "golfdb_repo/data/golfDB.pkl"
YOUTUBE_DIR = "youtube_videos"
EXISTING_DIR = "training_data_v3"
OUTPUT_DIR = "training_data_5class"
STATS_FILE = "extraction_stats_5class.json"

TARGET_FPS = 30
TARGET_CLIP_FRAMES = 15   # 0.5s — doubles phase purity vs 30-frame clips
MIN_CLIP_FRAMES = 8       # Minimum viable clip (0.27s)
IMPACT_BUFFER = 4         # ±4 frames for impact class (267ms window)
MAX_WINDOWS_PER_PHASE = 2 # Cap sliding windows to reduce class imbalance (3.4x → ~2x)

# GolfDB event indices (10 events per swing)
# 0:PRE  1:ADDR  2:TOE-UP  3:MID-BACK  4:TOP  5:MID-DOWN  6:IMPACT  7:MID-FOLLOW  8:FINISH  9:POST
EVT_PRE = 0
EVT_ADDR = 1
EVT_TAKEAWAY = 2  # toe-up — first actual club movement (backswing start)
EVT_TOP = 4
EVT_IMPACT = 6
EVT_FINISH = 8
EVT_POST = 9

# Range-based classes: (class_name, start_event, end_event)
# NOTE: backswing starts at TAKEAWAY (event 2), NOT ADDRESS (event 1).
# Address is standing still — including it contaminates backswing clips.
RANGE_CLASSES = [
    ("backswing",      EVT_TAKEAWAY, EVT_TOP),
    ("downswing",      EVT_TOP,      EVT_IMPACT),
    ("follow_through", EVT_IMPACT,   EVT_FINISH),
]

# Point-based class: impact centered on EVT_IMPACT
IMPACT_CLASS = ("impact", EVT_IMPACT)

# H.264 fourcc — outputs CreateML-compatible video directly
H264_FOURCC = cv2.VideoWriter_fourcc(*"avc1")


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class Annotation:
    id: int
    youtube_id: str
    events: np.ndarray
    bbox: np.ndarray
    slow: int
    view: str
    club: str

    @property
    def is_slow_motion(self) -> bool:
        return self.slow == 1

    def event_frame(self, evt: int) -> int:
        return int(self.events[evt])


# ---------------------------------------------------------------------------
# Clip writer (H.264 output)
# ---------------------------------------------------------------------------

class ClipWriter:
    """Writes H.264-encoded video clips from a source VideoCapture."""

    def __init__(self, target_fps: int = TARGET_FPS):
        self.target_fps = target_fps

    def write(self, cap: cv2.VideoCapture, start_frame: int, end_frame: int,
              output_path: Path) -> bool:
        if output_path.exists():
            return True

        cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
        ret, first = cap.read()
        if not ret:
            return False

        h, w = first.shape[:2]
        writer = cv2.VideoWriter(str(output_path), H264_FOURCC, self.target_fps, (w, h))
        writer.write(first)

        written = 1
        target = end_frame - start_frame
        while written < target:
            ret, frame = cap.read()
            if not ret:
                break
            writer.write(frame)
            written += 1

        writer.release()

        if written < MIN_CLIP_FRAMES:
            output_path.unlink(missing_ok=True)
            return False
        return True


# ---------------------------------------------------------------------------
# Window computation
# ---------------------------------------------------------------------------

def compute_centered_window(phase_start: int, phase_end: int,
                            total_frames: int, target: int) -> Optional[tuple[int, int]]:
    """Compute a single centered window for a range-based phase.

    Unlike the 6/8-class scripts, we use ONE centered window only.
    Shifted-window augmentation adds noise for short phases (70% overlap
    between variants when phase is <10 frames).
    """
    dur = phase_end - phase_start
    if dur <= 0:
        return None

    center = (phase_start + phase_end) // 2
    ws = max(0, center - target // 2)
    we = min(total_frames, ws + target)
    ws = max(0, we - target)

    if we - ws < MIN_CLIP_FRAMES:
        return None

    return (ws, we)


def compute_sliding_windows(phase_start: int, phase_end: int,
                            total_frames: int, target: int) -> list[tuple[int, int]]:
    """Compute sliding windows for phases longer than the target clip."""
    windows = []
    stride = target // 2

    ws = phase_start
    while ws + target <= phase_end:
        windows.append((ws, ws + target))
        ws += stride

    if not windows or windows[-1][1] < phase_end:
        fs = max(phase_start, phase_end - target)
        windows.append((fs, min(total_frames, fs + target)))

    return windows


def compute_phase_windows(phase_start: int, phase_end: int,
                          total_frames: int, target: int,
                          max_windows: Optional[int] = None) -> list[tuple[int, int]]:
    """Compute extraction windows for a range-based phase.

    Short phases (≤ target): single centered window.
    Long phases (> target): overlapping sliding windows, capped at max_windows.
    """
    dur = phase_end - phase_start
    if dur <= 0:
        return []

    if dur <= target:
        window = compute_centered_window(phase_start, phase_end, total_frames, target)
        return [window] if window else []

    windows = compute_sliding_windows(phase_start, phase_end, total_frames, target)

    if max_windows and len(windows) > max_windows:
        indices = np.linspace(0, len(windows) - 1, max_windows, dtype=int)
        windows = [windows[i] for i in indices]

    return windows


def compute_impact_window(impact_frame: int, total_frames: int,
                          target: int,
                          buffer: int = IMPACT_BUFFER) -> Optional[tuple[int, int]]:
    """Compute a centered window for the impact point class.

    The impact event must have at least `buffer` frames of context on each
    side within the video. The window is centered on the impact frame.
    """
    if impact_frame - buffer < 0 or impact_frame + buffer >= total_frames:
        return None

    ws = impact_frame - target // 2
    we = ws + target

    # Clamp to video boundaries
    if ws < 0:
        ws = 0
        we = target
    if we > total_frames:
        we = total_frames
        ws = we - target

    if ws < 0 or we - ws < MIN_CLIP_FRAMES:
        return None

    return (ws, we)


# ---------------------------------------------------------------------------
# YouTube extraction
# ---------------------------------------------------------------------------

class YouTubeExtractor:
    """Extracts 5-class clips from downloaded YouTube source videos."""

    def __init__(self, youtube_dir: str, output_dir: str, target_frames: int,
                 max_windows: Optional[int] = None):
        self.youtube_dir = Path(youtube_dir)
        self.output_dir = Path(output_dir)
        self.target_frames = target_frames
        self.max_windows = max_windows
        self.writer = ClipWriter()
        self._yt_cache: dict[str, Optional[Path]] = {}

    def _resolve_video(self, yt_id: str) -> Optional[Path]:
        if yt_id in self._yt_cache:
            return self._yt_cache[yt_id]
        for ext in ("mp4", "mkv", "webm"):
            p = self.youtube_dir / f"{yt_id}.{ext}"
            if p.exists():
                self._yt_cache[yt_id] = p
                return p
        self._yt_cache[yt_id] = None
        return None

    def extract_all(self, annotations: list[Annotation]) -> tuple[int, int, int]:
        success, skip, fail = 0, 0, 0

        for i, anno in enumerate(annotations):
            video = self._resolve_video(anno.youtube_id)
            if video is None:
                skip += 1
                continue

            if i % 50 == 0:
                print(f"  [{i+1}/{len(annotations)}] ID={anno.id:04d} ({anno.view})")

            if self._extract_one(anno, video):
                success += 1
            else:
                fail += 1

        return success, skip, fail

    def _extract_one(self, anno: Annotation, video_path: Path) -> bool:
        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            return False

        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

        self._extract_range_phases(cap, anno, total)
        self._extract_impact(cap, anno, total)
        self._extract_no_swing(cap, anno, total)

        cap.release()
        return True

    def _extract_range_phases(self, cap, anno, total):
        for cls, s_evt, e_evt in RANGE_CLASSES:
            cls_dir = self.output_dir / cls
            cls_dir.mkdir(parents=True, exist_ok=True)

            ps = anno.event_frame(s_evt)
            pe = anno.event_frame(e_evt)
            windows = compute_phase_windows(ps, pe, total, self.target_frames,
                                            max_windows=self.max_windows)

            for wi, (ws, we) in enumerate(windows):
                sfx = f"_w{wi}" if len(windows) > 1 else ""
                out = cls_dir / f"golfdb_{anno.id:04d}_{cls}{sfx}.mp4"
                self.writer.write(cap, ws, we, out)

    def _extract_impact(self, cap, anno, total):
        cls_dir = self.output_dir / "impact"
        cls_dir.mkdir(parents=True, exist_ok=True)

        ef = anno.event_frame(EVT_IMPACT)
        window = compute_impact_window(ef, total, self.target_frames)

        if window is None:
            return

        ws, we = window
        out = cls_dir / f"golfdb_{anno.id:04d}_impact.mp4"
        self.writer.write(cap, ws, we, out)

    def _extract_no_swing(self, cap, anno, total):
        ns_dir = self.output_dir / "no_swing"
        ns_dir.mkdir(parents=True, exist_ok=True)

        # no_swing absorbs address (standing still) — pre-swing includes address
        regions = [
            ("pre",  anno.event_frame(EVT_PRE), anno.event_frame(EVT_TAKEAWAY)),
            ("post", anno.event_frame(EVT_FINISH), anno.event_frame(EVT_POST)),
        ]
        for variant, rs, re in regions:
            rs, re = max(0, rs), min(total, re)
            if re - rs < MIN_CLIP_FRAMES:
                continue
            center = (rs + re) // 2
            ws = max(0, center - self.target_frames // 2)
            we = min(total, ws + self.target_frames)
            ws = max(0, we - self.target_frames)
            out = ns_dir / f"golfdb_{anno.id:04d}_no_swing_{variant}.mp4"
            self.writer.write(cap, ws, we, out)


# ---------------------------------------------------------------------------
# Existing-clip extraction
# ---------------------------------------------------------------------------

class ExistingClipExtractor:
    """Re-extracts 5-class clips from existing training_data_v3 clips.

    Existing clips are ~45 frames (1.5s) centered on each phase midpoint.
    We re-cut them into 15-frame windows using GolfDB event annotations.
    """

    EXISTING_PHASES = {
        "backswing":      (EVT_TAKEAWAY, EVT_TOP),
        "downswing":      (EVT_TOP, EVT_IMPACT),
        "follow_through": (EVT_IMPACT, EVT_FINISH),
    }

    def __init__(self, existing_dir: str, output_dir: str, target_frames: int):
        self.existing_dir = Path(existing_dir)
        self.output_dir = Path(output_dir)
        self.target_frames = target_frames
        self.writer = ClipWriter()

    def extract_all(self, annotations: list[Annotation]) -> tuple[int, int]:
        success, skip = 0, 0

        for i, anno in enumerate(annotations):
            if anno.is_slow_motion:
                skip += 1
                continue

            if i % 100 == 0:
                print(f"  [{i+1}/{len(annotations)}] ID={anno.id:04d}")

            if self._extract_one(anno):
                success += 1
            else:
                skip += 1

        return success, skip

    def _extract_one(self, anno: Annotation) -> bool:
        extracted_any = False

        for old_phase, (old_start_evt, old_end_evt) in self.EXISTING_PHASES.items():
            clip_path = self.existing_dir / old_phase / f"golfdb_{anno.id:04d}_{old_phase}.mp4"
            if not clip_path.exists():
                continue

            cap = cv2.VideoCapture(str(clip_path))
            if not cap.isOpened():
                continue

            clip_total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            clip_offset = self._compute_clip_offset(anno, old_start_evt, old_end_evt, clip_total)

            if self._extract_ranges_from_clip(cap, anno, clip_total, clip_offset, old_phase):
                extracted_any = True

            if self._extract_impact_from_clip(cap, anno, clip_total, clip_offset, old_phase):
                extracted_any = True

            cap.release()

        if self._copy_no_swing(anno):
            extracted_any = True

        return extracted_any

    def _compute_clip_offset(self, anno, old_start_evt, old_end_evt, clip_total):
        """Compute which source frame corresponds to clip frame 0."""
        old_phase_start = anno.event_frame(old_start_evt)
        old_phase_end = anno.event_frame(old_end_evt)
        old_phase_mid = (old_phase_start + old_phase_end) / 2
        return old_phase_mid - clip_total / 2

    def _extract_ranges_from_clip(self, cap, anno, clip_total, clip_offset, old_phase):
        extracted = False

        for new_cls, new_s_evt, new_e_evt in RANGE_CLASSES:
            new_start = anno.event_frame(new_s_evt)
            new_end = anno.event_frame(new_e_evt)

            if new_end - new_start <= 0:
                continue

            local_start = new_start - clip_offset
            local_end = new_end - clip_offset

            local_mid = (local_start + local_end) / 2
            if local_mid < 0 or local_mid >= clip_total:
                continue

            windows = compute_phase_windows(
                max(0, int(local_start)),
                min(clip_total, int(local_end)),
                clip_total,
                self.target_frames,
            )

            cls_dir = self.output_dir / new_cls
            cls_dir.mkdir(parents=True, exist_ok=True)

            for wi, (ws, we) in enumerate(windows):
                sfx = f"_from{old_phase[0]}"
                sfx += f"_w{wi}" if len(windows) > 1 else ""
                out = cls_dir / f"golfdb_{anno.id:04d}_{new_cls}{sfx}.mp4"

                if self.writer.write(cap, ws, we, out):
                    extracted = True

        return extracted

    def _extract_impact_from_clip(self, cap, anno, clip_total, clip_offset, old_phase):
        ef = anno.event_frame(EVT_IMPACT)
        local_ef = ef - clip_offset

        if local_ef - IMPACT_BUFFER < 0 or local_ef + IMPACT_BUFFER >= clip_total:
            return False

        window = compute_impact_window(int(local_ef), clip_total, self.target_frames)
        if window is None:
            return False

        ws, we = window
        cls_dir = self.output_dir / "impact"
        cls_dir.mkdir(parents=True, exist_ok=True)

        out = cls_dir / f"golfdb_{anno.id:04d}_impact_from{old_phase[0]}.mp4"
        return self.writer.write(cap, ws, we, out)

    def _copy_no_swing(self, anno):
        extracted = False
        ns_dir = self.output_dir / "no_swing"
        ns_dir.mkdir(parents=True, exist_ok=True)

        for variant in ("pre", "post"):
            src = self.existing_dir / "no_swing" / f"golfdb_{anno.id:04d}_no_swing_{variant}.mp4"
            dst = ns_dir / f"golfdb_{anno.id:04d}_no_swing_{variant}.mp4"
            if src.exists() and not dst.exists():
                cap = cv2.VideoCapture(str(src))
                if cap.isOpened():
                    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
                    frames = min(total, self.target_frames)
                    if self.writer.write(cap, 0, frames, dst):
                        extracted = True
                    cap.release()

        return extracted


# ---------------------------------------------------------------------------
# YouTube downloader
# ---------------------------------------------------------------------------

class YouTubeDownloader:
    """Downloads YouTube videos needed for dataset extraction."""

    def __init__(self, output_dir: str):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def download_all(self, annotations: list[Annotation]) -> dict[str, bool]:
        unique_ids = list({a.youtube_id for a in annotations})
        results = {}
        already = 0

        print(f"Need {len(unique_ids)} unique YouTube videos")

        for i, yt_id in enumerate(unique_ids):
            out = self.output_dir / f"{yt_id}.mp4"
            if out.exists():
                results[yt_id] = True
                already += 1
                continue

            print(f"  [{i+1}/{len(unique_ids)}] Downloading {yt_id}...")
            results[yt_id] = self._download(yt_id, out)

        ok = sum(1 for v in results.values() if v)
        print(f"\nResult: {ok}/{len(unique_ids)} available ({already} cached)")
        return results

    def _download(self, yt_id: str, out: Path) -> bool:
        url = f"https://www.youtube.com/watch?v={yt_id}"
        try:
            subprocess.run(
                ["yt-dlp", "-f",
                 "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
                 "--merge-output-format", "mp4",
                 "-o", str(out), "--no-playlist",
                 "--socket-timeout", "30", "--retries", "3", url],
                capture_output=True, text=True, timeout=120,
            )
            return out.exists()
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            print(f"    Error: {e}")
            return False


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------

class DatasetStatistics:
    """Reports per-class clip counts, sizes, and balance metrics."""

    def __init__(self, dataset_dir: str):
        self.dataset_dir = Path(dataset_dir)

    def report(self) -> dict:
        stats = {}
        total_clips, total_mb = 0, 0.0

        print("\n" + "=" * 65)
        print("5-CLASS DATASET STATISTICS")
        print("=" * 65)

        for cls_dir in sorted(self.dataset_dir.iterdir()):
            if not cls_dir.is_dir():
                continue
            clips = list(cls_dir.glob("*.mp4"))
            mb = sum(c.stat().st_size for c in clips) / (1024 * 1024)

            stats[cls_dir.name] = {
                "total": len(clips),
                "size_mb": round(mb, 1),
            }
            total_clips += len(clips)
            total_mb += mb

            print(f"  {cls_dir.name:25s}: {len(clips):5d} clips [{mb:.1f} MB]")

        print(f"  {'TOTAL':25s}: {total_clips:5d} clips [{total_mb:.1f} MB]")

        if stats:
            counts = [s["total"] for s in stats.values() if s["total"] > 0]
            if counts:
                ratio = max(counts) / min(counts)
                print(f"  Balance ratio:            {ratio:.1f}x (max/min)")

        print("=" * 65)

        stats["_total"] = {"clips": total_clips, "size_mb": round(total_mb, 1)}
        return stats


# ---------------------------------------------------------------------------
# Annotation loader
# ---------------------------------------------------------------------------

def load_annotations(include_slow_mo: bool = False) -> list[Annotation]:
    """Load GolfDB annotations. Excludes slow-motion by default."""
    df = pd.read_pickle(GOLFDB_PKL)
    annotations = []

    for _, row in df.iterrows():
        if not include_slow_mo and row["slow"] == 1:
            continue

        events = row["events"]
        if len(events) != 10:
            continue
        if not all(events[i] <= events[i + 1] for i in range(9)):
            print(f"  WARNING: ID {row['id']} has non-monotonic events, skipping")
            continue

        annotations.append(Annotation(
            id=int(row["id"]), youtube_id=row["youtube_id"],
            events=events, bbox=row["bbox"], slow=int(row["slow"]),
            view=row["view"], club=row["club"],
        ))

    return annotations


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Extract optimized 5-class golf swing dataset for CreateML",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Classes:
  backswing       (TAKEAWAY -> TOP)     Actual swing movement (address excluded)
  downswing       (TOP -> IMPACT)       Full downswing
  impact          (IMPACT ±4 frames)    Ball contact zone (98.4%% PCE)
  follow_through  (IMPACT -> FINISH)    Full follow-through
  no_swing        (PRE/POST regions)    Non-swing (absorbs address + finish)

Optimizations:
  - Backswing starts at takeaway, not address (removes standing-still clips)
  - Max 2 sliding windows per phase (reduces class imbalance)
  - 15-frame clips (0.5s) — doubles phase purity vs 30-frame
  - H.264 output (avc1) — no re-encode step needed
  - No manual flip — let CreateML handle augmentation
  - Excludes slow-motion by default

Examples:
  python extract_5class_dataset.py --extract --from-youtube --stats
  python extract_5class_dataset.py --extract --from-existing --stats
""",
    )
    parser.add_argument("--download", action="store_true",
                        help="Download YouTube source videos")
    parser.add_argument("--extract", action="store_true",
                        help="Extract 5-class clips")
    parser.add_argument("--from-youtube", action="store_true",
                        help="Extract from YouTube videos")
    parser.add_argument("--from-existing", action="store_true",
                        help="Extract from existing training_data_v3 clips")
    parser.add_argument("--stats", action="store_true",
                        help="Report dataset statistics")
    parser.add_argument("--include-slow-mo", action="store_true",
                        help="Include slow-motion videos (excluded by default)")
    parser.add_argument("--clip-frames", type=int, default=TARGET_CLIP_FRAMES,
                        help=f"Frames per clip (default: {TARGET_CLIP_FRAMES})")
    parser.add_argument("--output-dir", type=str, default=OUTPUT_DIR,
                        help=f"Output directory (default: {OUTPUT_DIR})")
    parser.add_argument("--max-windows", type=int, default=MAX_WINDOWS_PER_PHASE,
                        help=f"Max sliding windows per phase (default: {MAX_WINDOWS_PER_PHASE})")
    parser.add_argument("--clean", action="store_true",
                        help="Delete existing output directory before extraction")

    args = parser.parse_args()

    if not any([args.download, args.extract, args.stats]):
        parser.print_help()
        sys.exit(1)

    output_dir = args.output_dir
    clip_frames = args.clip_frames
    max_windows = args.max_windows

    if args.clean and Path(output_dir).exists():
        print(f"Cleaning existing output directory: {output_dir}/")
        shutil.rmtree(output_dir)

    print("=" * 65)
    print("5-CLASS GOLF SWING DATASET EXTRACTION (OPTIMIZED)")
    print("=" * 65)
    print(f"  Classes:      backswing (takeaway→top), downswing, impact (±{IMPACT_BUFFER}f), "
          f"follow_through, no_swing")
    print(f"  Clip frames:  {clip_frames} ({clip_frames / TARGET_FPS:.1f}s)")
    print(f"  Max windows:  {max_windows} per phase")
    print(f"  Codec:        H.264 (avc1)")

    include_slow = args.include_slow_mo
    if args.from_existing:
        include_slow = False
        print("  Mode:         from existing training_data_v3 (normal-speed only)")
    else:
        print("  Mode:         from YouTube videos")

    print(f"  Output:       {output_dir}/")
    print(f"  Slow-motion:  {'included' if include_slow else 'excluded'}")

    annotations = load_annotations(include_slow_mo=include_slow)
    normal = sum(1 for a in annotations if not a.is_slow_motion)
    slow = sum(1 for a in annotations if a.is_slow_motion)
    print(f"  Annotations:  {len(annotations)} ({normal} normal, {slow} slow)")

    if args.download:
        print("\n=== DOWNLOADING YOUTUBE VIDEOS ===\n")
        YouTubeDownloader(YOUTUBE_DIR).download_all(annotations)

    if args.extract:
        print("\n=== EXTRACTING 5-CLASS CLIPS ===\n")

        if args.from_existing:
            extractor = ExistingClipExtractor(EXISTING_DIR, output_dir, clip_frames)
            ok, skip = extractor.extract_all(annotations)
            print(f"\nDone: {ok} extracted, {skip} skipped")
        else:
            extractor = YouTubeExtractor(YOUTUBE_DIR, output_dir, clip_frames,
                                         max_windows=max_windows)
            ok, skip, fail = extractor.extract_all(annotations)
            print(f"\nDone: {ok} extracted, {skip} skipped, {fail} failed")

    if args.stats:
        stats = DatasetStatistics(output_dir).report()
        with open(STATS_FILE, "w") as f:
            json.dump(stats, f, indent=2)

    print("\nDone!")


if __name__ == "__main__":
    main()
