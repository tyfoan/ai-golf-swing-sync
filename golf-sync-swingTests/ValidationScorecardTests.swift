//
//  ValidationScorecardTests.swift
//  golf-sync-swingTests
//
//  Golden-snapshot serialization support for PoseFrame data.
//  Validates detection algorithms against pre-recorded pose snapshots
//  and produces a machine-readable JSON scorecard.
//

import Testing
import Foundation
import Vision
@testable import golf_sync_swing

extension Tag {
    @Tag static var validation: Self
}

// MARK: - Manifest Entry

private struct ManifestEntry: Codable {
    let file: String
    let type: String
    let impactTime: Double?
    let player: String?
    let club: String?
    let angle: String?
    let label: String?
}

// MARK: - Scorecard Output Models

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

// MARK: - Loaded Snapshot

private struct LoadedSnapshot {
    let entry: ManifestEntry
    let frames: [PoseFrame]
}

// MARK: - Tests

struct ValidationScorecardTests {

    // MARK: - Success Criteria

    private static let minimumPrecision: Double = 0.90
    private static let minimumRecall: Double = 0.95
    private static let maxImpactTolerance: Double = 1.0
    private static let meanImpactTolerance: Double = 0.5

    // MARK: - Round-Trip Tests

    @Test("JointPosition round-trips through JSON", .tags(.validation))
    func jointPositionCodable() throws {
        let original = PoseFrame.JointPosition(x: 0.42, y: 0.87, confidence: 0.95)
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PoseFrame.JointPosition.self, from: data)

        #expect(decoded.x == original.x)
        #expect(decoded.y == original.y)
        #expect(decoded.confidence == original.confidence)
    }

    @Test("PoseFrame round-trips through SerializablePoseFrame JSON", .tags(.validation))
    func poseFrameRoundTrip() throws {
        let joints: [VNHumanBodyPoseObservation.JointName: PoseFrame.JointPosition] = [
            .leftWrist: PoseFrame.JointPosition(x: 0.3, y: 0.6, confidence: 0.9),
            .rightWrist: PoseFrame.JointPosition(x: 0.7, y: 0.4, confidence: 0.85),
            .neck: PoseFrame.JointPosition(x: 0.5, y: 0.8, confidence: 0.95),
            .leftHip: PoseFrame.JointPosition(x: 0.35, y: 0.45, confidence: 0.88),
            .rightHip: PoseFrame.JointPosition(x: 0.65, y: 0.44, confidence: 0.87)
        ]
        let original = PoseFrame(
            timestamp: 1.234,
            joints: joints,
            observation: nil
        )

        let serializable = SerializablePoseFrame(poseFrame: original)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(serializable)

        let decoder = JSONDecoder()
        let restored = try decoder.decode(SerializablePoseFrame.self, from: data)
        let roundTripped = restored.toPoseFrame()

        #expect(roundTripped.timestamp == original.timestamp)
        #expect(roundTripped.observation == nil)
        #expect(roundTripped.joints.count == original.joints.count)

        for (jointName, originalPosition) in original.joints {
            let restoredPosition = roundTripped.joints[jointName]
            #expect(restoredPosition != nil, "Missing joint: \(jointName.rawValue.rawValue)")
            #expect(restoredPosition?.x == originalPosition.x)
            #expect(restoredPosition?.y == originalPosition.y)
            #expect(restoredPosition?.confidence == originalPosition.confidence)
        }
    }

    // MARK: - Validation Scorecard

    @Test("Validation scorecard: detection accuracy across golden snapshots", .tags(.validation))
    func validationScorecard() throws {
        let snapshots = try loadAllSnapshots()

        guard !snapshots.isEmpty else {
            print("[ValidationScorecard] No snapshots found -- run exportPoseSnapshots on a physical device first. Skipping.")
            return
        }

        let impactDetector = ImpactDetector()
        let heuristics = PoseHeuristics()

        let videoResults = snapshots.map { snapshot in
            evaluateSnapshot(snapshot, impactDetector: impactDetector, heuristics: heuristics)
        }

        let scorecard = buildScorecard(from: videoResults, heuristics: heuristics)
        try emitScorecard(scorecard)
        assertSuccessCriteria(scorecard)
        assertAllVideosPass(videoResults)
    }

    // MARK: - Snapshot Evaluation

    private func evaluateSnapshot(
        _ snapshot: LoadedSnapshot,
        impactDetector: ImpactDetecting,
        heuristics: SwingDetecting
    ) -> Scorecard.VideoResult {
        let entry = snapshot.entry
        let frames = snapshot.frames

        switch entry.type {
        case "swing":
            return evaluateSwingSnapshot(entry: entry, frames: frames,
                                         impactDetector: impactDetector, heuristics: heuristics)
        default:
            return evaluateNoSwingSnapshot(entry: entry, frames: frames, heuristics: heuristics)
        }
    }

    private func evaluateSwingSnapshot(
        entry: ManifestEntry,
        frames: [PoseFrame],
        impactDetector: ImpactDetecting,
        heuristics: SwingDetecting
    ) -> Scorecard.VideoResult {
        let swingEvent = heuristics.analyze(frames: frames)
        let detectedImpact = impactDetector.findImpactTime(in: frames)
        let swingDetected = isSwingDetected(swingEvent)

        let error = computeImpactError(expected: entry.impactTime, detected: detectedImpact)
        let pass = swingDetected
            && detectedImpact != nil
            && (error ?? .greatestFiniteMagnitude) <= Self.maxImpactTolerance

        return Scorecard.VideoResult(
            name: entry.file,
            type: entry.type,
            expectedImpact: entry.impactTime,
            detectedImpact: detectedImpact,
            error: error,
            pass: pass
        )
    }

    private func evaluateNoSwingSnapshot(
        entry: ManifestEntry,
        frames: [PoseFrame],
        heuristics: SwingDetecting
    ) -> Scorecard.VideoResult {
        let swingEvent = heuristics.analyze(frames: frames)
        let pass = !isSwingDetected(swingEvent)

        return Scorecard.VideoResult(
            name: entry.file,
            type: entry.type,
            expectedImpact: nil,
            detectedImpact: nil,
            error: nil,
            pass: pass
        )
    }

    // MARK: - Scorecard Builder

    private func buildScorecard(
        from results: [Scorecard.VideoResult],
        heuristics: PoseHeuristics
    ) -> Scorecard {
        let swingResults = results.filter { $0.type == "swing" }
        let noSwingResults = results.filter { $0.type != "swing" }

        let truePositives = swingResults.filter(\.pass).count
        let falseNegatives = swingResults.count - truePositives
        let falsePositives = noSwingResults.filter { !$0.pass }.count

        let impactErrors = swingResults.compactMap(\.error)
        let meanError = impactErrors.isEmpty ? 0.0 : impactErrors.reduce(0, +) / Double(impactErrors.count)
        let maxError = impactErrors.max() ?? 0.0

        let precision = computePrecision(truePositives: truePositives, falsePositives: falsePositives)
        let recall = computeRecall(truePositives: truePositives, falseNegatives: falseNegatives)

        let summary = Scorecard.Summary(
            totalVideos: results.count,
            swingVideos: swingResults.count,
            noSwingVideos: noSwingResults.count,
            truePositives: truePositives,
            falseNegatives: falseNegatives,
            falsePositives: falsePositives,
            meanImpactError: meanError,
            maxImpactError: maxError,
            precision: precision,
            recall: recall
        )

        let thresholds = Scorecard.ThresholdSnapshot(
            velocityThreshold: 0.8,
            minimumDescentFrames: 2,
            minimumDisplacement: 0.08
        )

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())

        return Scorecard(
            timestamp: timestamp,
            thresholds: thresholds,
            summary: summary,
            perVideo: results
        )
    }

    // MARK: - Scorecard Emission

    private func emitScorecard(_ scorecard: Scorecard) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(scorecard)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        print("=== VALIDATION SCORECARD ===")
        print(json)
        print("=== END SCORECARD ===")

        let outputURL = URL(fileURLWithPath: "/tmp/validation_scorecard.json")
        try data.write(to: outputURL)
    }

    // MARK: - Assertions

    private func assertSuccessCriteria(_ scorecard: Scorecard) {
        let summary = scorecard.summary

        #expect(
            summary.precision >= Self.minimumPrecision,
            "Precision \(String(format: "%.2f", summary.precision)) below minimum \(Self.minimumPrecision)"
        )
        #expect(
            summary.recall >= Self.minimumRecall,
            "Recall \(String(format: "%.2f", summary.recall)) below minimum \(Self.minimumRecall)"
        )
        #expect(
            summary.maxImpactError <= Self.maxImpactTolerance,
            "Max impact error \(String(format: "%.3f", summary.maxImpactError))s exceeds tolerance \(Self.maxImpactTolerance)s"
        )
        #expect(
            summary.meanImpactError <= Self.meanImpactTolerance,
            "Mean impact error \(String(format: "%.3f", summary.meanImpactError))s exceeds tolerance \(Self.meanImpactTolerance)s"
        )
    }

    private func assertAllVideosPass(_ results: [Scorecard.VideoResult]) {
        for result in results {
            #expect(result.pass, "Regression: \(result.name) failed (type=\(result.type), error=\(result.error.map { String(format: "%.3f", $0) } ?? "n/a"))")
        }
    }

    // MARK: - Snapshot Loader

    private func loadAllSnapshots() throws -> [LoadedSnapshot] {
        let bundle = Bundle(for: ScorecardBundleToken.self)

        guard let manifestURL = bundle.url(
            forResource: "manifest", withExtension: "json", subdirectory: "snapshots"
        ) ?? bundle.url(forResource: "manifest", withExtension: "json") else {
            return []
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        let entries = try decoder.decode([ManifestEntry].self, from: manifestData)

        return entries.compactMap { entry in
            loadSnapshot(entry: entry, bundle: bundle, decoder: decoder)
        }
    }

    private func loadSnapshot(
        entry: ManifestEntry,
        bundle: Bundle,
        decoder: JSONDecoder
    ) -> LoadedSnapshot? {
        let resourceName = entry.file.replacingOccurrences(of: ".json", with: "")

        guard let snapshotURL = bundle.url(
            forResource: resourceName, withExtension: "json", subdirectory: "snapshots"
        ) ?? bundle.url(forResource: resourceName, withExtension: "json") else {
            return nil
        }

        guard let data = try? Data(contentsOf: snapshotURL),
              let serializedFrames = try? decoder.decode([SerializablePoseFrame].self, from: data) else {
            return nil
        }

        let frames = serializedFrames.map { $0.toPoseFrame() }
        return LoadedSnapshot(entry: entry, frames: frames)
    }

    // MARK: - Helpers

    private func isSwingDetected(_ event: SwingEvent) -> Bool {
        switch event {
        case .swingDetected:
            return true
        case .noSwing:
            return false
        }
    }

    private func computeImpactError(expected: Double?, detected: Double?) -> Double? {
        guard let expected, let detected else { return nil }
        return abs(detected - expected)
    }

    private func computePrecision(truePositives: Int, falsePositives: Int) -> Double {
        let denominator = truePositives + falsePositives
        guard denominator > 0 else { return 1.0 }
        return Double(truePositives) / Double(denominator)
    }

    private func computeRecall(truePositives: Int, falseNegatives: Int) -> Double {
        let denominator = truePositives + falseNegatives
        guard denominator > 0 else { return 1.0 }
        return Double(truePositives) / Double(denominator)
    }
}

// MARK: - Bundle Anchor

private final class ScorecardBundleToken {}

// MARK: - Serialization Bridge

struct SerializablePoseFrame: Codable {
    let timestamp: TimeInterval
    let joints: [String: PoseFrame.JointPosition]

    init(poseFrame: PoseFrame) {
        self.timestamp = poseFrame.timestamp
        self.joints = Dictionary(
            uniqueKeysWithValues: poseFrame.joints.map { jointName, position in
                (jointName.rawValue.rawValue, position)
            }
        )
    }

    func toPoseFrame() -> PoseFrame {
        let visionJoints = Dictionary(
            uniqueKeysWithValues: joints.map { key, position in
                let jointName = VNHumanBodyPoseObservation.JointName(
                    rawValue: VNRecognizedPointKey(rawValue: key)
                )
                return (jointName, position)
            }
        )
        return PoseFrame(
            timestamp: timestamp,
            joints: visionJoints,
            observation: nil
        )
    }
}
