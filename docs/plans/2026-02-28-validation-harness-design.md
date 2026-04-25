# Automated Validation Harness — Design

**Date:** 2026-02-28
**Status:** Approved
**Goal:** Enable an agentic loop where Claude autonomously tunes the detection pipeline, validates results against ground truth, and iterates — with human feedback at key decision points.

## Problem

The swing detection pipeline has 6 tunable components (`PoseHeuristics` thresholds, `ImpactDetector` algorithm, `SwingStateMachine` cooldown, etc.), but validation requires a physical iPhone. Every adjustment is blind until manually tested on device. This blocks rapid iteration.

## Key Insight

`ImpactDetector` and `PoseHeuristics` operate on `[PoseFrame]` — pure structs with joint coordinates. They never touch Vision or CoreML. If we serialize real pose data once (on device), we can test algorithms forever on the simulator.

## Architecture

### The Agentic Loop

```
┌──────────────────────────────────────────────┐
│                                              │
│  ┌─────────┐    ┌──────────┐    ┌─────────┐ │
│  │ Run     │───▶│ Read     │───▶│ Adjust  │ │
│  │ tests   │    │ scorecard│    │ code    │ │
│  └─────────┘    └──────────┘    └─────────┘ │
│       ▲                              │       │
│       └──────────────────────────────┘       │
│                                              │
│            CLAUDE AUTONOMOUS LOOP            │
└──────────────────────────────────────────────┘
                      │
                      ▼ (plateau or criteria met)
              ┌───────────────┐
              │ Human review  │
              └───────────────┘
```

1. Claude runs `xcodebuild test` on simulator
2. Reads JSON scorecard from test output
3. Identifies worst-performing videos and failure modes
4. Adjusts thresholds or algorithm logic in production files
5. Re-runs tests, compares scorecards
6. Reverts if regressions, continues if improved
7. Presents results to human when criteria met or plateau reached

### No New Packages, No CLI Tools

Everything stays in the existing project. Claude edits production files directly and reads test output. The test target is the validation harness.

## Components

### 1. PoseFrame JSON Serialization

Add `Codable` conformance to `PoseFrame` and `PoseFrame.JointPosition`. This enables serializing real pose data extracted on device into JSON files that load on any platform.

**File:** `golf-sync-swing/Models/PoseFrame.swift`

### 2. Golden Snapshots

Pre-computed `[PoseFrame]` arrays serialized as JSON. Extracted once on a physical device, committed to the repo. Each file represents one video's worth of pose data.

**Location:** `golf-sync-swingTests/TestData/snapshots/`

**Files:**
- `tiger_woods.json`, `sandra_gal.json`, `hyo_joo_kim.json`, `rory_mcilroy.json`, `paula_creamer.json`
- Future: `walking_01.json`, `practice_waggle.json`, `standing_idle.json`

### 3. Manifest

Ground truth metadata for all test clips.

**File:** `golf-sync-swingTests/TestData/snapshots/manifest.json`

```json
[
  {
    "file": "tiger_woods.json",
    "type": "swing",
    "impactTime": 2.967,
    "player": "Tiger Woods",
    "club": "iron",
    "angle": "down-the-line"
  },
  {
    "file": "walking_01.json",
    "type": "no_swing",
    "label": "Walking on range"
  }
]
```

### 4. Scorecard Test

A single test class that:
1. Loads all snapshots from the manifest
2. Runs each through `ImpactDetector.findImpactTime()` and `PoseHeuristics.analyze()`
3. Computes TP/FP/FN, precision, recall, mean/max impact error
4. Writes a structured JSON scorecard to a known path
5. Asserts against configurable success criteria

**File:** `golf-sync-swingTests/ValidationScorecardTests.swift`

**Scorecard output:**
```json
{
  "timestamp": "2026-02-28T14:30:00Z",
  "thresholds": {
    "velocityThreshold": 0.8,
    "minimumDescentFrames": 2,
    "minimumDisplacement": 0.08,
    "impactTopSearchFraction": 0.70,
    "impactPostPeakWindow": 6
  },
  "summary": {
    "totalVideos": 12,
    "swingVideos": 7,
    "noSwingVideos": 5,
    "truePositives": 7,
    "falseNegatives": 0,
    "falsePositives": 0,
    "meanImpactError": 0.34,
    "maxImpactError": 0.89,
    "precision": 1.0,
    "recall": 1.0
  },
  "perVideo": [...]
}
```

### 5. Snapshot Exporter Test

A device-only test that extracts `[PoseFrame]` from each GolfDB video and writes the JSON snapshot files. Run once to bootstrap, then again whenever adding new videos.

**File:** `golf-sync-swingTests/GolfDBValidationTests.swift` (new test method)

### 6. Snapshot Loader

A helper that reads manifest + JSON files → `[(name: String, frames: [PoseFrame], groundTruth: GroundTruth)]`.

**File:** `golf-sync-swingTests/ValidationScorecardTests.swift` (private helper)

## Success Criteria

The scorecard test asserts these minimums:

| Metric | Threshold |
|--------|-----------|
| Precision | >= 0.90 |
| Recall | >= 0.95 |
| Max impact error | <= 1.0s |
| Mean impact error | <= 0.5s |
| Regressions | 0 (no previously-passing video may fail) |

## Adding New Test Data

**Swing videos:**
1. Record on iPhone or download from GolfDB
2. Run snapshot exporter test on device
3. Copy generated JSON to `TestData/snapshots/`
4. Add entry to `manifest.json` with impact time

**Non-swing videos (false positive testing):**
1. Record standing/walking/waggling on iPhone
2. Run snapshot exporter on device
3. Copy JSON, add to manifest with `"type": "no_swing"`

## File Summary

| File | Change |
|------|--------|
| `PoseFrame.swift` | Add `Codable` conformance |
| `GolfDBValidationTests.swift` | Add snapshot exporter test (device-only) |
| `ValidationScorecardTests.swift` | NEW — scorecard test + snapshot loader |
| `TestData/snapshots/manifest.json` | NEW — ground truth manifest |
| `TestData/snapshots/*.json` | NEW — serialized pose data (generated on device) |
