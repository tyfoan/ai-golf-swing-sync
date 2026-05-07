#!/usr/bin/env swift

//
//  diagnose_failures.swift
//
//  Analyzes failing videos to understand why detection/timing is off.
//  Prints wrist trajectory, velocities, and algorithm decisions.
//

import Foundation

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

// Failing videos from scorecard
let failures: [(id: String, reason: String)] = [
    ("qqF9qeNzqTA", "swing not detected — Lydia Ko wedge other"),
    ("04d08bM6-6U", "swing not detected — Eun-Hee Ji iron face-on"),
    ("7dI2HeBChks", "1.334s error — So Yeon Ryu iron other"),
    ("IVRbQrq2JHo", "1.566s error — Michelle Wie iron other"),
]

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let snapshotsDir = projectRoot.appendingPathComponent("golf-sync-swingTests/youtube-tests/snapshots")

let manifestURL = snapshotsDir.appendingPathComponent("youtube_manifest.json")
let manifestData = try Data(contentsOf: manifestURL)
let manifest = try JSONDecoder().decode([ManifestEntry].self, from: manifestData)
let manifestMap = Dictionary(uniqueKeysWithValues: manifest.map { ($0.file, $0) })

for (ytId, reason) in failures {
    let filename = "\(ytId).json"
    let url = snapshotsDir.appendingPathComponent(filename)
    guard let data = try? Data(contentsOf: url) else {
        print("SKIP: \(filename)")
        continue
    }

    let frames = try JSONDecoder().decode([SerializablePoseFrame].self, from: data)
    let entry = manifestMap[filename]
    let expectedImpact = entry?.impactTime ?? 0

    print("\n" + String(repeating: "=", count: 70))
    print("\(reason)")
    print("Expected impact: \(String(format: "%.3f", expectedImpact))s")
    print("Frames: \(frames.count), duration: \(String(format: "%.1f", frames.last?.timestamp ?? 0))s")

    // Wrist Y values
    let wristData = frames.compactMap { frame -> (t: Double, y: CGFloat)? in
        let wrists = ["left_hand_joint", "right_hand_joint"]
            .compactMap { frame.joints[$0] }
            .filter { $0.confidence > 0.3 }
        guard let minY = wrists.map(\.y).min() else { return nil }
        return (frame.timestamp, minY)
    }

    print("Frames with wrist data: \(wristData.count)")

    // Displacement
    let yValues = wristData.map(\.y)
    let maxY = yValues.max() ?? 0
    let minY = yValues.min() ?? 0
    let displacement = maxY - minY
    print("Displacement: \(String(format: "%.4f", displacement)) (threshold: 0.08)")

    // Velocities
    var velocities: [(t: Double, v: CGFloat)] = []
    for i in 1..<wristData.count {
        let dt = wristData[i].t - wristData[i-1].t
        guard dt > 0 else { continue }
        let v = (wristData[i].y - wristData[i-1].y) / dt
        velocities.append((wristData[i].t, v))
    }

    let descentVels = velocities.filter { $0.v < -0.8 }
    print("Descent frames (v < -0.8): \(descentVels.count)")
    if !descentVels.isEmpty {
        print("  at times: \(descentVels.map { String(format: "%.2f", $0.t) }.joined(separator: ", "))s")
    }

    // Two-phase analysis
    guard wristData.count >= 5 else {
        print("Too few wrist frames for two-phase")
        continue
    }

    let searchEnd = Int(Double(wristData.count) * 0.7)
    let topIdx = wristData[0..<searchEnd].enumerated().max(by: { $0.element.y < $1.element.y })!
    print("\nBackswing top: t=\(String(format: "%.2f", topIdx.element.t))s, y=\(String(format: "%.4f", topIdx.element.y))")

    // Post-top velocities
    let postTop = Array(wristData[topIdx.offset...])
    var postVels: [(idx: Int, t: Double, v: CGFloat)] = []
    for i in 1..<postTop.count {
        let dt = postTop[i].t - postTop[i-1].t
        guard dt > 0 else { continue }
        let v = (postTop[i].y - postTop[i-1].y) / dt
        postVels.append((i, postTop[i].t, v))
    }

    if let peakVel = postVels.min(by: { $0.v < $1.v }) {
        print("Peak downward velocity: v=\(String(format: "%.3f", peakVel.v)) at t=\(String(format: "%.2f", peakVel.t))s")

        // Y-min in 6-frame window after peak
        let windowEnd = min(peakVel.idx + 6, postTop.count)
        let window = postTop[peakVel.idx..<windowEnd]
        if let yMin = window.min(by: { $0.y < $1.y }) {
            print("Two-phase impact: t=\(String(format: "%.3f", yMin.t))s (y=\(String(format: "%.4f", yMin.y)))")
            print("Error vs ground truth: \(String(format: "%.3f", abs(yMin.t - expectedImpact)))s")
        }
    }

    // Naive fallback
    if let naiveMin = wristData.min(by: { $0.y < $1.y }) {
        print("Naive Y-min: t=\(String(format: "%.3f", naiveMin.t))s (y=\(String(format: "%.4f", naiveMin.y)))")
        print("Naive error: \(String(format: "%.3f", abs(naiveMin.t - expectedImpact)))s")
    }

    // Show wrist trajectory around expected impact
    print("\nWrist Y around expected impact (\(String(format: "%.2f", expectedImpact))s):")
    let nearby = wristData.filter { abs($0.t - expectedImpact) <= 1.0 }
    for d in nearby {
        let marker = abs(d.t - expectedImpact) < 0.1 ? " <-- EXPECTED" : ""
        let vel = velocities.first { abs($0.t - d.t) < 0.01 }?.v
        let velStr = vel.map { String(format: "%+.3f", $0) } ?? "  n/a"
        print("  t=\(String(format: "%.2f", d.t))s  y=\(String(format: "%.4f", d.y))  v=\(velStr)\(marker)")
    }
}
