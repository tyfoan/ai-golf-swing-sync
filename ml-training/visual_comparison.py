#!/usr/bin/env python3
"""
visual_comparison.py

Extracts frames at expected vs detected impact times from each youtube-test video
and generates an HTML comparison page.

Usage: python3 visual_comparison.py
Output: /tmp/impact_comparison/index.html (open in browser)
"""

import json
import os
import subprocess
import html

SCORECARD = "/tmp/youtube_scorecard.json"
VIDEOS_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "golf-sync-swingTests", "youtube-tests"
)
OUTPUT_DIR = "/tmp/impact_comparison"
FRAMES_DIR = os.path.join(OUTPUT_DIR, "frames")


def extract_frame(video_path, timestamp, output_path):
    """Extract a single frame at the given timestamp using ffmpeg."""
    cmd = [
        "ffmpeg", "-y", "-ss", str(timestamp),
        "-i", video_path, "-frames:v", "1",
        "-q:v", "2", output_path
    ]
    subprocess.run(cmd, capture_output=True)
    return os.path.exists(output_path)


def main():
    os.makedirs(FRAMES_DIR, exist_ok=True)

    with open(SCORECARD) as f:
        scorecard = json.load(f)

    videos = scorecard["perVideo"]
    thresholds = scorecard["thresholds"]
    summary = scorecard["summary"]

    results = []

    for entry in videos:
        name = entry["name"].replace(".json", "")
        video_path = os.path.join(VIDEOS_DIR, f"golfdb_{name}.mp4")
        if not os.path.exists(video_path):
            video_path = os.path.join(VIDEOS_DIR, f"{name}.mp4")

        if not os.path.exists(video_path):
            print(f"SKIP: {name}.mp4 not found")
            continue

        expected = entry["expectedImpact"]
        detected = entry.get("detectedImpact")
        error = entry.get("error")
        passed = entry["pass"]
        swing = entry["swingDetected"]

        # Extract expected frame
        expected_img = os.path.join(FRAMES_DIR, f"{name}_expected.jpg")
        extract_frame(video_path, expected, expected_img)

        # Extract detected frame (if available)
        detected_img = None
        if detected is not None:
            detected_img = os.path.join(FRAMES_DIR, f"{name}_detected.jpg")
            extract_frame(video_path, detected, detected_img)

        results.append({
            "name": name,
            "player": entry.get("player", "?"),
            "club": entry.get("club", "?"),
            "angle": entry.get("angle", "?"),
            "expected": expected,
            "detected": detected,
            "error": error,
            "passed": passed,
            "swing": swing,
            "expected_img": os.path.basename(expected_img),
            "detected_img": os.path.basename(detected_img) if detected_img else None,
        })

        status = "PASS" if passed else "FAIL"
        err_str = f"{error:.3f}s" if error else "n/a"
        print(f"{status} {entry.get('player', '?')} — error={err_str}")

    # Sort: failures first, then by error descending
    results.sort(key=lambda r: (r["passed"], -(r["error"] or 0)))

    # Generate HTML
    generate_html(results, summary, thresholds)
    print(f"\nComparison page: file://{OUTPUT_DIR}/index.html")
    print(f"Open with: open {OUTPUT_DIR}/index.html")


def generate_html(results, summary, thresholds):
    passing = sum(1 for r in results if r["passed"])
    total = len(results)

    rows = []
    for r in results:
        status_class = "pass" if r["passed"] else "fail"
        status_text = "PASS" if r["passed"] else "FAIL"
        err_str = f'{r["error"]:.3f}s' if r["error"] is not None else "n/a"
        det_str = f'{r["detected"]:.3f}s' if r["detected"] is not None else "none"

        detected_cell = ""
        if r["detected_img"]:
            detected_cell = f'<img src="frames/{r["detected_img"]}" loading="lazy">'
        else:
            detected_cell = '<div class="no-detect">No detection</div>'

        rows.append(f"""
        <div class="card {status_class}">
            <div class="header">
                <span class="status {status_class}">{status_text}</span>
                <span class="player">{html.escape(r['player'])}</span>
                <span class="meta">{html.escape(r['club'])} / {html.escape(r['angle'])}</span>
                <span class="error">error: {err_str}</span>
            </div>
            <div class="frames">
                <div class="frame-col">
                    <div class="label">Expected @ {r['expected']:.3f}s</div>
                    <img src="frames/{r['expected_img']}" loading="lazy">
                </div>
                <div class="frame-col">
                    <div class="label">Detected @ {det_str}</div>
                    {detected_cell}
                </div>
            </div>
        </div>
        """)

    page = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Impact Detection Comparison — {passing}/{total}</title>
<style>
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ font-family: -apple-system, system-ui, sans-serif; background: #1a1a2e; color: #eee; padding: 20px; }}
h1 {{ text-align: center; margin-bottom: 5px; font-size: 24px; }}
.summary {{ text-align: center; color: #aaa; margin-bottom: 20px; font-size: 14px; }}
.summary span {{ margin: 0 10px; }}
.filters {{ text-align: center; margin-bottom: 20px; }}
.filters button {{ padding: 6px 16px; margin: 0 4px; border: 1px solid #444; background: #2a2a4a;
    color: #ccc; border-radius: 4px; cursor: pointer; font-size: 13px; }}
.filters button.active {{ background: #4a4a8a; color: #fff; border-color: #6a6aba; }}
.card {{ background: #16213e; border-radius: 8px; margin-bottom: 16px; overflow: hidden;
    border-left: 4px solid #444; }}
.card.pass {{ border-left-color: #2ecc71; }}
.card.fail {{ border-left-color: #e74c3c; }}
.header {{ padding: 10px 16px; display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }}
.status {{ font-weight: 700; font-size: 13px; padding: 2px 8px; border-radius: 3px; }}
.status.pass {{ background: #27ae60; color: #fff; }}
.status.fail {{ background: #c0392b; color: #fff; }}
.player {{ font-weight: 600; font-size: 15px; }}
.meta {{ color: #888; font-size: 13px; }}
.error {{ margin-left: auto; font-family: monospace; font-size: 13px; color: #f39c12; }}
.frames {{ display: flex; gap: 8px; padding: 0 16px 16px; }}
.frame-col {{ flex: 1; }}
.frame-col .label {{ font-size: 12px; color: #999; margin-bottom: 4px; text-align: center; }}
.frame-col img {{ width: 100%; border-radius: 4px; display: block; }}
.no-detect {{ height: 200px; display: flex; align-items: center; justify-content: center;
    background: #0f1629; border-radius: 4px; color: #666; }}
</style>
</head>
<body>
<h1>Impact Detection: {passing}/{total} passing</h1>
<div class="summary">
    <span>Recall: {summary['recall']:.0%}</span>
    <span>Mean error: {summary['meanImpactError']:.3f}s</span>
    <span>Max error: {summary['maxImpactError']:.3f}s</span>
    <span>Thresholds: vel={thresholds['velocityThreshold']}, descent={thresholds['minimumDescentFrames']}, disp={thresholds['minimumDisplacement']}</span>
</div>
<div class="filters">
    <button class="active" onclick="filter('all')">All ({total})</button>
    <button onclick="filter('fail')">Failures ({total - passing})</button>
    <button onclick="filter('pass')">Passing ({passing})</button>
</div>
<div id="cards">
{''.join(rows)}
</div>
<script>
function filter(mode) {{
    document.querySelectorAll('.filters button').forEach(b => b.classList.remove('active'));
    event.target.classList.add('active');
    document.querySelectorAll('.card').forEach(c => {{
        if (mode === 'all') c.style.display = '';
        else if (mode === 'fail') c.style.display = c.classList.contains('fail') ? '' : 'none';
        else c.style.display = c.classList.contains('pass') ? '' : 'none';
    }});
}}
</script>
</body>
</html>"""

    with open(os.path.join(OUTPUT_DIR, "index.html"), "w") as f:
        f.write(page)


if __name__ == "__main__":
    main()
