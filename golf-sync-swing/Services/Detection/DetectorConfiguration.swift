//
//  DetectorConfiguration.swift
//  golf-sync-swing
//
//  Value object encapsulating all model-specific parameters.
//  Strategies and detectors read labels and thresholds from this object,
//  eliminating conditional checks on the model variant.
//

import Foundation

struct DetectorConfiguration {

    let variant: ModelVariant
    let modelFileName: String
    let predictionWindow: Int
    let idleStride: Int
    let activeStride: Int

    let backswingLabel: String
    let noSwingLabel: String
    let swingLabels: [String]

    let downswingLabels: [String]
    let followThroughLabels: [String]

    let primaryDownswingLabel: String
    let primaryFollowLabel: String

    let thresholds: Thresholds

    // MARK: - Per-Variant Thresholds

    struct Thresholds {
        // DownswingToFollowThroughStrategy
        let primaryDownswing: Double
        let primaryFollow: Double
        let aggregateDownswing: Double
        let minSwingConfidence: Double

        // BackswingToFollowThroughStrategy
        let backswing: Double
        let followThrough: Double

        // DownswingDecayStrategy
        let downswingDecay: Double
        let minPeakDownswing: Double

        // BackswingDecayStrategy
        let minBackswingProb: Double

        // No-swing dominance pre-filter (ActionClassifierDetector)
        let noSwingDominanceRatio: Double
    }

    // MARK: - Factory

    private static let registry: [ModelVariant: DetectorConfiguration] = [
        .fourClass: fourClassConfiguration,
        .fourClassV2: fourClassV2Configuration,
        .fiveClass: fiveClassConfiguration,
        .sixClass: sixClassConfiguration,
    ]

    static func configuration(for variant: ModelVariant) -> DetectorConfiguration {
        guard let config = registry[variant] else {
            fatalError("DetectorConfiguration: no configuration registered for \(variant)")
        }
        return config
    }

    // MARK: - Variant Configurations

    private static let fourClassConfiguration = DetectorConfiguration(
        variant: .fourClass,
        modelFileName: ModelVariant.fourClass.modelFileName,
        predictionWindow: 60,
        idleStride: 8,
        activeStride: 2,
        backswingLabel: "backswing",
        noSwingLabel: "no_swing",
        swingLabels: ["backswing", "downswing", "follow_through"],
        downswingLabels: ["downswing"],
        followThroughLabels: ["follow_through"],
        primaryDownswingLabel: "downswing",
        primaryFollowLabel: "follow_through",
        thresholds: Thresholds(
            primaryDownswing: 0.10, primaryFollow: 0.10,
            aggregateDownswing: 0.15, minSwingConfidence: 0.12,
            backswing: 0.15, followThrough: 0.10,
            downswingDecay: 0.10, minPeakDownswing: 0.15,
            minBackswingProb: 0.20, noSwingDominanceRatio: 0.95
        )
    )

    /// 4-class v2: retrained 60-frame model (GolfSwingClassifier_v3).
    /// Same 4 labels as original, but with updated training data.
    /// Thresholds tuned between original 4-class and 5-class starting points.
    private static let fourClassV2Configuration = DetectorConfiguration(
        variant: .fourClassV2,
        modelFileName: ModelVariant.fourClassV2.modelFileName,
        predictionWindow: 60,
        idleStride: 8,
        activeStride: 2,
        backswingLabel: "backswing",
        noSwingLabel: "no_swing",
        swingLabels: ["backswing", "downswing", "follow_through"],
        downswingLabels: ["downswing"],
        followThroughLabels: ["follow_through"],
        primaryDownswingLabel: "downswing",
        primaryFollowLabel: "follow_through",
        thresholds: Thresholds(
            primaryDownswing: 0.12, primaryFollow: 0.12,
            aggregateDownswing: 0.18, minSwingConfidence: 0.15,
            backswing: 0.18, followThrough: 0.12,
            downswingDecay: 0.12, minPeakDownswing: 0.18,
            minBackswingProb: 0.25, noSwingDominanceRatio: 0.95
        )
    )

    /// 5-class: 18-frame windows produce noisier predictions.
    /// Thresholds lowered to 0.10-0.15 range — action classifiers
    /// rarely output clean probability peaks above 0.25.
    /// Note: predictionWindow MUST match the model's compiled input shape (18 frames).
    private static let fiveClassConfiguration = DetectorConfiguration(
        variant: .fiveClass,
        modelFileName: ModelVariant.fiveClass.modelFileName,
        predictionWindow: 18,
        idleStride: 8,
        activeStride: 2,
        backswingLabel: "backswing",
        noSwingLabel: "no_swing",
        swingLabels: ["backswing", "downswing", "impact", "follow_through"],
        downswingLabels: ["downswing"],
        followThroughLabels: ["follow_through"],
        primaryDownswingLabel: "downswing",
        primaryFollowLabel: "follow_through",
        thresholds: Thresholds(
            primaryDownswing: 0.15, primaryFollow: 0.15,
            aggregateDownswing: 0.20, minSwingConfidence: 0.18,
            backswing: 0.20, followThrough: 0.15,
            downswingDecay: 0.15, minPeakDownswing: 0.20,
            minBackswingProb: 0.25, noSwingDominanceRatio: 0.95
        )
    )

    private static let sixClassConfiguration = DetectorConfiguration(
        variant: .sixClass,
        modelFileName: ModelVariant.sixClass.modelFileName,
        predictionWindow: 15,
        idleStride: 8,
        activeStride: 2,
        backswingLabel: "backswing",
        noSwingLabel: "noswing",
        swingLabels: ["backswing", "early_downswing", "late_downswing", "early_follow", "follow_through"],
        downswingLabels: ["early_downswing", "late_downswing"],
        followThroughLabels: ["early_follow", "follow_through"],
        primaryDownswingLabel: "late_downswing",
        primaryFollowLabel: "early_follow",
        thresholds: Thresholds(
            primaryDownswing: 0.10, primaryFollow: 0.10,
            aggregateDownswing: 0.15, minSwingConfidence: 0.12,
            backswing: 0.15, followThrough: 0.10,
            downswingDecay: 0.10, minPeakDownswing: 0.15,
            minBackswingProb: 0.20, noSwingDominanceRatio: 0.95
        )
    )
}
