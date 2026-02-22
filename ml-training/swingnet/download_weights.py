"""
Download pre-trained SwingNet weights from the GolfDB Google Drive.

Downloads swingnet_1800.pth.tar (the pre-trained checkpoint trained on
GolfDB split 1 for 1800 iterations without augmentation, achieving 71.5% PCE).

Licensed under CC-BY-NC 4.0 (non-commercial use only).

Usage:
    python download_weights.py
    python download_weights.py --output models/swingnet_1800.pth.tar
"""

import argparse
import os
import sys
import urllib.request
from pathlib import Path


# Google Drive file ID for swingnet_1800.pth.tar
# Source: https://drive.google.com/file/d/1MBIDwHSM8OKRbxS8YfyRLnUBAdt0nupW/view
GDRIVE_FILE_ID = "1MBIDwHSM8OKRbxS8YfyRLnUBAdt0nupW"
DEFAULT_OUTPUT = "models/swingnet_1800.pth.tar"
EXPECTED_SIZE_MB = 21  # approximate expected file size


def download_from_gdrive(file_id, output_path):
    """Download a file from Google Drive using the confirm-download URL pattern.

    Google Drive requires a confirmation step for large files. This function
    handles both cases: direct download and confirmation-required download.

    Args:
        file_id: Google Drive file ID
        output_path: local path to save the downloaded file
    """
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if output_path.exists():
        size_mb = output_path.stat().st_size / (1024 * 1024)
        print(f"File already exists: {output_path} ({size_mb:.1f} MB)")
        return

    url = f"https://drive.usercontent.google.com/download?id={file_id}&confirm=t"
    print(f"Downloading pre-trained SwingNet weights...")
    print(f"  Source: Google Drive ({file_id})")
    print(f"  Target: {output_path}")

    _download_with_progress(url, output_path)
    _verify_download(output_path)


def _download_with_progress(url, output_path):
    """Download a URL with progress reporting."""
    response = urllib.request.urlopen(url)
    total_size = response.headers.get("Content-Length")
    total_size = int(total_size) if total_size else None

    downloaded = 0
    chunk_size = 8192

    with open(output_path, "wb") as f:
        while True:
            chunk = response.read(chunk_size)
            if not chunk:
                break
            f.write(chunk)
            downloaded += len(chunk)
            _print_progress(downloaded, total_size)

    print()  # newline after progress


def _print_progress(downloaded, total_size):
    """Print download progress."""
    mb = downloaded / (1024 * 1024)
    if total_size:
        pct = downloaded / total_size * 100
        total_mb = total_size / (1024 * 1024)
        print(f"\r  {mb:.1f} / {total_mb:.1f} MB ({pct:.0f}%)", end="", flush=True)
    else:
        print(f"\r  {mb:.1f} MB downloaded", end="", flush=True)


def _verify_download(output_path):
    """Verify the downloaded file is a valid PyTorch checkpoint."""
    size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"  Downloaded: {size_mb:.1f} MB")

    if size_mb < 1:
        print("WARNING: File is suspiciously small. Download may have failed.")
        print("  Try downloading manually from:")
        print(f"  https://drive.google.com/file/d/{GDRIVE_FILE_ID}/view")
        sys.exit(1)

    # Quick validation: try loading as PyTorch checkpoint
    try:
        import torch
        checkpoint = torch.load(output_path, map_location="cpu", weights_only=True)
        keys = list(checkpoint.get("model_state_dict", {}).keys())
        print(f"  Checkpoint valid: {len(keys)} weight tensors")
    except Exception as e:
        print(f"WARNING: Could not validate checkpoint: {e}")
        print("  The file may be an HTML error page from Google Drive.")
        print("  Try downloading manually and placing at: {output_path}")


def parse_args():
    parser = argparse.ArgumentParser(description="Download pre-trained SwingNet weights")
    parser.add_argument("--output", type=str, default=DEFAULT_OUTPUT,
                        help=f"Output path (default: {DEFAULT_OUTPUT})")
    return parser.parse_args()


def main():
    args = parse_args()
    download_from_gdrive(GDRIVE_FILE_ID, args.output)
    print("\nDone. Use with:")
    print(f"  python export_coreml.py --checkpoint {args.output}")


if __name__ == "__main__":
    main()
