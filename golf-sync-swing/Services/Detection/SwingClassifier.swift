//
//  SwingClassifier.swift
//  golf-sync-swing
//
//  Wrapper for the Create ML Action Classifier model.
//  Takes a sliding window of PoseFrames and classifies: swing / not_swing.
//
//  The model expects keypointsMultiArray() from VNHumanBodyPoseObservation,
//  concatenated along axis 0 for the full prediction window.
//
//  If the model is unavailable, returns .noSwing so the caller falls back to PoseHeuristics.
//

import CoreML
import Vision
import os

final class SwingClassifier: SwingDetecting, @unchecked Sendable {

    private let model: MLModel?
    private let windowSize: Int
    private let swingConfidenceThreshold: Double

    init(windowSize: Int = 15, swingConfidenceThreshold: Double = 0.85) {
        self.windowSize = windowSize
        self.swingConfidenceThreshold = swingConfidenceThreshold
        self.model = Self.loadModel()
    }

    func analyze(frames: [PoseFrame]) -> SwingEvent {
        guard let model else { return .noSwing }
        guard frames.count >= windowSize else { return .noSwing }

        let window = Array(frames.suffix(windowSize))
        let prediction = predict(model: model, frames: window)

        guard let prediction else { return .noSwing }

        let isSwing = prediction.label == "swing" && prediction.confidence >= swingConfidenceThreshold

        guard isSwing else { return .noSwing }

        let timestamp = window[windowSize / 2].timestamp
        AppLogger.detection.info(
            "SwingClassifier: swing (conf=\(String(format: "%.2f", prediction.confidence)))"
        )
        return .swingDetected(confidence: prediction.confidence, timestamp: timestamp)
    }

    var isAvailable: Bool { model != nil }

    // MARK: - Prediction

    private func predict(
        model: MLModel,
        frames: [PoseFrame]
    ) -> ClassifierPrediction? {
        let multiArrays = frames.map { frame -> MLMultiArray in
            keypointsArray(from: frame)
        }

        guard let concatenated = concatenateArrays(multiArrays) else { return nil }

        return runInference(model: model, poses: concatenated)
    }

    private func keypointsArray(from frame: PoseFrame) -> MLMultiArray {
        if let observation = frame.observation,
           let keypoints = try? observation.keypointsMultiArray() {
            return keypoints
        }
        return zeroPaddedArray()
    }

    private func zeroPaddedArray() -> MLMultiArray {
        let array = try? MLMultiArray(shape: [1, 3, 18], dataType: .float32)
        return array ?? MLMultiArray()
    }

    private func concatenateArrays(_ arrays: [MLMultiArray]) -> MLMultiArray? {
        guard !arrays.isEmpty else { return nil }
        return MLMultiArray(concatenating: arrays, axis: 0, dataType: .float32)
    }

    private func runInference(
        model: MLModel,
        poses: MLMultiArray
    ) -> ClassifierPrediction? {
        do {
            let input = try MLDictionaryFeatureProvider(dictionary: ["poses": poses])
            let output = try model.prediction(from: input)

            guard let label = output.featureValue(for: "label")?.stringValue,
                  let probs = output.featureValue(for: "labelProbabilities")?.dictionaryValue
                      as? [String: Double] else {
                return nil
            }

            let confidence = probs[label] ?? 0
            return ClassifierPrediction(label: label, confidence: confidence)
        } catch {
            AppLogger.detection.error("SwingClassifier prediction failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Model Loading

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
}

// MARK: - Types

private struct ClassifierPrediction {
    let label: String
    let confidence: Double
}
