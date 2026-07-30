#!/usr/bin/env bash
#
# Drive the on-device diagnostics probe end to end: build → install → launch → pull → summarise.
#
# Why: the app runs on a physical iPhone and the only channel back has been prose ("the screen
# is black"). That sentence has two completely different causes — the preview layer was never
# attached, or the capture session delivered no frames — and nothing in a bug report separates
# them. This harness separates them mechanically:
#
#   * a  ui-<NNN>.png     is SwiftUI chrome. It NEVER proves anything about the camera.
#   * a  frame-<NNN>.jpg  is a sample buffer that actually came out of AVFoundation.
#     Its mere existence proves the pipeline delivers. Even an all-black one proves delivery
#     (covered lens / no exposure). NO frame files at all is the "no frames" diagnosis.
#
# The app writes <app Documents>/diagnostics/<runId>/{timeline.jsonl,ui-*.png,frame-*.jpg},
# appending each timeline line immediately so a crashed or hung run still yields data.
# runId is "yyyyMMdd-HHmmss" (device local time).
#
# The probe is DEBUG-only and additionally requires GSS_PROBE=1 in the launch environment, so
# a Release build has none of this and a normal Debug launch from Xcode is unaffected.
#
# Usage:
#   scripts/device-probe.sh                          # build, install, run "capture-flow", pull
#   scripts/device-probe.sh --scenario capture-flow  # pick the self-driving scenario
#   scripts/device-probe.sh --scenario ""            # recorder on, you drive the app by hand
#   scripts/device-probe.sh --no-build               # reinstall nothing, just launch + pull
#   scripts/device-probe.sh --pull-only              # you drove the app by hand — just pull
#   scripts/device-probe.sh --device <id>            # devicectl identifier override
#   scripts/device-probe.sh --timeout 180            # seconds to wait for the app to exit
#
# Output lands in build/device-probe/<runId>/ (already covered by the build/ .gitignore rule).
#
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="golf-sync-swing.xcodeproj"
SCHEME="golf-sync-swing"
BUNDLE_ID="com.tyfoan.golf-sync-swing"
DERIVED="build/probe-dd"
OUT_ROOT="build/device-probe"

SCENARIO="capture-flow"
DEVICE_ID=""
TIMEOUT=120
DO_BUILD=1
DO_LAUNCH=1

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m  ! \033[0m%s\n' "$1"; }
fail() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

usage() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# ---- Flags ----

while [[ $# -gt 0 ]]; do
    case "$1" in
        # An explicitly EMPTY scenario is meaningful: recorder on, nothing self-driving.
        --scenario) [[ $# -ge 2 ]] || fail "--scenario needs a name (\"\" for none)"; SCENARIO="$2"; shift 2 ;;
        --device) DEVICE_ID="${2:-}"; [[ -n "$DEVICE_ID" ]] || fail "--device needs an identifier"; shift 2 ;;
        --timeout) TIMEOUT="${2:-}"; [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || fail "--timeout needs seconds"; shift 2 ;;
        --no-build) DO_BUILD=0; shift ;;
        --pull-only) DO_BUILD=0; DO_LAUNCH=0; shift ;;
        -h|--help) usage 0 ;;
        *) printf 'unknown flag: %s\n' "$1" >&2; usage 1 ;;
    esac
done

# ---- Device ----

resolve_device() {
    [[ -n "$DEVICE_ID" ]] && return 0
    # A usable device reports as "connected" (attached) or "available (paired)" and flips
    # between them, so accept both. `grep -v unavailable` MUST come first: "unavailable"
    # contains "available", so filtering on "available" alone matches every offline device.
    DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
        | grep -v "unavailable" \
        | grep -E "connected|available" \
        | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
        | head -1) || true
    [[ -n "$DEVICE_ID" ]] || fail "no available device. Unlock the iPhone, then: xcrun devicectl list devices"
}

# ---- Build + install ----

build_and_install() {
    # Build against the generic iOS destination: xcodebuild identifies devices by ECID
    # (00008130-...) while devicectl uses the CoreDevice UUID (7B73EE57-...). Passing the
    # latter to xcodebuild fails with "no available devices matched".
    log "Building Debug for device (the probe is #if DEBUG, so Release would compile it away)"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration Debug \
        -destination "generic/platform=iOS" \
        -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates \
        build | tail -8

    local app="$DERIVED/Build/Products/Debug-iphoneos/$SCHEME.app"
    [[ -d "$app" ]] || fail "build produced no .app at $app"

    log "Installing on $DEVICE_ID"
    xcrun devicectl device install app --device "$DEVICE_ID" "$app" | tail -3
}

# ---- Launch ----

launch_probe() {
    log "Launching with GSS_PROBE=1${SCENARIO:+ GSS_SCENARIO=$SCENARIO} (waiting up to ${TIMEOUT}s)"
    [[ -n "$SCENARIO" ]] || printf '    No scenario: the recorder is on and the app is yours to drive by hand.\n'
    printf '    Ctrl-C forwards a catchable signal to the app, so it stops cleanly.\n\n'

    # --environment-variables is the contracted mechanism and overrides any DEVICECTL_CHILD_*
    # already exported in this shell. --console attaches stdout/stderr and waits for exit;
    # --timeout bounds that wait. A non-zero exit here is NOT fatal: the timeline is appended
    # line by line, so a hung or crashed run still has data worth pulling.
    local env_json='{"GSS_PROBE":"1"}' rc=0
    [[ -n "$SCENARIO" ]] && env_json=$(printf '{"GSS_PROBE":"1","GSS_SCENARIO":"%s"}' "$SCENARIO")
    xcrun devicectl device process launch \
        --console \
        --terminate-existing \
        --timeout "$TIMEOUT" \
        --device "$DEVICE_ID" \
        --environment-variables "$env_json" \
        "$BUNDLE_ID" || rc=$?

    [[ $rc -eq 0 ]] || warn "launch exited $rc (timed out, or the app is still up) — pulling anyway"
}

# ---- Pull ----

# devicectl copies the CONTENTS of --source into an existing --destination, so the runs land
# at <stage>/<runId>. Rather than bank on that, discover run directories by their
# yyyyMMdd-HHmmss name anywhere in the staged tree — correct under either layout.
pull_diagnostics() {
    local stage="$OUT_ROOT/.pull-$(date +%Y%m%d-%H%M%S)"
    local copylog="$stage.log"
    mkdir -p "$stage"

    log "Pulling Documents/diagnostics from $BUNDLE_ID"
    local rc=0
    xcrun devicectl device copy from \
        --device "$DEVICE_ID" \
        --domain-type appDataContainer \
        --domain-identifier "$BUNDLE_ID" \
        --source Documents/diagnostics \
        --destination "$stage" >"$copylog" 2>&1 || rc=$?

    local pulled=0 run dest
    while IFS= read -r run; do
        dest="$OUT_ROOT/$(basename "$run")"
        rm -rf "$dest"
        mv "$run" "$dest"
        pulled=$((pulled + 1))
    done < <(find "$stage" -type d -name "????????-??????" 2>/dev/null | sort)
    rm -rf "$stage"

    [[ $pulled -gt 0 ]] && { rm -f "$copylog"; log "Pulled $pulled run(s) into $OUT_ROOT/"; return 0; }

    printf '\n'
    fail "$(cat <<EOF
no diagnostics pulled (copy exit $rc). devicectl said:
$(grep -iE "error|denied|locked" "$copylog" | head -3 | sed 's/^/  /')

CoreDeviceError 7000 means the folder simply is not there — the app never created
Documents/diagnostics. In order of likelihood:
  1. The installed build predates the probe, or was built Release — rerun without --no-build.
  2. GSS_PROBE was not seen at launch. It must be in the LAUNCH environment, not your shell:
     tapping the app on the home screen, or running from Xcode, will NOT set it.
  3. The app crashed during startup, before the probe opened its run directory.
     Check with: xcrun devicectl device info processes --device $DEVICE_ID
Full copy log: $copylog
EOF
)"
}

# ---- Summary ----

newest_run_with_timeline() {
    local d
    for d in $(find "$OUT_ROOT" -maxdepth 1 -type d -name "????????-??????" | sort -r); do
        [[ -s "$d/timeline.jsonl" ]] && { printf '%s' "$d"; return 0; }
    done
    return 1
}

diagnose_missing_timeline() {
    local newest
    newest=$(find "$OUT_ROOT" -maxdepth 1 -type d -name "????????-??????" | sort -r | head -1)

    printf '\n'
    [[ -n "$newest" ]] || fail "no run directories under $OUT_ROOT/ — see the pull diagnosis above."

    warn "run $(basename "$newest") has no usable timeline.jsonl"
    if [[ -f "$newest/timeline.jsonl" ]]; then
        fail "$(cat <<EOF
timeline.jsonl exists but is ZERO BYTES.

The probe started and opened a run directory, then emitted nothing. That points at the
scenario, not at the probe:
  * GSS_SCENARIO="$SCENARIO" may not match any registered scenario name (a typo is silent).
  * The scenario may have thrown or awaited forever before its first recorded event.
Try a run with no scenario at all to confirm the recorder itself works:
  scripts/device-probe.sh --scenario ""
EOF
)"
    fi
    fail "$(cat <<EOF
the run directory exists but contains NO timeline.jsonl at all.

The probe created its directory and then died before the first append — a crash inside probe
start-up, or the file handle was never opened. Files actually present:
$(ls -lA "$newest" | tail -n +2 | sed 's/^/  /')
EOF
)"
}

print_timeline() {
    local run="$1"
    log "Timeline — $(basename "$run")  ($run/timeline.jsonl)"

    command -v python3 >/dev/null 2>&1 || { cat "$run/timeline.jsonl"; return 0; }

    python3 - "$run/timeline.jsonl" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="replace") as handle:
    lines = [line.strip() for line in handle.read().splitlines() if line.strip()]

# Elide long values so one verbose prop cannot wreck the table. Nothing is lost: the file
# itself is right there, and its path is printed above.
def clip(value, limit=44):
    value = str(value)
    return value if len(value) <= limit else value[:limit - 1] + "…"

def props_of(obj):
    props = obj.get("props") or {}
    if not isinstance(props, dict):
        return clip(props)
    return "  ".join(f"{key}={clip(value)}" for key, value in props.items())

def artifacts_of(obj):
    return " ".join(str(obj[key]) for key in ("ui", "frame") if obj.get(key))

rows, truncated = [], 0
for raw in lines:
    try:
        obj = json.loads(raw)
    except ValueError:
        truncated += 1
        rows.append(("     ?", "<unparseable>", raw[:70], ""))
        continue
    stamp = obj.get("t")
    stamp = f"{stamp:6.3f}" if isinstance(stamp, (int, float)) else "     ?"
    rows.append((stamp, str(obj.get("event", "?")), props_of(obj), artifacts_of(obj)))

# Pad to the widest value so the columns line up, but cap the padding: one monster props
# value should overflow its own row rather than stretch every other row.
events = min(max([len(row[1]) for row in rows] + [8]), 34)
props = min(max([len(row[2]) for row in rows] + [8]), 56)
print(f"\n  {'t':>6}  {'event':<{events}}  {'props':<{props}}  artifacts")
print(f"  {'-' * 6}  {'-' * events}  {'-' * props}  {'-' * 22}")
for stamp, event, prop, artifacts in rows:
    print(f"  {stamp}  {event:<{events}}  {prop:<{props}}  {artifacts}".rstrip())

print(f"\n  {len(rows)} event(s).")
if truncated:
    print(f"  {truncated} unparseable line(s) — the app most likely died mid-write.")
PY
}

# Mean luminance via a 1x1 downsample. sips writes a 24-bit BMP: 54-byte header, then the
# single pixel as B,G,R (rows are padded to 4 bytes, hence 58 bytes total). Averaging the
# three bytes is a real mean over the whole frame, not a spot sample.
frame_luma() {
    local jpg="$1" bmp="$OUT_ROOT/.px.bmp" value=""
    if sips -s format bmp -z 1 1 "$jpg" --out "$bmp" >/dev/null 2>&1; then
        value=$(od -An -tu1 -j 54 -N 3 "$bmp" 2>/dev/null \
            | awk 'NF >= 3 { printf "%d", ($1 + $2 + $3) / 3; exit }')
    fi
    rm -f "$bmp"
    printf '%s' "${value:--1}"
}

# du -h rounds to the 4 KB block, which hides the very difference that matters here: a JPEG
# of a flat black frame compresses to a fraction of a real one.
human_size() {
    stat -f %z "$1" 2>/dev/null | awk '{ printf "%.1f KB", $1 / 1024 }'
}

print_artifacts() {
    local run="$1" file luma verdict
    log "Artifacts"

    while IFS= read -r file; do
        printf '  %-16s %10s   UI chrome only — says nothing about the camera\n' \
            "$(basename "$file")" "$(human_size "$file")"
    done < <(find "$run" -maxdepth 1 -name "ui-*.png" | sort)

    while IFS= read -r file; do
        luma=$(frame_luma "$file")
        verdict="image present"
        [[ "$luma" -lt 32 ]] 2>/dev/null && verdict="very dark"
        [[ "$luma" -lt 8 ]] 2>/dev/null && verdict="ALL BLACK — buffer delivered, no image (lens covered / no exposure)"
        [[ "$luma" -lt 0 ]] 2>/dev/null && verdict="unreadable by sips — corrupt JPEG?"
        printf '  %-16s %10s   mean luma %3s   %s\n' \
            "$(basename "$file")" "$(human_size "$file")" "$luma" "$verdict"
    done < <(find "$run" -maxdepth 1 -name "frame-*.jpg" | sort)

    printf '\n  A frame-*.jpg is a real sample buffer off the capture callback. A ui-*.png is the\n'
    printf '  app layer tree only: the preview is a render-server surface that drawHierarchy\n'
    printf '  composites as EMPTY, so it reads black there whether the camera works or not.\n'
}

# The headline answer. The probe stamps frames_seen / last_frame_age_s onto EVERY event and
# emits frame_capture_timeout when a requested frame never arrives, so the timeline settles
# the founding question on its own — the artifacts are corroboration, not the proof.
print_verdict() {
    local run="$1"
    log "Verdict"

    command -v python3 >/dev/null 2>&1 || { printf '  (python3 unavailable — read frames_seen in the timeline above)\n'; return 0; }

    python3 - "$run/timeline.jsonl" "$(find "$run" -maxdepth 1 -name "frame-*.jpg" | wc -l | tr -d ' ')" <<'PY'
import json
import sys

path, files = sys.argv[1], int(sys.argv[2])
seen, timeouts, last_event = 0, 0, "?"
with open(path, "r", encoding="utf-8", errors="replace") as handle:
    for raw in handle:
        raw = raw.strip()
        if not raw:
            continue
        try:
            obj = json.loads(raw)
        except ValueError:
            continue
        last_event = obj.get("event", last_event)
        if obj.get("event") == "frame_capture_timeout":
            timeouts += 1
        value = (obj.get("props") or {}).get("frames_seen", "")
        seen = max(seen, int(value)) if str(value).isdigit() else seen

print(f"  frames_seen (peak) : {seen}")
print(f"  frame artifacts    : {files}")
print(f"  frame timeouts     : {timeouts}")
print(f"  last event         : {last_event}")
print()
if seen == 0:
    print("  CAPTURE PIPELINE IS DEAD — no sample buffer ever reached the app.")
    print("  A black screen here is the session, not the UI. Read the configure_* lines above")
    print("  for where bring-up stopped; a ui-*.png cannot add anything to this.")
else:
    print(f"  CAPTURE PIPELINE IS ALIVE — {seen} sample buffers counted.")
    print("  If the screen still looked black, the fault is DOWNSTREAM of the session:")
    print("  preview layer never attached, wrong geometry/gravity, or z-order.")
if timeouts:
    print(f"\n  {timeouts} frame_capture_timeout event(s): a frame was requested and none arrived")
    print("  within the deadline. That is a positive assertion of starvation, not a missing file.")
PY
}

# A run that died before its first append would otherwise hide behind a healthy older run,
# so call it out by name instead of silently summarising the wrong run.
print_stale_runs() {
    local current="$1" run stale=""
    while IFS= read -r run; do
        [[ "$run" == "$current" ]] && continue
        [[ -s "$run/timeline.jsonl" ]] && continue
        stale="$stale      $run"$'\n'
    done < <(find "$OUT_ROOT" -maxdepth 1 -type d -name "????????-??????" | sort)

    [[ -n "$stale" ]] || return 0
    printf '\n'
    warn "run(s) with an empty or missing timeline (the probe died before writing):"
    printf '%s' "$stale"
}

# ---- Run ----

resolve_device
log "Target device: $DEVICE_ID"
mkdir -p "$OUT_ROOT"

[[ $DO_BUILD -eq 1 ]] && build_and_install
[[ $DO_LAUNCH -eq 1 ]] && launch_probe
[[ $DO_LAUNCH -eq 1 ]] || log "Skipping launch (--pull-only): --scenario is IGNORED, reading whatever is already on the device"

pull_diagnostics

RUN=$(newest_run_with_timeline) || diagnose_missing_timeline
print_timeline "$RUN"
print_artifacts "$RUN"
print_verdict "$RUN"
print_stale_runs "$RUN"

log "Done. Full run: $RUN"
