# On-device debugging harness

The app runs on a physical iPhone and the only channel back has been prose. "The screen is
black" has two different causes — **the preview layer was never attached** or **the capture
session delivers no frames** — and nothing distinguished them. Three rounds were lost to that
ambiguity. This harness settles it mechanically.

| Evidence | What it proves |
| --- | --- |
| `frames_seen` (on **every** event) | whether AVFoundation delivered sample buffers |
| `frame-<NNN>.jpg` | a real buffer off the capture callback — even an all-black one proves delivery |
| `frame_capture_timeout` | a frame was requested and none came: a *positive* assertion of starvation |
| `ui-<NNN>.png` | **chrome only** — which screen is up, are the overlays there |

`ui-*.png` can never show the camera: `AVCaptureVideoPreviewLayer` draws into a render-server
surface that `drawHierarchy` composites as empty, so the preview region is black in the PNG
whether the camera is perfect or dead. Snapshot events say so via
`props.ui_excludes = "camera_preview"`. **Never conclude anything about the camera from a UI
snapshot.**

## Run it

```bash
scripts/device-probe.sh                          # build → install → run "capture-flow" → pull → summarise
scripts/device-probe.sh --scenario capture-flow  # pick the self-driving scenario
scripts/device-probe.sh --scenario ""            # recorder on, you drive the app by hand
scripts/device-probe.sh --no-build               # skip build+install, just launch and pull
scripts/device-probe.sh --pull-only              # pull only — you already drove the app
scripts/device-probe.sh --device <id> --timeout 180
```

The app is launched with `GSS_PROBE=1` (plus `GSS_SCENARIO`) in its **launch environment**;
tapping the icon or running from Xcode does not set them, so the probe stays inert there.
`--console` forwards Ctrl-C to the app for a clean stop. Results land in
`build/device-probe/<runId>/` (`runId` = `yyyyMMdd-HHmmss`, device local time), gitignored by
the existing `build/` rule.

## Reading timeline.jsonl

One JSON object per line, appended immediately — a crashed or watchdog-killed run still leaves
everything up to the moment of failure.

```json
{"t": 1.94, "event": "session_running", "props": {"frames_seen": "12"}, "ui": "ui-004.png"}
```

`t` is seconds since probe start (monotonic). `ui`/`frame` carry the line's own sequence number,
so `ui-004.png` belongs to line 4. The script prints an aligned table and a verdict, but the
timeline alone answers the question:

| Reading | Diagnosis |
| --- | --- |
| `frames_seen: "0"` at `session_running` | pipeline is dead — read the `configure_*` lines above it |
| `frames_seen` climbing, no preview-attach event | frames are fine, the layer never landed |
| frames climbing + attach landed + still black | rotation/geometry or video-gravity problem |
| `frame_capture_timeout` present | no frame arrived within the deadline |

```bash
jq -r '[.t, .event, .props.frames_seen] | @tsv' build/device-probe/<runId>/timeline.jsonl
```

## Driving by hand

`--scenario ""` enables the recorder with no automation; `--pull-only` collects whatever is
already on the device — every past run is kept there, including earlier sessions.

## Limitations — be blunt about these

- **No gesture-layer coverage.** A scenario drives view models and services, not taps. A button
  wired to nothing looks identical to a working one.
- **No system dialogs.** Permission alerts and StoreKit sheets are separate windows: absent from
  `ui-*.png` and undismissable by a scenario.
- **os_log cannot be streamed from a device on macOS 15.7** — `log stream --device-name` was
  removed, and `--console` shows only `print()`/stderr. Console.app is the one live route;
  after the fact use `log collect --device-udid 00008130-001835DC0CF8001C --last 5m` and read
  the `.logarchive` with `log show`. Mind the two namespaces: `devicectl` wants the CoreDevice
  id (`7B73EE57-…`), `log collect` wants the UDID (`00008130-…`).
- Mean luma is a 1×1 downsample, i.e. a whole-frame average: a mostly-black frame with one
  bright corner reads as dim, not zero.

## Adding a scenario

The host script needs no change — `--scenario <name>` is passed through as `GSS_SCENARIO`.
Register the name in the scenario runner under `golf-sync-swing/Services/Diagnostics/`
(alongside `DeviceProbe.swift`), keep it inside `#if DEBUG`, and have it terminate the app when
done so the script stops waiting. Record an event at every step: a step that emits nothing is
indistinguishable from a step that never ran.
