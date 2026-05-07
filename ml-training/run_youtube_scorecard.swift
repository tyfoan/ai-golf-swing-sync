#!/usr/bin/env swift

//
//  run_youtube_scorecard.swift
//
//  Runs PoseHeuristics + ImpactDetector against 50 youtube-test snapshots.
//  Outputs a validation scorecard JSON to /tmp/youtube_scorecard.json.
//
//  Usage: swift run_youtube_scorecard.swift
//

import Foundation

// MARK: - Models (mirrors production types)

struct JointPosition: Codable {
    let x: CGFloat
    let y: CGFloat
    let confidence: Float
}

struct SerializablePoseFrame: Codable {
    let timestamp: TimeInterval
    let joints: [String: JointPosition]
}

struct ManifestEntry: Codable {
    let file: String
    let type: String
    let impactTime: Double?
    let player: String?
    let club: String?
    let angle: String?
}

// MARK: - Scorecard Output

struct Scorecard: Codable {
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
        let truePositives: Int
        let falseNegatives: Int
        let meanImpactError: Double
        let maxImpactError: Double
        let precision: Double
        let recall: Double
    }

    struct VideoResult: Codable {
        let name: String
        let player: String
        let club: String
        let angle: String
        let expectedImpact: Double
        let detectedImpact: Double?
        let error: Double?
        let pass: Bool
        let swingDetected: Bool
    }
}

// MARK: - PoseHeuristics (mirrors production)

let velocityThreshold: CGFloat = 0.5
let minimumDescentFrames: Int = 3
let minimumDisplacement: CGFloat = 0.08
let maxImpactTolerance: Double = 1.0

func analyzeSwing(frames: [(timestamp: TimeInterval, joints: [String: JointPosition])]) -> (detected: Bool, confidence: Double) {
    guard frames.count >= 10 else { return (false, 0) }

    let yValues = frames.compactMap { leadWristY(joints: $0.joints) }
    guard let maxY = yValues.max(), let minY = yValues.min(),
          (maxY - minY) >= minimumDisplacement else {
        return (false, 0)
    }

    let velocities = computeVelocities(frames: frames)
    let descentCount = velocities.filter { $0 < -velocityThreshold }.count  // 0.5 threshold

    guard descentCount >= minimumDescentFrames else { return (false, 0) }

    let confidence = min(1.0, Double(descentCount) / 8.0)
    return (true, confidence)
}

func findImpactTime(frames: [(timestamp: TimeInterval, joints: [String: JointPosition])]) -> Double? {
    guard frames.count >= 5 else { return nil }

    if let velocityFirst = velocityFirstImpact(frames: frames) {
        return velocityFirst
    }

    return naiveImpact(frames: frames)
}

let downswingVelocityThreshold: CGFloat = -0.5

func medianSmoothed(_ data: [(timestamp: TimeInterval, y: CGFloat)]) -> [(timestamp: TimeInterval, y: CGFloat)] {
    guard data.count >= 3 else { return data }
    var smoothed = [data[0]]
    for i in 1..<(data.count - 1) {
        let trio = [data[i-1].y, data[i].y, data[i+1].y].sorted()
        smoothed.append((data[i].timestamp, trio[1]))
    }
    smoothed.append(data[data.count - 1])
    return smoothed
}

func velocityFirstImpact(frames: [(timestamp: TimeInterval, joints: [String: JointPosition])]) -> Double? {
    let rawWristData = frames.compactMap { frame -> (timestamp: TimeInterval, y: CGFloat)? in
        guard let y = leadWristY(joints: frame.joints) else { return nil }
        return (frame.timestamp, y)
    }

    guard rawWristData.count >= 10 else { return nil }

    let wristData = medianSmoothed(rawWristData)

    let minY = wristData.map(\.y).min() ?? 0
    let maxY = wristData.map(\.y).max() ?? 0
    let yRange = maxY - minY
    guard yRange >= 0.05 else { return nil }

    // Compute all velocities
    var velocities: [(index: Int, timestamp: TimeInterval, velocity: CGFloat)] = []
    for i in 1..<wristData.count {
        let dt = wristData[i].timestamp - wristData[i-1].timestamp
        guard dt > 0 else { continue }
        let v = (wristData[i].y - wristData[i-1].y) / dt
        velocities.append((i, wristData[i].timestamp, v))
    }

    // Only count downswing after wrist has risen above 40% of range
    let riseThreshold = minY + yRange * 0.4
    var hasRisen = false

    let gatedDownswing = velocities.first(where: { entry in
        let prevY = wristData[entry.index - 1].y
        let currentY = wristData[entry.index].y
        if prevY >= riseThreshold { hasRisen = true }
        guard hasRisen && entry.velocity < downswingVelocityThreshold
                && currentY > minY + yRange * 0.15 else { return false }
        // Require next velocity to also be negative (filter single-frame noise)
        if let next = velocities.first(where: { $0.index == entry.index + 1 }) {
            return next.velocity < 0
        }
        return true
    })

    let firstDownswing = gatedDownswing ?? velocities.first(where: { $0.velocity < downswingVelocityThreshold })
    guard let downswing = firstDownswing else { return nil }

    // Find peak velocity near this burst
    let burstEnd = min(downswing.index + 8, wristData.count)
    let burstVelocities = velocities.filter {
        $0.index >= downswing.index && $0.index < burstEnd
    }
    guard let peakVel = burstVelocities.min(by: { $0.velocity < $1.velocity }) else {
        return nil
    }

    // Impact: Y-minimum in 6-frame window after peak velocity (use raw data for accuracy)
    let searchStart = peakVel.index
    let searchEnd = min(rawWristData.count, searchStart + 6)
    let window = rawWristData[searchStart..<searchEnd]
    return window.min(by: { $0.y < $1.y })?.timestamp
}

func naiveImpact(frames: [(timestamp: TimeInterval, joints: [String: JointPosition])]) -> Double? {
    let wristData = frames.compactMap { frame -> (timestamp: TimeInterval, y: CGFloat)? in
        guard let y = leadWristY(joints: frame.joints) else { return nil }
        return (frame.timestamp, y)
    }
    return wristData.min(by: { $0.y < $1.y })?.timestamp
}

func computeVelocities(frames: [(timestamp: TimeInterval, joints: [String: JointPosition])]) -> [CGFloat] {
    guard frames.count >= 2 else { return [] }
    return (1..<frames.count).map { i in
        let dt = frames[i].timestamp - frames[i-1].timestamp
        guard dt > 0 else { return 0 }
        let prevY = leadWristY(joints: frames[i-1].joints)
        let currY = leadWristY(joints: frames[i].joints)
        guard let py = prevY, let cy = currY else { return 0 }
        return (cy - py) / dt
    }
}

func leadWristY(joints: [String: JointPosition]) -> CGFloat? {
    let wristKeys = ["left_hand_joint", "right_hand_joint"]
    let wrists = wristKeys.compactMap { joints[$0] }.filter { $0.confidence > 0.3 }
    return wrists.map(\.y).min()
}

// MARK: - Main

func main() throws {
    let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let projectRoot = scriptDir.deletingLastPathComponent()
    let snapshotsDir = projectRoot.appendingPathComponent("golf-sync-swingTests/youtube-tests/snapshots")

    let manifestURL = snapshotsDir.appendingPathComponent("youtube_manifest.json")
    let manifestData = try Data(contentsOf: manifestURL)
    let entries = try JSONDecoder().decode([ManifestEntry].self, from: manifestData)

    print("Running scorecard on \(entries.count) videos...\n")

    var results: [Scorecard.VideoResult] = []
    let decoder = JSONDecoder()

    for entry in entries {
        let snapshotURL = snapshotsDir.appendingPathComponent(entry.file)
        guard let data = try? Data(contentsOf: snapshotURL) else {
            print("SKIP: \(entry.file) not found")
            continue
        }

        let serialized = try decoder.decode([SerializablePoseFrame].self, from: data)
        let frames = serialized.map { sf in
            (timestamp: sf.timestamp, joints: sf.joints)
        }

        let (swingDetected, _) = analyzeSwing(frames: frames)
        let detectedImpact = findImpactTime(frames: frames)

        let expected = entry.impactTime ?? 0
        let error = detectedImpact.map { abs($0 - expected) }
        let pass = swingDetected
            && detectedImpact != nil
            && (error ?? .greatestFiniteMagnitude) <= maxImpactTolerance

        let status = pass ? "PASS" : "FAIL"
        let errorStr = error.map { String(format: "%.3f", $0) } ?? "n/a"
        let swingStr = swingDetected ? "yes" : "NO"
        print("\(status) \(entry.player ?? "?") (\(entry.club ?? "?"), \(entry.angle ?? "?")) — "
            + "swing=\(swingStr), error=\(errorStr)s")

        results.append(Scorecard.VideoResult(
            name: entry.file,
            player: entry.player ?? "",
            club: entry.club ?? "",
            angle: entry.angle ?? "",
            expectedImpact: expected,
            detectedImpact: detectedImpact,
            error: error,
            pass: pass,
            swingDetected: swingDetected
        ))
    }

    // Build summary
    let passed = results.filter(\.pass)
    let failed = results.filter { !$0.pass }
    let errors = results.compactMap(\.error)
    let meanError = errors.isEmpty ? 0 : errors.reduce(0, +) / Double(errors.count)
    let maxError = errors.max() ?? 0
    let tp = results.filter(\.swingDetected).count
    let fn = results.filter { !$0.swingDetected }.count

    let scorecard = Scorecard(
        timestamp: ISO8601DateFormatter().string(from: Date()),
        thresholds: Scorecard.ThresholdSnapshot(
            velocityThreshold: Double(velocityThreshold),
            minimumDescentFrames: minimumDescentFrames,
            minimumDisplacement: Double(minimumDisplacement)
        ),
        summary: Scorecard.Summary(
            totalVideos: results.count,
            swingVideos: results.count,
            truePositives: tp,
            falseNegatives: fn,
            meanImpactError: meanError,
            maxImpactError: maxError,
            precision: 1.0,
            recall: tp > 0 ? Double(tp) / Double(tp + fn) : 0
        ),
        perVideo: results
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let output = try encoder.encode(scorecard)
    let outputURL = URL(fileURLWithPath: "/tmp/youtube_scorecard.json")
    try output.write(to: outputURL)

    print("\n" + String(repeating: "=", count: 60))
    print("RESULTS: \(passed.count)/\(results.count) passing")
    print("Recall: \(String(format: "%.2f", scorecard.summary.recall))")
    print("Mean error: \(String(format: "%.3f", meanError))s")
    print("Max error:  \(String(format: "%.3f", maxError))s")

    if !failed.isEmpty {
        print("\nFAILED:")
        for r in failed {
            let reason = r.swingDetected ? "error \(String(format: "%.3f", r.error ?? 0))s > 1.0s" : "swing not detected"
            print("  \(r.player) (\(r.club), \(r.angle)) — \(reason)")
        }
    }

    print("\nScorecard: \(outputURL.path)")
}

try main()
