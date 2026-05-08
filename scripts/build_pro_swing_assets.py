#!/usr/bin/env python3
"""Build bundled pro swing clips from local GolfDB/YouTube labels."""

from __future__ import annotations

import json
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "golf-sync-swing" / "Resources" / "ProSwings"
BACKUP_DIR = ROOT / "backups" / "pro-swings-original-16x9"
GOLFDB_METADATA = ROOT / "ml-training" / "golfdb_repo" / "data" / "golfDB.pkl"
PADDING_SECONDS = 2.0
CROP_WIDTH = 1620
CROP_HEIGHT = 1080

GROUND_TRUTH_FILES = [
    ROOT / "golf-sync-swingTests" / "youtube-tests" / "youtube_ground_truth.json",
    ROOT / "golf-sync-swingTests" / "TestData" / "ground_truth.json",
]

SOURCE_DIRS = [
    ROOT / "ml-training" / "youtube_videos",
    ROOT / "golf-sync-swingTests" / "youtube-tests",
    ROOT / "golf-sync-swingTests" / "TestData",
]


@dataclass(frozen=True)
class ProAsset:
    display_name: str
    bundle_filename: str
    youtube_id: str


SELECTED_ASSETS = [
    ProAsset("Tiger Woods", "tiger-woods-driver", "CuAL_6U7_aQ"),
    ProAsset("Tiger Woods", "tiger-woods-wedge", "blonNcv1yas"),
    ProAsset("Rory McIlroy", "rory-mcilroy-driver", "wIiLM8ufWVI"),
    ProAsset("Rickie Fowler", "rickie-fowler-driver", "3WfIqboFIHM"),
    ProAsset("Bryson DeChambeau", "bryson-dechambeau-driver", "7DR3pFxkPVg"),
    ProAsset("Tony Finau", "tony-finau-iron", "9a4LQfePtI4"),
    ProAsset("Bubba Watson", "bubba-watson-iron", "1dSKw-krBIU"),
    ProAsset("Adam Scott", "adam-scott-driver", "jbB8LaUIq1c"),
    ProAsset("Brooke Henderson", "brooke-henderson-iron", "2GqeYdNBCWQ"),
    ProAsset("Charley Hull", "charley-hull-driver", "Kbow-hEJoe0"),
    ProAsset("Dustin Johnson", "dustin-johnson-fairway", "uk4kC3tA8oE"),
    ProAsset("Hyo Joo Kim", "hyo-joo-kim-driver", "iW323nsTGtU"),
    ProAsset("Inbee Park", "inbee-park-driver", "UZ9f9sukG3A"),
    ProAsset("Justin Rose", "justin-rose-driver", "4H2k5sHRqUU"),
    ProAsset("Lexi Thompson", "lexi-thompson-driver", "yfCt0Hkwues"),
    ProAsset("Lydia Ko", "lydia-ko-driver", "UVnNv2eW4gQ"),
    ProAsset("Michelle Wie", "michelle-wie-driver", "htF1nwyL3Dc"),
    ProAsset("Minjee Lee", "minjee-lee-driver", "-x6fBaulaWU"),
    ProAsset("Phil Mickelson", "phil-mickelson-wedge", "wrvEURqD-GI"),
]


def main() -> None:
    labels = load_labels()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    descriptors = []
    for asset in SELECTED_ASSETS:
        label = labels[asset.youtube_id]
        source = source_url(asset.youtube_id)
        plan = clip_plan(label, source)
        output = OUTPUT_DIR / f"{asset.bundle_filename}.mp4"

        backup_existing_asset(output)
        build_clip(source, output, plan["source_start"], plan["source_end"], label.get("bbox"))
        duration = probe_duration(output)
        context_padding = min(plan["core_start"], max(0, duration - plan["core_end"]))

        descriptors.append({
            "display_name": asset.display_name,
            "bundle_filename": asset.bundle_filename,
            "club": club_name(label["club"]),
            "duration": duration,
            "core_start": plan["core_start"],
            "contact": plan["contact"],
            "core_end": plan["core_end"],
            "context_padding": context_padding,
        })

    print_swift_entries(descriptors)


def load_labels() -> dict[str, dict]:
    labels: dict[str, dict] = {}
    bboxes = load_golfdb_bboxes()
    for path in GROUND_TRUTH_FILES:
        for entry in json.loads(path.read_text()):
            golfdb_index = entry.get("golfdb_index")
            if golfdb_index in bboxes:
                entry = {**entry, "bbox": bboxes[golfdb_index]}
            labels[entry["youtube_id"]] = entry
    return labels


def load_golfdb_bboxes() -> dict[int, list[float]]:
    if not GOLFDB_METADATA.exists():
        return {}

    try:
        import pandas as pd
    except ImportError as exc:
        raise RuntimeError("pandas is required to read GolfDB bbox metadata") from exc

    dataframe = pd.read_pickle(GOLFDB_METADATA)
    return {
        int(row["id"]): [float(value) for value in row["bbox"]]
        for _, row in dataframe.iterrows()
    }


def source_url(youtube_id: str) -> Path:
    candidates = [
        *(directory / f"{youtube_id}.mp4" for directory in SOURCE_DIRS),
        *(directory / f"golfdb_{youtube_id}.mp4" for directory in SOURCE_DIRS),
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise FileNotFoundError(f"No local source MP4 found for {youtube_id}")


def clip_plan(label: dict, source: Path) -> dict[str, float]:
    events = label["events"]
    trim_start = float(label["trim_start_sec"])
    address = trim_start + float(events["address"]["time_in_clip_sec"])
    impact = trim_start + float(label["impact_time_sec"])
    finish = trim_start + float(events["finish"]["time_in_clip_sec"])

    source_duration = probe_duration(source)
    source_start = max(0, address - PADDING_SECONDS)
    source_end = min(source_duration, finish + PADDING_SECONDS)

    return {
        "source_start": source_start,
        "source_end": source_end,
        "core_start": address - source_start,
        "contact": impact - source_start,
        "core_end": finish - source_start,
    }


def build_clip(source: Path, output: Path, start: float, end: float, bbox: list[float] | None) -> None:
    video_filter = video_filter_for_bbox(bbox, scaled_width=scaled_width_after_height_scale(source))
    command = [
        "ffmpeg",
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-ss",
        f"{start:.6f}",
        "-to",
        f"{end:.6f}",
        "-i",
        str(source),
        "-map",
        "0:v:0",
        "-an",
        "-vf",
        video_filter,
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "23",
        "-movflags",
        "+faststart",
        str(output),
    ]
    subprocess.run(command, check=True)


def video_filter_for_bbox(
    bbox: list[float] | None,
    *,
    scaled_width: int = 1920,
    crop_width: int = CROP_WIDTH,
    crop_height: int = CROP_HEIGHT,
) -> str:
    crop_x = crop_x_for_bbox(bbox, scaled_width=scaled_width, crop_width=crop_width)
    return (
        f"scale=-2:{crop_height}:flags=lanczos,"
        f"crop={crop_width}:{crop_height}:{crop_x}:0,"
        "format=yuv420p"
    )


def crop_x_for_bbox(
    bbox: list[float] | None,
    *,
    scaled_width: int = 1920,
    crop_width: int = CROP_WIDTH,
) -> int:
    max_crop_x = max(0, scaled_width - crop_width)
    if bbox is None:
        return round(max_crop_x / 2)

    x, _, width, _ = bbox
    bbox_center_x = (float(x) + (float(width) / 2)) * scaled_width
    crop_x = round(bbox_center_x - (crop_width / 2))
    return min(max(crop_x, 0), max_crop_x)


def scaled_width_after_height_scale(source: Path, crop_height: int = CROP_HEIGHT) -> int:
    width, height = probe_video_size(source)
    scaled_width = round((width / height) * crop_height)
    return scaled_width if scaled_width % 2 == 0 else scaled_width + 1


def backup_existing_asset(output: Path) -> None:
    if not output.exists():
        return
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    backup = BACKUP_DIR / output.name
    if backup.exists():
        return
    shutil.copy2(output, backup)


def probe_duration(path: Path) -> float:
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return float(result.stdout.strip())


def probe_video_size(path: Path) -> tuple[int, int]:
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-of",
            "csv=p=0:s=x",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    width, height = result.stdout.strip().split("x")
    return int(width), int(height)


def club_name(club: str) -> str:
    return club.replace("_", " ").title()


def print_swift_entries(descriptors: list[dict]) -> None:
    print("\nSwift ProSwingCatalog entries:\n")
    for descriptor in descriptors:
        print(
            "        ProSwingDescriptor("
            f"displayName: \"{descriptor['display_name']}\", "
            f"bundleFilename: \"{descriptor['bundle_filename']}\", "
            f"club: \"{descriptor['club']}\", "
            f"duration: {descriptor['duration']:.2f}, "
            f"coreStartTime: {descriptor['core_start']:.2f}, "
            f"contactTime: {descriptor['contact']:.2f}, "
            f"coreEndTime: {descriptor['core_end']:.2f}, "
            f"contextPadding: {descriptor['context_padding']:.2f}),"
        )


if __name__ == "__main__":
    main()
