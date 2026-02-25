//
//  SwingClassifier.swift
//  golf-sync-swing
//
//  Wrapper for the Create ML Action Classifier model.
//  Takes a sliding window of PoseFrames and classifies: swing / not_swing.
//
//  If the model is unavailable, returns .noSwing so the caller falls back to PoseHeuristics.
//

import CoreML
import Vision
import os

final class SwingClassifier: SwingDetecting, @unchecked Sendable {

    private let model: MLModel?
    private let windowSize: Int

    init(windowSize: Int = 15) {
        self.windowSize = windowSize
        self.model = Self.loadModel()
    }

    func analyze(frames: [PoseFrame]) -> SwingEvent {
        guard model != nil else {
            AppLogger.detection.debug("SwingClassifier: no model available, skipping")
            return .noSwing
        }

        guard frames.count >= windowSize else { return .noSwing }

        // TODO: Build MLMultiArray from pose data and run prediction
        // For now, delegate to heuristics until model is trained
        AppLogger.detection.debug("SwingClassifier: model loaded but prediction not yet implemented")
        return .noSwing
    }

    private static func loadModel() -> MLModel? {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        guard let url = Bundle.main.url(forResource: "GolfSwingClassifier", withExtension: "mlmodelc") else {
            AppLogger.detection.info("SwingClassifier: model not found in bundle (expected during development)")
            return nil
        }

        do {
            let model = try MLModel(contentsOf: url, configuration: config)
            AppLogger.detection.info("SwingClassifier: model loaded successfully")
            return model
        } catch {
            AppLogger.detection.error("SwingClassifier: failed to load model: \(error.localizedDescription)")
            return nil
        }
    }

    var isAvailable: Bool { model != nil }
}
