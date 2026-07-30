#!/usr/bin/env bash
#
# Build an OPTIMIZED (Release) build and install it on a connected iPhone.
#
# Why: the Debug configuration compiles with SWIFT_OPTIMIZATION_LEVEL = -Onone, so every Swift
# frame of the pose pipeline runs unoptimized. Release uses -O with SWIFT_COMPILATION_MODE =
# wholemodule and drops the DEBUG compilation condition. If the camera feels sluggish, this is
# how you find out whether it is the build configuration or the code.
#
# Verified settings (xcodebuild -showBuildSettings):
#   Debug   : -Onone, ENABLE_TESTABILITY=YES, SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG
#   Release : -O (default), wholemodule, ENABLE_TESTABILITY=NO, no DEBUG
#
# NOTE: a Release build has no `#if DEBUG` affordances — the Debug settings section
# (premium toggle, demo data, reset onboarding) will be absent. That is the point: it is
# production-like.
#
# Usage:
#   scripts/build-release-device.sh                # first available device
#   scripts/build-release-device.sh <device-udid>  # a specific device
#   scripts/build-release-device.sh --simulator    # Release build on the simulator instead
#
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="golf-sync-swing.xcodeproj"
SCHEME="golf-sync-swing"
BUNDLE_ID="com.tyfoan.golf-sync-swing"
DERIVED="build/release-dd"

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }
fail() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

if [[ "${1:-}" == "--simulator" ]]; then
    log "Building Release for the iOS Simulator"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration Release \
        -destination 'platform=iOS Simulator,name=iPhone 17 CI' \
        -derivedDataPath "$DERIVED" \
        build | tail -5

    APP="$DERIVED/Build/Products/Release-iphonesimulator/$SCHEME.app"
    [[ -d "$APP" ]] || fail "build produced no .app at $APP"

    SIM_ID=$(xcrun simctl list devices available | grep -m1 -oE '[0-9A-F-]{36}') \
        || fail "no booted/available simulator"
    xcrun simctl boot "$SIM_ID" 2>/dev/null || true
    xcrun simctl install "$SIM_ID" "$APP"
    xcrun simctl launch "$SIM_ID" "$BUNDLE_ID"
    log "Installed and launched (Release) on simulator $SIM_ID"
    log "Reminder: the simulator has NO camera and Vision body pose returns nothing there."
    exit 0
fi

# ---- Device path ----

DEVICE_ID="${1:-}"
if [[ -z "$DEVICE_ID" ]]; then
    log "Looking for an available paired device"
    # devicectl reports a usable device as either "connected" (physically attached) or
    # "available (paired)" (reachable over the network) and it flips between them, so accept
    # both. `grep -v unavailable` must come FIRST: "unavailable" contains "available" as a
    # substring, so filtering on "available" alone matches every offline device too.
    DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
        | grep -v "unavailable" \
        | grep -E "connected|available" \
        | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
        | head -1) || true
fi
[[ -n "$DEVICE_ID" ]] || fail "no available device. Plug in / unlock the iPhone, then: xcrun devicectl list devices"

log "Target device: $DEVICE_ID"

# Build against the generic iOS destination rather than the specific device. xcodebuild
# identifies devices by ECID (00008130-...) while devicectl uses the CoreDevice UUID
# (7B73EE57-...) — passing the latter to xcodebuild fails with "no available devices matched".
# `generic/platform=iOS` sidesteps the mismatch entirely and does not need the device present
# at build time.
log "Building Release (optimized, signed for device)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    build | tail -8

APP="$DERIVED/Build/Products/Release-iphoneos/$SCHEME.app"
[[ -d "$APP" ]] || fail "build produced no .app at $APP"

# Confirm we really got an optimized build, rather than trusting the flag we passed.
if grep -qa "SWIFT_OPTIMIZATION_LEVEL.*Onone" "$APP/$SCHEME" 2>/dev/null; then
    log "WARNING: binary still references -Onone — check the configuration"
fi

log "Installing on device"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

log "Done. Launch it from the home screen (cold start, so you measure a real first launch)."
cat <<'NOTES'

What to compare against Debug:
  * time from tapping the Camera tab until the preview shows a live image
  * time from tapping "Start Recording" until the countdown appears
  * smoothness of the skeleton overlay during a swing

Bear in mind, and no build configuration changes these:
  * "Start Recording" runs a deliberate 5-SECOND COUNTDOWN before capture begins
    (RecordingViewModel.startRecording). That is by design, so you can walk to the ball.
  * Opening the camera does AVAudioSession.setActive(true) on .playAndRecord with Bluetooth
    options, which routinely costs a few hundred ms on its own.
  * The skeleton overlay currently defaults to ON, adding a main-queue hop and a Canvas
    redraw per analysed frame. Toggle it off with the figure button to compare.
NOTES
