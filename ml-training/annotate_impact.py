#!/usr/bin/env python3
"""
annotate_impact.py

Interactive HTML tool for manually marking impact frames in youtube-test videos.
Opens a browser page where you can step frame-by-frame through each video and
click to mark the exact impact moment.

Usage: python3 annotate_impact.py
Output: /tmp/impact_annotator/index.html (open in browser)
        After annotation, saves to /tmp/impact_annotations.json

Workflow:
  1. Run this script to extract frames from each video
  2. Open /tmp/impact_annotator/index.html
  3. Click on the impact frame for each video
  4. Click "Export JSON" when done — copies to clipboard and saves
"""

import json
import os
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
VIDEOS_DIR = os.path.join(PROJECT_ROOT, "golf-sync-swingTests", "youtube-tests")
GT_PATH = os.path.join(VIDEOS_DIR, "youtube_ground_truth.json")
OUTPUT_DIR = "/tmp/impact_annotator"
FRAMES_DIR = os.path.join(OUTPUT_DIR, "frames")

# Extract frames at 30fps for fine-grained selection
EXTRACT_FPS = 30


def extract_all_frames(video_path, video_id):
    """Extract every frame at EXTRACT_FPS from the video."""
    video_frames_dir = os.path.join(FRAMES_DIR, video_id)
    os.makedirs(video_frames_dir, exist_ok=True)

    # Check if already extracted
    existing = [f for f in os.listdir(video_frames_dir) if f.endswith(".jpg")]
    if len(existing) > 10:
        return len(existing)

    cmd = [
        "ffmpeg", "-y", "-i", video_path,
        "-vf", f"fps={EXTRACT_FPS}",
        "-q:v", "3",
        os.path.join(video_frames_dir, "frame_%04d.jpg"),
    ]
    subprocess.run(cmd, capture_output=True)

    return len([f for f in os.listdir(video_frames_dir) if f.endswith(".jpg")])


def get_video_duration(video_path):
    """Get video duration using ffprobe."""
    cmd = [
        "ffprobe", "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        video_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    try:
        return float(result.stdout.strip())
    except ValueError:
        return 0


def main():
    os.makedirs(FRAMES_DIR, exist_ok=True)

    with open(GT_PATH) as f:
        ground_truth = json.load(f)

    videos = []
    for entry in ground_truth:
        video_path = os.path.join(VIDEOS_DIR, entry["filename"])
        if not os.path.exists(video_path):
            print(f"SKIP: {entry['filename']} not found")
            continue

        yt_id = entry["youtube_id"]
        print(f"Extracting frames: {entry['player']} ({yt_id})...", end=" ", flush=True)

        frame_count = extract_all_frames(video_path, yt_id)
        duration = get_video_duration(video_path)
        print(f"{frame_count} frames, {duration:.2f}s")

        videos.append({
            "id": yt_id,
            "player": entry["player"],
            "club": entry["club"],
            "view": entry["view"],
            "filename": entry["filename"],
            "golfdb_impact": entry["impact_time_sec"],
            "frame_count": frame_count,
            "duration": round(duration, 3),
            "fps": EXTRACT_FPS,
        })

    generate_html(videos)
    print(f"\nAnnotation tool: file://{OUTPUT_DIR}/index.html")
    print(f"Open with: open {OUTPUT_DIR}/index.html")


def generate_html(videos):
    videos_json = json.dumps(videos, indent=2)

    page = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Impact Annotator — {len(videos)} videos</title>
<style>
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ font-family: -apple-system, system-ui, sans-serif; background: #1a1a2e; color: #eee; }}

.toolbar {{
    position: fixed; top: 0; left: 0; right: 0; z-index: 100;
    background: #16213e; border-bottom: 1px solid #333; padding: 8px 16px;
    display: flex; align-items: center; gap: 12px;
}}
.toolbar .progress {{ color: #aaa; font-size: 13px; }}
.toolbar button {{
    padding: 6px 16px; border: 1px solid #444; background: #2a2a4a;
    color: #ccc; border-radius: 4px; cursor: pointer; font-size: 13px;
}}
.toolbar button:hover {{ background: #3a3a6a; }}
.toolbar button.primary {{ background: #27ae60; color: #fff; border-color: #2ecc71; }}
.toolbar button.primary:hover {{ background: #2ecc71; }}
.toolbar .nav-btn {{ font-size: 18px; padding: 4px 12px; }}

.main {{ padding-top: 60px; }}

.video-card {{
    max-width: 900px; margin: 20px auto; background: #16213e;
    border-radius: 8px; overflow: hidden; border: 2px solid transparent;
}}
.video-card.active {{ border-color: #3498db; }}
.video-card.annotated {{ border-color: #27ae60; }}

.card-header {{
    padding: 10px 16px; display: flex; align-items: center; gap: 12px;
    background: #1a1a3e; flex-wrap: wrap;
}}
.card-header .player {{ font-weight: 600; font-size: 15px; }}
.card-header .meta {{ color: #888; font-size: 13px; }}
.card-header .status {{
    margin-left: auto; font-size: 12px; font-weight: 700;
    padding: 2px 8px; border-radius: 3px;
}}
.status.pending {{ background: #444; color: #aaa; }}
.status.done {{ background: #27ae60; color: #fff; }}

.frame-viewer {{
    position: relative; background: #000; text-align: center;
    min-height: 200px; display: flex; align-items: center; justify-content: center;
}}
.frame-viewer img {{
    max-width: 100%; max-height: 500px; display: block; margin: 0 auto;
}}
.frame-overlay {{
    position: absolute; top: 8px; left: 8px; right: 8px;
    display: flex; justify-content: space-between; pointer-events: none;
}}
.frame-info {{
    background: rgba(0,0,0,0.7); padding: 4px 10px; border-radius: 4px;
    font-family: monospace; font-size: 13px;
}}
.frame-info.impact {{ background: rgba(39,174,96,0.8); }}

.controls {{
    padding: 12px 16px; display: flex; align-items: center; gap: 8px;
    flex-wrap: wrap;
}}
.controls button {{
    padding: 6px 12px; border: 1px solid #444; background: #2a2a4a;
    color: #ccc; border-radius: 4px; cursor: pointer; font-size: 13px;
}}
.controls button:hover {{ background: #3a3a6a; }}
.controls button.mark {{ background: #c0392b; color: #fff; border-color: #e74c3c; font-weight: 600; }}
.controls button.mark:hover {{ background: #e74c3c; }}

.scrubber {{
    flex: 1; min-width: 200px; -webkit-appearance: none; appearance: none;
    height: 6px; background: #333; border-radius: 3px; outline: none;
}}
.scrubber::-webkit-slider-thumb {{
    -webkit-appearance: none; appearance: none; width: 16px; height: 16px;
    background: #3498db; border-radius: 50%; cursor: pointer;
}}

.golfdb-ref {{
    padding: 4px 16px 12px; font-size: 12px; color: #666;
}}
</style>
</head>
<body>

<div class="toolbar">
    <button class="nav-btn" onclick="prevVideo()">&larr;</button>
    <button class="nav-btn" onclick="nextVideo()">&rarr;</button>
    <span class="progress" id="progress">0/0 annotated</span>
    <span style="flex:1"></span>
    <button onclick="exportJSON()" class="primary">Export JSON</button>
</div>

<div class="main" id="main"></div>

<script>
const videos = {videos_json};
const annotations = {{}};
let currentVideoIdx = 0;
let currentFrames = {{}};

// Load any saved annotations
try {{
    const saved = localStorage.getItem('impact_annotations');
    if (saved) Object.assign(annotations, JSON.parse(saved));
}} catch(e) {{}}

function init() {{
    renderAll();
    updateProgress();
    scrollToVideo(0);
}}

function renderAll() {{
    const main = document.getElementById('main');
    main.innerHTML = videos.map((v, i) => renderCard(v, i)).join('');
}}

function renderCard(video, idx) {{
    const isActive = idx === currentVideoIdx;
    const isAnnotated = annotations[video.id] !== undefined;
    const frameNum = currentFrames[video.id] || 1;
    const totalFrames = video.frame_count;
    const time = ((frameNum - 1) / video.fps).toFixed(3);
    const annotatedTime = isAnnotated ? annotations[video.id].toFixed(3) : null;
    const annotatedFrame = isAnnotated ? Math.round(annotations[video.id] * video.fps) + 1 : null;
    const isOnAnnotated = isAnnotated && frameNum === annotatedFrame;

    return `
    <div class="video-card ${{isActive ? 'active' : ''}} ${{isAnnotated ? 'annotated' : ''}}"
         id="card-${{idx}}" onclick="selectVideo(${{idx}})">
        <div class="card-header">
            <span class="player">${{video.player}}</span>
            <span class="meta">${{video.club}} / ${{video.view}}</span>
            <span class="status ${{isAnnotated ? 'done' : 'pending'}}">
                ${{isAnnotated ? 'MARKED @ ' + annotatedTime + 's' : 'PENDING'}}
            </span>
        </div>
        <div class="frame-viewer">
            <img src="frames/${{video.id}}/frame_${{String(frameNum).padStart(4, '0')}}.jpg"
                 id="img-${{idx}}" loading="lazy">
            <div class="frame-overlay">
                <div class="frame-info ${{isOnAnnotated ? 'impact' : ''}}">
                    Frame ${{frameNum}}/${{totalFrames}} &mdash; ${{time}}s
                </div>
                <div class="frame-info">
                    GolfDB: ${{video.golfdb_impact.toFixed(3)}}s
                </div>
            </div>
        </div>
        <div class="controls">
            <button onclick="event.stopPropagation(); stepFrame(${{idx}}, -10)">&laquo;10</button>
            <button onclick="event.stopPropagation(); stepFrame(${{idx}}, -1)">&lsaquo; 1</button>
            <input type="range" class="scrubber" min="1" max="${{totalFrames}}"
                   value="${{frameNum}}"
                   oninput="event.stopPropagation(); seekFrame(${{idx}}, parseInt(this.value))"
                   onclick="event.stopPropagation()">
            <button onclick="event.stopPropagation(); stepFrame(${{idx}}, 1)">1 &rsaquo;</button>
            <button onclick="event.stopPropagation(); stepFrame(${{idx}}, 10)">10&raquo;</button>
            <button class="mark"
                    onclick="event.stopPropagation(); markImpact(${{idx}})">
                MARK IMPACT
            </button>
        </div>
        <div class="golfdb-ref">
            GolfDB impact: ${{video.golfdb_impact.toFixed(3)}}s (frame ~${{Math.round(video.golfdb_impact * video.fps) + 1}})
            ${{isAnnotated ? ' | Your mark: ' + annotatedTime + 's (frame ' + annotatedFrame + ')' : ''}}
        </div>
    </div>`;
}}

function selectVideo(idx) {{
    currentVideoIdx = idx;
    renderAll();
}}

function scrollToVideo(idx) {{
    const el = document.getElementById('card-' + idx);
    if (el) el.scrollIntoView({{ behavior: 'smooth', block: 'center' }});
}}

function stepFrame(idx, delta) {{
    const video = videos[idx];
    const current = currentFrames[video.id] || 1;
    const next = Math.max(1, Math.min(video.frame_count, current + delta));
    currentFrames[video.id] = next;
    currentVideoIdx = idx;
    renderAll();
}}

function seekFrame(idx, frame) {{
    const video = videos[idx];
    currentFrames[video.id] = frame;
    currentVideoIdx = idx;
    renderAll();
}}

function markImpact(idx) {{
    const video = videos[idx];
    const frameNum = currentFrames[video.id] || 1;
    const time = (frameNum - 1) / video.fps;
    annotations[video.id] = parseFloat(time.toFixed(4));
    localStorage.setItem('impact_annotations', JSON.stringify(annotations));
    updateProgress();
    renderAll();

    // Auto-advance to next unannotated video
    const nextUnannotated = videos.findIndex((v, i) => i > idx && !annotations[v.id]);
    if (nextUnannotated >= 0) {{
        // Jump to GolfDB reference frame for next video
        const nextVideo = videos[nextUnannotated];
        const refFrame = Math.round(nextVideo.golfdb_impact * nextVideo.fps) + 1;
        currentFrames[nextVideo.id] = Math.max(1, Math.min(nextVideo.frame_count, refFrame));
        currentVideoIdx = nextUnannotated;
        setTimeout(() => {{
            renderAll();
            scrollToVideo(nextUnannotated);
        }}, 100);
    }}
}}

function prevVideo() {{
    if (currentVideoIdx > 0) {{
        currentVideoIdx--;
        renderAll();
        scrollToVideo(currentVideoIdx);
    }}
}}

function nextVideo() {{
    if (currentVideoIdx < videos.length - 1) {{
        currentVideoIdx++;
        renderAll();
        scrollToVideo(currentVideoIdx);
    }}
}}

function updateProgress() {{
    const done = videos.filter(v => annotations[v.id] !== undefined).length;
    document.getElementById('progress').textContent =
        `${{done}}/${{videos.length}} annotated`;
}}

function exportJSON() {{
    const result = videos.map(v => ({{
        youtube_id: v.id,
        player: v.player,
        club: v.club,
        view: v.view,
        filename: v.filename,
        golfdb_impact_sec: v.golfdb_impact,
        manual_impact_sec: annotations[v.id] ?? null,
        fps: v.fps,
    }}));

    const jsonStr = JSON.stringify(result, null, 2);

    // Copy to clipboard
    navigator.clipboard.writeText(jsonStr).then(() => {{
        alert('Annotations copied to clipboard!\\n\\nAlso saved to localStorage.\\nPaste into /tmp/impact_annotations.json');
    }}).catch(() => {{
        // Fallback: show in textarea
        const ta = document.createElement('textarea');
        ta.value = jsonStr;
        ta.style.cssText = 'position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);width:80%;height:60%;z-index:999;font-family:monospace;font-size:12px';
        document.body.appendChild(ta);
        ta.select();
    }});
}}

// Keyboard shortcuts
document.addEventListener('keydown', (e) => {{
    if (e.target.tagName === 'INPUT') return;
    const idx = currentVideoIdx;
    switch(e.key) {{
        case 'ArrowLeft': stepFrame(idx, e.shiftKey ? -10 : -1); e.preventDefault(); break;
        case 'ArrowRight': stepFrame(idx, e.shiftKey ? 10 : 1); e.preventDefault(); break;
        case 'ArrowUp': prevVideo(); e.preventDefault(); break;
        case 'ArrowDown': nextVideo(); e.preventDefault(); break;
        case 'Enter': case ' ': markImpact(idx); e.preventDefault(); break;
        case 'g': {{
            // Jump to GolfDB reference frame
            const v = videos[idx];
            const refFrame = Math.round(v.golfdb_impact * v.fps) + 1;
            seekFrame(idx, Math.max(1, Math.min(v.frame_count, refFrame)));
            e.preventDefault();
            break;
        }}
    }}
}});

init();
</script>
</body>
</html>"""

    with open(os.path.join(OUTPUT_DIR, "index.html"), "w") as f:
        f.write(page)


if __name__ == "__main__":
    main()
