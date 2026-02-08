//
//  PhaseClassifier.swift
//  golf-sync-swing
//
//  Wraps the CoreML GolfSwingClassifier model for 4-class swing phase prediction.
//  Input: sliding window of pose keypoints -> Output: phase label + probabilities.
//

import CoreML
import Foundation
import os

struct PredictionRecord {
    let timestamp: TimeInterval      // Timestamp of LAST frame in the window
    let windowStart: TimeInterval    // Timestamp of FIRST frame in the window
    let label: String
    let probabilities: [String: Double]
}

protocol PhaseClassifying: Sendable {
    func classify(frames: [PoseFrame], predictionWindow: Int) -> PredictionRecord?
}

final class PhaseClassifier: PhaseClassifying, @unchecked Sendable {

    private var model: MLModel?
    private(set) var isLoaded: Bool = false

    init() {
        loadModel()
    }

    private func loadModel() {
        let config = MLModelConfiguration()
        config.computeUnits = .all

        let modelNames = ["GolfSwingClassifier_v3", "GolfSwingClassifier_v2", "GolfSwingClassifier"]
        for name in modelNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                do {
                    model = try MLModel(contentsOf: url, configuration: config)
                    isLoaded = true
                    AppLogger.detection.info("PhaseClassifier: loaded \(name)")
                    return
                } catch {
                    AppLogger.detection.error("PhaseClassifier: failed to load \(name): \(error.localizedDescription)")
                }
            }
        }

        AppLogger.detection.error("PhaseClassifier: no Action Classifier model found in bundle")
    }

    func classify(frames: [PoseFrame], predictionWindow: Int) -> PredictionRecord? {
        guard isLoaded, let model, frames.count == predictionWindow else { return nil }

        guard let inputArray = buildInput(from: frames, predictionWindow: predictionWindow) else {
            return nil
        }

        do {
            let inputFeatures = try MLDictionaryFeatureProvider(
                dictionary: ["poses": MLFeatureValue(multiArray: inputArray)]
            )
            let prediction = try model.prediction(from: inputFeatures)
            return parsePrediction(prediction, frames: frames)
        } catch {
            return nil
        }
    }

    // MARK: - Private

    private func buildInput(from frames: [PoseFrame], predictionWindow: Int) -> MLMultiArray? {
        let firstShape = frames[0].keypointsArray.shape
        let numComponents: Int
        let numJoints: Int

        if firstShape.count == 3 {
            numComponents = firstShape[1].intValue
            numJoints = firstShape[2].intValue
        } else if firstShape.count == 2 {
            numComponents = firstShape[0].intValue
            numJoints = firstShape[1].intValue
        } else {
            return nil
        }

        do {
            let result = try MLMultiArray(
                shape: [predictionWindow as NSNumber,
                        numComponents as NSNumber,
                        numJoints as NSNumber],
                dataType: .float32
            )

            let resultPtr = UnsafeMutablePointer<Float>(OpaquePointer(result.dataPointer))
            let frameStride = numComponents * numJoints

            for (frameIdx, frame) in frames.enumerated() {
                let src = frame.keypointsArray
                let dstOffset = frameIdx * frameStride

                if src.dataType == .double {
                    let doubleSrc = UnsafeMutablePointer<Double>(OpaquePointer(src.dataPointer))
                    for i in 0..<frameStride {
                        resultPtr[dstOffset + i] = Float(doubleSrc[i])
                    }
                } else {
                    let floatSrc = UnsafeMutablePointer<Float>(OpaquePointer(src.dataPointer))
                    for i in 0..<frameStride {
                        resultPtr[dstOffset + i] = floatSrc[i]
                    }
                }
            }

            return result
        } catch {
            return nil
        }
    }

    private func parsePrediction(_ prediction: MLFeatureProvider, frames: [PoseFrame]) -> PredictionRecord? {
        guard let labelValue = prediction.featureValue(for: "label") else { return nil }

        let label = labelValue.stringValue
        let probabilities: [String: Double]

        if let probsValue = prediction.featureValue(for: "labelProbabilities"),
           let probs = probsValue.dictionaryValue as? [String: Double] {
            probabilities = probs
        } else {
            probabilities = [label: 1.0]
        }

        return PredictionRecord(
            timestamp: frames.last?.timestamp ?? 0,
            windowStart: frames.first?.timestamp ?? 0,
            label: label,
            probabilities: probabilities
        )
    }
}
