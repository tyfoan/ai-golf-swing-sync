#!/usr/bin/env python3
"""Install golf-sync-swing app icon: resize source, derive dark + tinted, drop in asset catalog.

Usage: python3 scripts/install_app_icon.py /path/to/source.png
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

SOURCE = Path(sys.argv[1])
TARGET_SIZE = 1024
ASSET_DIR = Path(__file__).resolve().parent.parent / "golf-sync-swing/Assets.xcassets/AppIcon.appiconset"

LIGHT_BG = np.array([45, 106, 79])    # #2D6A4F  fairwayGreen
DARK_BG = np.array([27, 67, 50])      # #1B4332  pineGreen
CREAM_LUMINOSITY_THRESHOLD = 540       # R+G+B sum above which a pixel is treated as cream silhouette/brackets

def load_and_resize(path: Path, size: int) -> np.ndarray:
    img = Image.open(path).convert("RGB").resize((size, size), Image.LANCZOS)
    return np.array(img)

def cream_mask(arr: np.ndarray) -> np.ndarray:
    """Pixels representing the cream silhouette + brackets (high luminosity, low saturation)."""
    luminosity = arr.sum(axis=2)
    return luminosity > CREAM_LUMINOSITY_THRESHOLD

def make_light(arr: np.ndarray) -> np.ndarray:
    return arr

def make_dark(arr: np.ndarray) -> np.ndarray:
    """Shift only the non-cream pixels from fairway-teal toward pine-green."""
    delta = (LIGHT_BG - DARK_BG).astype(np.int16)
    out = arr.astype(np.int16)
    bg_pixels = ~cream_mask(arr)
    out[bg_pixels] -= delta
    return np.clip(out, 0, 255).astype(np.uint8)

def make_tinted(arr: np.ndarray) -> np.ndarray:
    """Pure black background, cream pixels → white. iOS applies user tint at runtime."""
    out = np.zeros_like(arr)
    out[cream_mask(arr)] = [255, 255, 255]
    return out

def save(arr: np.ndarray, path: Path):
    Image.fromarray(arr).save(path, optimize=True)
    print(f"wrote {path}")

def main():
    arr = load_and_resize(SOURCE, TARGET_SIZE)
    save(make_light(arr),  ASSET_DIR / "appicon-light.png")
    save(make_dark(arr),   ASSET_DIR / "appicon-dark.png")
    save(make_tinted(arr), ASSET_DIR / "appicon-tinted.png")

if __name__ == "__main__":
    main()
