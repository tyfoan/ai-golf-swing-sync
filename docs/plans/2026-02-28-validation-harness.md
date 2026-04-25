# Validation Harness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a golden-snapshot validation system that lets Claude autonomously tune the detection pipeline in a test-adjust-retest loop, all on the simulator — no iPhone required.

**Architecture:** Serialize real `[PoseFrame]` data (extracted once on device) as JSON. A scorecard test loads every snapshot, runs it through the production `ImpactDetector` and `PoseHeuristics`, computes precision/recall/error metrics, and writes a machine-readable JSON scorecard. Claude reads the scorecard, adjusts code, re-runs tests, compares results.

**Tech Stack:** Swift Testing framework, `Codable`, `VNHumanBodyPoseObservation.JointName` (string-keyed for serialization), existing test target.

---

## Task 1: Make PoseFrame.JointPosition Codable

**Files:**
- Modify: `golf-sync-swing/Models/PoseFrame.swift`
- Test: `golf-sync-swingTests/ValidationScorecardTests.swift` (new file)

**Step 1: Write the failing test**

Create `golf-sync-swingTests/ValidationScorecardTests.swift`:

```swift
//
//  ValidationScorecardTests.swift
//  golf-sync-swingTests
//

import Testing
import Foundation
import Vision
@testable import golf_sync_swing

struct ValidationScorecardTests {

    // MARK: - Serialization

    @Test("JointPosition round-trips through JSON")
    func jointPositionCodable() throws {
        let original = PoseFrame.JointPosition(x: 0.42, y: 0.31, confidence: 0.92)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PoseFrame.JointPosition.self, from: data)

        #expect(decoded.x == original.x)
        #expect(decoded.y == original.y)
        #expect(decoded.confidence == original.confidence)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/ValidationScorecardTests/jointPositionCodable 2>&1 | tail -5`

Expected: Compile error — `JointPosition` does not conform to `Codable`.

**Step 3: Write minimal implementation**

In `golf-sync-swing/Models/PoseFrame.swift`, add `Codable` to `JointPosition`:

```swift
struct JointPosition: Sendable, Codable {
    let x: CGFloat
    let y: CGFloat
    let confidence: Float
}
```

**Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS.

**Step 5: Commit**

```bash
git add golf-sync-swing/Models/PoseFrame.swift golf-sync-swingTests/ValidationScorecardTests.swift
git commit -m "feat(validation): add Codable to JointPosition, create ValidationScorecardTests"
```

---

## Task 2: Create SerializablePoseFrame for JSON snapshots

PoseFrame itself uses `VNHumanBodyPoseObservation.JointName` as dictionary keys (not string-codable) and holds a non-codable `VNHumanBodyPoseObservation?`. We need a serialization wrapper.

**Files:**
- Modify: `golf-sync-swingTests/ValidationScorecardTests.swift`

**Step 1: Write the failing test**

Add to `ValidationScorecardTests.swift`:

```swift
@Test("PoseFrame round-trips through SerializablePoseFrame")
func poseFrameRoundTrip() throws {
    let wrist = PoseFrame.JointPosition(x: 0.42, y: 0.31, confidence: 0.92)
    let hip = PoseFrame.JointPosition(x: 0.50, y: 0.55, confidence: 0.90)
    let original = PoseFrame(
        timestamp: 2.967,
        joints: [.leftWrist: wrist, .leftHip: hip]
    )

    let serializable = SerializablePoseFrame(original)
    let data = try JSONEncoder().encode(serializable)
    let decoded = try JSONDecoder().decode(SerializablePoseFrame.self, from: data)
    let restored = decoded.toPoseFrame()

    #expect(restored.timestamp == original.timestamp)
    #expect(restored.joint(.leftWrist)?.x == wrist.x)
    #expect(restored.joint(.leftWrist)?.y == wrist.y)
    #expect(restored.joint(.leftHip)?.confidence == hip.confidence)
    #expect(restored.observation == nil) // observation is not serialized
}
```

**Step 2: Run test to verify it fails**

Expected: Compile error — `SerializablePoseFrame` not found.

**Step 3: Write minimal implementation**

Add to `ValidationScorecardTests.swift` (private to test target for now):

```swift
// MARK: - Serialization Bridge

struct SerializablePoseFrame: Codable {
    let timestamp: TimeInterval
    let joints: [String: PoseFrame.JointPosition]

    init(_ frame: PoseFrame) {
        self.timestamp = frame.timestamp
        self.joints = Dictionary(
            uniqueKeysWithValues: frame.joints.map { (key, value) in
                (key.rawValue.rawValue, value)
            }
        )
    }

    func toPoseFrame() -> PoseFrame {
        let visionJoints = Dictionary(
            uniqueKeysWithValues: joints.compactMap { (key, value) -> (VNHumanBodyPoseObservation.JointName, PoseFrame.JointPosition)? in
                let jointName = VNHumanBodyPoseObservation.JointName(rawValue: VNRecognizedPointKey(rawValue: key))
                return (jointName, value)
            }
        )
        return PoseFrame(timestamp: timestamp, joints: visionJoints)
    }
}
```

**Note:** `VNHumanBodyPoseObservation.JointName` wraps `VNRecognizedPointKey` which wraps a `String`. The double `.rawValue.rawValue` extracts the underlying string. Verify this compiles — if the API differs, adjust to use `VNRecognizedPointKey(rawValue:)` directly.

**Step 4: Run test to verify it passes**

Expected: PASS.

**Step 5: Commit**

```bash
git add golf-sync-swingTests/ValidationScorecardTests.swift
git commit -m "feat(validation): add SerializablePoseFrame for JSON round-trip"
```

---

## Task 3: Add snapshot exporter to GolfDBValidationTests

This device-only test extracts pose frames from each GolfDB video and writes them as JSON snapshot files to a temporary directory. You then copy them into the test bundle.

**Files:**
- Modify: `golf-sync-swingTests/GolfDBValidationTests.swift`

**Step 1: Write the exporter test**

Add to `GolfDBValidationTests.swift`:

```swift
@Test("Export pose snapshots to JSON (run on device, copy output to TestData/snapshots/)",
      .tags(.golfdb),
      .enabled(if: GolfDBValidationTests.isPhysicalDevice, "Requires physical device"))
func exportPoseSnapshots() throws {
    let outputDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("pose_snapshots", isDirectory: true)
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    for gt in Self.testVideos {
        guard let url = Bundle(for: BundleToken.self).url(
            forResource: gt.filename,
            withExtension: "mp4"
        ) else {
            Issue.record("Missing video: \(gt.filename).mp4")
            continue
        }

        let frames = try extractPoseFrames(from: url, bbox: gt.bbox, sampleRate: 15)
        let serializable = frames.map { SerializablePoseFrame($0) }
        let data = try encoder.encode(serializable)

        let snapshotName = gt.filename.replacingOccurrences(of: "golfdb_", with: "")
        let outputFile = outputDir.appendingPathComponent("\(snapshotName).json")
        try data.write(to: outputFile)

        let framesWithWrist = frames.filter { $0.leftWrist != nil || $0.rightWrist != nil }.count
        print("Exported \(gt.player): \(frames.count) frames (\(framesWithWrist) with wrist) → \(outputFile.path)")
    }

    print("\n📁 Snapshots written to: \(outputDir.path)")
    print("Copy to: golf-sync-swingTests/TestData/snapshots/")
}
```

**Step 2: Verify it compiles on simulator**

Run build (not test — this test is device-only):
`xcodebuild build-for-testing -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED.

**Step 3: Commit**

```bash
git add golf-sync-swingTests/GolfDBValidationTests.swift
git commit -m "feat(validation): add snapshot exporter for GolfDB pose data"
```

**Step 4: Run on device to generate snapshots**

Run: `xcodebuild test -destination 'id=00008130-001835DC0CF8001C' -only-testing:golf-sync-swingTests/GolfDBValidationTests/exportPoseSnapshots`

Copy the output JSON files from the printed path into `golf-sync-swingTests/TestData/snapshots/`.

---

## Task 4: Create the manifest

**Files:**
- Create: `golf-sync-swingTests/TestData/snapshots/manifest.json`

**Step 1: Write the manifest**

```json
[
  {
    "file": "f1BWA5F87Jc.json",
    "type": "swing",
    "impactTime": 3.900,
    "player": "Sandra Gal",
    "club": "driver",
    "angle": "down-the-line"
  },
  {
    "file": "iW323nsTGtU.json",
    "type": "swing",
    "impactTime": 3.567,
    "player": "Hyo Joo Kim",
    "club": "driver",
    "angle": "face-on"
  },
  {
    "file": "4HzLO88ryCU.json",
    "type": "swing",
    "impactTime": 2.967,
    "player": "Tiger Woods",
    "club": "iron",
    "angle": "down-the-line"
  },
  {
    "file": "KR9Umr1GM-U.json",
    "type": "swing",
    "impactTime": 2.600,
    "player": "Rory McIlroy",
    "club": "iron",
    "angle": "other"
  },
  {
    "file": "tpv8QUM0G0E.json",
    "type": "swing",
    "impactTime": 2.767,
    "player": "Paula Creamer",
    "club": "driver",
    "angle": "other"
  }
]
```

**Step 2: Commit**

```bash
mkdir -p golf-sync-swingTests/TestData/snapshots
git add golf-sync-swingTests/TestData/snapshots/manifest.json
git commit -m "feat(validation): add ground truth manifest for pose snapshots"
```

---

## Task 5: Build the scorecard test

The core of the validation harness. Loads snapshots, runs detection, writes a JSON scorecard.

**Files:**
- Modify: `golf-sync-swingTests/ValidationScorecardTests.swift`

**Step 1: Add manifest model and snapshot loader**

Add to `ValidationScorecardTests.swift`:

```swift
// MARK: - Manifest Model

private struct ManifestEntry: Codable {
    let file: String
    let type: String         // "swing" or "no_swing"
    let impactTime: Double?  // nil for no_swing entries
    let player: String?
    let club: String?
    let angle: String?
    let label: String?       // description for no_swing entries
}

// MARK: - Scorecard Output

private struct Scorecard: Codable {
    let timestamp: String
    let thresholds: ThresholdSnapshot
    let summary: Summary
    let perVideo: [VideoResult]

    struct ThresholdSnapshot: Codable {
        let velocityThreshold: Double
        let minimumDescentFrames: Int
        let minimumDisplacement: Double
    }

    struct Summary: Codable {
        let totalVideos: Int
        let swingVideos: Int
        let noSwingVideos: Int
        let truePositives: Int
        let falseNegatives: Int
        let falsePositives: Int
        let meanImpactError: Double
        let maxImpactError: Double
        let precision: Double
        let recall: Double
    }

    struct VideoResult: Codable {
        let name: String
        let type: String
        let expectedImpact: Double?
        let detectedImpact: Double?
        let error: Double?
        let pass: Bool
    }
}

// MARK: - Snapshot Loading

private func loadSnapshots() throws -> [(entry: ManifestEntry, frames: [PoseFrame])] {
    let bundle = Bundle(for: BundleToken.self)
    guard let manifestURL = bundle.url(
        forResource: "manifest",
        withExtension: "json",
        subdirectory: "snapshots"
    ) else {
        return []
    }

    let manifestData = try Data(contentsOf: manifestURL)
    let entries = try JSONDecoder().decode([ManifestEntry].self, from: manifestData)

    return try entries.compactMap { entry in
        let snapshotName = entry.file.replacingOccurrences(of: ".json", with: "")
        guard let snapshotURL = bundle.url(
            forResource: snapshotName,
            withExtension: "json",
            subdirectory: "snapshots"
        ) else {
            return nil
        }

        let snapshotData = try Data(contentsOf: snapshotURL)
        let serialized = try JSONDecoder().decode([SerializablePoseFrame].self, from: snapshotData)
        let frames = serialized.map { $0.toPoseFrame() }
        return (entry, frames)
    }
}
```

**Step 2: Add the scorecard test method**

```swift
// MARK: - Success Criteria

private static let minimumPrecision: Double = 0.90
private static let minimumRecall: Double = 0.95
private static let maxImpactTolerance: Double = 1.0
private static let meanImpactTolerance: Double = 0.5

// MARK: - Scorecard Test

@Test("Validation scorecard: all snapshots against production detectors", .tags(.validation))
func validationScorecard() throws {
    let snapshots = try loadSnapshots()
    guard !snapshots.isEmpty else {
        Issue.record("No snapshots found. Run exportPoseSnapshots on device first.")
        return
    }

    let impactDetector = ImpactDetector()
    let heuristics = PoseHeuristics()
    var results: [Scorecard.VideoResult] = []

    for (entry, frames) in snapshots {
        let name = entry.player ?? entry.label ?? entry.file

        switch entry.type {
        case "swing":
            let detected = impactDetector.findImpactTime(in: frames)
            let heuristicsEvent = heuristics.analyze(frames: frames)
            let swingDetected: Bool = {
                if case .swingDetected = heuristicsEvent { return true }
                return false
            }()

            let error = detected.flatMap { d in entry.impactTime.map { abs(d - $0) } }
            let pass = swingDetected && detected != nil && (error ?? .greatestFiniteMagnitude) <= Self.maxImpactTolerance

            results.append(Scorecard.VideoResult(
                name: name,
                type: "swing",
                expectedImpact: entry.impactTime,
                detectedImpact: detected,
                error: error,
                pass: pass
            ))

        case "no_swing":
            let heuristicsEvent = heuristics.analyze(frames: frames)
            let falsePositive: Bool = {
                if case .swingDetected = heuristicsEvent { return true }
                return false
            }()

            results.append(Scorecard.VideoResult(
                name: name,
                type: "no_swing",
                expectedImpact: nil,
                detectedImpact: nil,
                error: nil,
                pass: !falsePositive
            ))

        default:
            Issue.record("Unknown type '\(entry.type)' for \(name)")
        }
    }

    // Compute summary
    let swingResults = results.filter { $0.type == "swing" }
    let noSwingResults = results.filter { $0.type == "no_swing" }
    let tp = swingResults.filter { $0.pass }.count
    let fn = swingResults.filter { !$0.pass }.count
    let fp = noSwingResults.filter { !$0.pass }.count
    let errors = swingResults.compactMap(\.error)
    let meanError = errors.isEmpty ? 0 : errors.reduce(0, +) / Double(errors.count)
    let maxError = errors.max() ?? 0
    let precision = (tp + fp) > 0 ? Double(tp) / Double(tp + fp) : 1.0
    let recall = (tp + fn) > 0 ? Double(tp) / Double(tp + fn) : 1.0

    let scorecard = Scorecard(
        timestamp: ISO8601DateFormatter().string(from: Date()),
        thresholds: Scorecard.ThresholdSnapshot(
            velocityThreshold: 0.8,
            minimumDescentFrames: 2,
            minimumDisplacement: 0.08
        ),
        summary: Scorecard.Summary(
            totalVideos: results.count,
            swingVideos: swingResults.count,
            noSwingVideos: noSwingResults.count,
            truePositives: tp,
            falseNegatives: fn,
            falsePositives: fp,
            meanImpactError: meanError,
            maxImpactError: maxError,
            precision: precision,
            recall: recall
        ),
        perVideo: results
    )

    // Write scorecard JSON
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let scorecardData = try encoder.encode(scorecard)
    let scorecardPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("validation_scorecard.json")
    try scorecardData.write(to: scorecardPath)

    // Print for Claude to read
    let scorecardString = String(data: scorecardData, encoding: .utf8) ?? "{}"
    print("\n=== VALIDATION SCORECARD ===")
    print(scorecardString)
    print("=== END SCORECARD ===")
    print("Scorecard written to: \(scorecardPath.path)")

    // Assert success criteria
    #expect(precision >= Self.minimumPrecision,
        "Precision \(String(format: "%.2f", precision)) below minimum \(Self.minimumPrecision)")
    #expect(recall >= Self.minimumRecall,
        "Recall \(String(format: "%.2f", recall)) below minimum \(Self.minimumRecall)")
    #expect(maxError <= Self.maxImpactTolerance,
        "Max impact error \(String(format: "%.3f", maxError))s exceeds tolerance \(Self.maxImpactTolerance)s")
    #expect(meanError <= Self.meanImpactTolerance,
        "Mean impact error \(String(format: "%.3f", meanError))s exceeds tolerance \(Self.meanImpactTolerance)s")

    // Per-video assertions for regression detection
    for result in results {
        #expect(result.pass, "\(result.name) [\(result.type)] FAILED: detected=\(result.detectedImpact.map { String(format: "%.3f", $0) } ?? "nil"), expected=\(result.expectedImpact.map { String(format: "%.3f", $0) } ?? "n/a"), error=\(result.error.map { String(format: "%.3f", $0) } ?? "n/a")")
    }
}
```

**Step 3: Add validation tag**

Add near the existing `Tag` extension in `GolfDBValidationTests.swift`:

```swift
extension Tag {
    @Tag static var validation: Self
}
```

Or add it directly in `ValidationScorecardTests.swift` if tag extensions can't be duplicated.

**Step 4: Run test to verify it compiles (will skip if no snapshots yet)**

Run: `xcodebuild test -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:golf-sync-swingTests/ValidationScorecardTests 2>&1 | tail -10`

Expected: Tests pass (with "No snapshots found" record if snapshots aren't in bundle yet) or compile successfully.

**Step 5: Commit**

```bash
git add golf-sync-swingTests/ValidationScorecardTests.swift
git commit -m "feat(validation): add scorecard test with precision/recall/error metrics"
```

---

## Task 6: Generate snapshots on device and verify full loop

This is the manual step that bootstraps the system. After this, no device is needed for algorithm tuning.

**Step 1: Run exporter on device**

```bash
xcodebuild test -destination 'id=00008130-001835DC0CF8001C' \
  -only-testing:golf-sync-swingTests/GolfDBValidationTests/exportPoseSnapshots
```

**Step 2: Copy snapshot files**

Copy the 5 JSON files from the printed temp directory into `golf-sync-swingTests/TestData/snapshots/`.

**Step 3: Verify snapshots are in the test bundle**

Xcode auto-syncs files in the project directory. Build and run the scorecard test on simulator:

```bash
xcodebuild test -project golf-sync-swing.xcodeproj -scheme golf-sync-swing \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:golf-sync-swingTests/ValidationScorecardTests/validationScorecard 2>&1 | tail -20
```

Expected: Full scorecard output with 5/5 swing videos passing. All assertions pass.

**Step 4: Commit snapshots**

```bash
git add golf-sync-swingTests/TestData/snapshots/
git commit -m "feat(validation): add GolfDB pose snapshots (5 videos)"
```

---

## Task 7: Add non-swing synthetic snapshots for false-positive testing

Until real non-swing recordings are available, create synthetic snapshots: standing still, slow arm movement, walking patterns.

**Files:**
- Modify: `golf-sync-swingTests/ValidationScorecardTests.swift`
- Modify: `golf-sync-swingTests/TestData/snapshots/manifest.json`

**Step 1: Write a test that generates synthetic no-swing snapshots**

Add to `ValidationScorecardTests.swift`:

```swift
@Test("Synthetic non-swing snapshots are not detected as swings", .tags(.validation))
func syntheticNonSwingSnapshots() throws {
    let heuristics = PoseHeuristics()

    // Standing still: wrist stays in same position for 3 seconds
    let standingFrames = (0..<90).map { i -> PoseFrame in
        let wrist = PoseFrame.JointPosition(x: 0.45, y: 0.40, confidence: 0.85)
        let hip = PoseFrame.JointPosition(x: 0.50, y: 0.55, confidence: 0.90)
        return PoseFrame(
            timestamp: Double(i) / 30.0,
            joints: [.leftWrist: wrist, .rightWrist: wrist, .leftHip: hip, .rightHip: hip]
        )
    }
    let standingResult = heuristics.analyze(frames: Array(standingFrames.suffix(15)))
    if case .swingDetected = standingResult {
        Issue.record("Standing still should not trigger swing detection")
    }

    // Slow arm raise: wrist moves up gradually over 3 seconds
    let slowRaiseFrames = (0..<90).map { i -> PoseFrame in
        let y = 0.40 + CGFloat(i) * 0.003  // very slow upward movement
        let wrist = PoseFrame.JointPosition(x: 0.45, y: y, confidence: 0.85)
        let hip = PoseFrame.JointPosition(x: 0.50, y: 0.55, confidence: 0.90)
        return PoseFrame(
            timestamp: Double(i) / 30.0,
            joints: [.leftWrist: wrist, .leftHip: hip, .rightHip: hip]
        )
    }
    let raiseResult = heuristics.analyze(frames: Array(slowRaiseFrames.suffix(15)))
    if case .swingDetected = raiseResult {
        Issue.record("Slow arm raise should not trigger swing detection")
    }

    // Small fidget: wrist oscillates in small range
    let fidgetFrames = (0..<90).map { i -> PoseFrame in
        let y = 0.45 + sin(Double(i) * 0.5) * 0.03
        let wrist = PoseFrame.JointPosition(x: 0.45, y: CGFloat(y), confidence: 0.85)
        let hip = PoseFrame.JointPosition(x: 0.50, y: 0.55, confidence: 0.90)
        return PoseFrame(
            timestamp: Double(i) / 30.0,
            joints: [.leftWrist: wrist, .leftHip: hip, .rightHip: hip]
        )
    }
    let fidgetResult = heuristics.analyze(frames: Array(fidgetFrames.suffix(15)))
    if case .swingDetected = fidgetResult {
        Issue.record("Small fidgeting should not trigger swing detection")
    }
}
```

**Step 2: Run test to verify passes**

Expected: PASS — none of the synthetic scenarios should trigger detection.

**Step 3: Save synthetic snapshots as JSON files for the scorecard**

Write a helper test that serializes these to JSON and add entries to the manifest:

Add to `manifest.json`:
```json
  {
    "file": "synthetic_standing.json",
    "type": "no_swing",
    "label": "Standing still"
  },
  {
    "file": "synthetic_slow_raise.json",
    "type": "no_swing",
    "label": "Slow arm raise"
  },
  {
    "file": "synthetic_fidget.json",
    "type": "no_swing",
    "label": "Small fidgeting"
  }
```

Generate the snapshot JSONs programmatically using `SerializablePoseFrame` and write them to `TestData/snapshots/`.

**Step 4: Run full scorecard**

```bash
xcodebuild test -project golf-sync-swing.xcodeproj -scheme golf-sync-swing \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:golf-sync-swingTests/ValidationScorecardTests 2>&1 | tail -20
```

Expected: 8 total videos (5 swing + 3 no_swing), all passing. Precision 1.0, recall 1.0.

**Step 5: Commit**

```bash
git add golf-sync-swingTests/
git commit -m "feat(validation): add synthetic non-swing snapshots for FP testing"
```

---

## Task 8: Verify the agentic loop works end-to-end

This is a dry run of the Claude feedback loop. Intentionally break a threshold, run the scorecard, verify it catches the regression, fix it, verify recovery.

**Step 1: Temporarily set velocityThreshold to 10.0**

Edit `PoseHeuristics.swift`: change `velocityThreshold: CGFloat = 0.8` to `10.0`.

**Step 2: Run scorecard test**

```bash
xcodebuild test -project golf-sync-swing.xcodeproj -scheme golf-sync-swing \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:golf-sync-swingTests/ValidationScorecardTests/validationScorecard 2>&1 | grep -E '(SCORECARD|FAIL|pass|error|recall|precision)'
```

Expected: TEST FAILED — swing videos fail (recall drops to 0), scorecard shows falseNegatives = 5.

**Step 3: Revert to 0.8**

**Step 4: Run scorecard test again**

Expected: TEST SUCCEEDED — all pass, scorecard shows recall = 1.0.

**Step 5: Commit (nothing changed, this was a dry run)**

No commit needed. The loop works.

---

## Summary

After all 8 tasks, you have:

| What | Where | Runs on |
|------|-------|---------|
| `SerializablePoseFrame` | `ValidationScorecardTests.swift` | Everywhere |
| Snapshot exporter | `GolfDBValidationTests.swift` | Device only (one-time) |
| Ground truth manifest | `TestData/snapshots/manifest.json` | Everywhere |
| 5 swing snapshots | `TestData/snapshots/*.json` | Everywhere |
| 3 synthetic non-swing snapshots | `TestData/snapshots/synthetic_*.json` | Everywhere |
| Scorecard test | `ValidationScorecardTests.swift` | **Simulator** |
| JSON scorecard output | `/tmp/validation_scorecard.json` | Machine-readable |

**The agentic loop:**
```
Claude edits PoseHeuristics.swift or ImpactDetector.swift
  → runs: xcodebuild test ... -only-testing:ValidationScorecardTests/validationScorecard
  → reads scorecard JSON from test output
  → sees which videos regressed and by how much
  → adjusts and repeats
```
