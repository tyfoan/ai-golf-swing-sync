"""
Generate golf-ball-dimple background patterns for App Store screenshots.

Brand palette sampled from the app icon:
  base    = #529F8F  (teal)
  rim     = #7FC1B4  (highlight, light teal)
  shadow  = #418C7C  (inner shadow)

Produces three outputs:
  dimples-tile-2048.png       — seamless square, drop-in for appscreens "Tile/Repeat"
  dimples-portrait-1320x2868.png — full-bleed phone canvas
  dimples-landscape-2868x1320.png — landscape full-bleed

Procedural — perfectly tileable, crisp at any resolution. Uses 2x supersampling
for anti-aliasing, hex (staggered) grid for organic feel, and directional
shading (light from upper-left) for a 3D bowl look.
"""

import math
from PIL import Image
from pathlib import Path

BASE = (0x52, 0x9F, 0x8F)
RIM = (0x7F, 0xC1, 0xB4)
SHADOW = (0x41, 0x8C, 0x7C)

OUT_DIR = Path(__file__).parent.parent / "screenshots" / "backgrounds"


def lerp(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return (
        int(c1[0] + (c2[0] - c1[0]) * t),
        int(c1[1] + (c2[1] - c1[1]) * t),
        int(c1[2] + (c2[2] - c1[2]) * t),
    )


def render(width, height, dimples_across, supersample=2, seamless=True):
    """Render a hex-grid dimple (concave) pattern.

    `dimples_across` — number of dimples spanning the width (controls scale).
    `seamless` — if True, horizontal edges tile cleanly.

    Concave shading: light from upper-left → upper-left of bowl is in SHADOW
    (near wall blocks light), lower-right rim catches the bounce HIGHLIGHT.
    Center of bowl is darkest (deepest).
    """
    W = width * supersample
    H = height * supersample
    spacing = W / dimples_across
    radius = spacing * 0.48
    row_height = spacing * 0.866  # hex row pitch (sqrt(3)/2)

    # light comes FROM upper-left → light_dir vector points lower-right
    # For concave bowl, the wall whose normal points toward the light gets lit.
    # That wall is on the LOWER-RIGHT side of the dimple (its inner normal points up-and-LEFT, toward the light).
    # So highlight position relative to dimple center is at +x, +y (lower-right).
    hx, hy = 0.55, 0.83
    norm = math.hypot(hx, hy)
    hx, hy = hx / norm, hy / norm

    img = Image.new("RGB", (W, H), BASE)
    px = img.load()

    inv_radius = 1.0 / radius
    inv_spacing = 1.0 / spacing
    inv_row_height = 1.0 / row_height

    for y in range(H):
        row_f = y * inv_row_height
        center_row = round(row_f)
        for x in range(W):
            best_d2 = 1e18
            best_cx = 0.0
            best_cy = 0.0
            for dr in (-1, 0, 1):
                r = center_row + dr
                ox = (spacing * 0.5) if (r % 2) else 0.0
                cyy = r * row_height
                col_f = (x - ox) * inv_spacing
                for dc in (0, 1):
                    col = math.floor(col_f) + dc
                    cxx = col * spacing + ox
                    if seamless:
                        dx_ = x - cxx
                        if dx_ > W * 0.5:
                            dx_ -= W
                        elif dx_ < -W * 0.5:
                            dx_ += W
                    else:
                        dx_ = x - cxx
                    dy_ = y - cyy
                    d2 = dx_ * dx_ + dy_ * dy_
                    if d2 < best_d2:
                        best_d2 = d2
                        best_cx = cxx
                        best_cy = cyy

            dist = math.sqrt(best_d2)
            # outside the dimple: leave BASE
            if dist >= radius:
                continue

            t = dist * inv_radius  # 0 = center, 1 = rim
            # bowl depth profile (paraboloid): 0 at rim, 1 at center
            depth = 1.0 - t * t

            # 1) Center darkness — strongest contributor to "concave" read.
            color = lerp(BASE, SHADOW, depth * 0.85)

            # 2) Rim highlight on the FAR side (opposite the light source).
            #    Inside the bowl, the lower-right wall catches the incoming light.
            dx_n = (x - best_cx) / radius
            dy_n = (y - best_cy) / radius
            # alignment with highlight direction (lower-right): peaks near the rim there
            facing = max(0.0, dx_n * hx + dy_n * hy)
            # only ramps up near the rim (t in [0.55, 1.0])
            rim_t = max(0.0, (t - 0.55) / 0.45)
            rim_strength = facing * (rim_t ** 1.3)
            color = lerp(color, RIM, rim_strength * 0.95)

            # 3) Shadowed rim on the NEAR side (upper-left), wall blocks the light.
            opposite = max(0.0, -(dx_n * hx + dy_n * hy))
            shadow_strength = opposite * (rim_t ** 1.2)
            color = lerp(color, SHADOW, shadow_strength * 0.55)

            px[x, y] = color

    if supersample > 1:
        img = img.resize((width, height), Image.LANCZOS)
    return img


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Square seamless tile — ~24 across so each dimple is ~85px at 2048,
    #    which when tiled to a 1320×2868 canvas reads as nice mid-detail.
    print("Rendering 2048×2048 seamless tile…")
    tile = render(2048, 2048, dimples_across=24, supersample=2, seamless=True)
    tile.save(OUT_DIR / "dimples-tile-2048.png", optimize=True)

    # 2. Portrait full-bleed for 9:19.5 phone canvas
    print("Rendering 1320×2868 portrait…")
    portrait = render(1320, 2868, dimples_across=18, supersample=2, seamless=False)
    portrait.save(OUT_DIR / "dimples-portrait-1320x2868.png", optimize=True)

    # 3. Landscape full-bleed
    print("Rendering 2868×1320 landscape…")
    landscape = render(2868, 1320, dimples_across=32, supersample=2, seamless=False)
    landscape.save(OUT_DIR / "dimples-landscape-2868x1320.png", optimize=True)

    print(f"Done. Files in: {OUT_DIR}")
    for p in sorted(OUT_DIR.glob("dimples-*.png")):
        print(f"  {p.name}  ({p.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
