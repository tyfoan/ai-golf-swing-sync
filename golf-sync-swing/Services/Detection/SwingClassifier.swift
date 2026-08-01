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

    /// One CoreML load per process, created the first time something ASKS for it — never at
    /// construction. Classifiers are built inside RecordingView's `@State` default, i.e. at
    /// MainTabView mount; an eager load from `init` (the previous shape) materialized the
    /// task milliseconds before the camera's cold bring-up and spent the one-time ANE/
    /// Espresso specialization competing with `startRunning` — exactly the contention the
    /// deferral exists to avoid. `.utility`: the classifier is a confidence boost, never on
    /// the critical path. Lock-guarded rather than a `static let` because a `static let`
    /// cannot distinguish "first access from `warmUp()`" from "first access from `init`".
    private static let loadLock = NSLock()
    nonisolated(unsafe) private static var loadTask: Task<MLModel?, Never>?
    /// Snapshot of the finished load, so the frame path reads a pointer under a lock
    /// instead of awaiting a task.
    nonisolated(unsafe) private static var loadedModel: MLModel?

    /// Starts the shared load. The first `MLModel.load` on a device pays a one-time
    /// on-device specialization (ANE/Espresso compile, cached afterwards); left to first
    /// access it lands mid-recording, when a stall costs a swing.
    ///
    /// Called from `RecordingViewModel.startRecording()` — the record tap — not from
    /// `App.init` or the tab's appear, where it competed with the camera's cold bring-up
    /// (on device the model reported "loaded successfully" *after* `startRunning` returned,
    /// 15.5 s in). From the record tap the compile overlaps the countdown instead, which is
    /// time the app is already spending. Idempotent: repeated calls share one load.
    static func warmUp() {
        _ = startLoadIfNeeded()
    }

    private static func startLoadIfNeeded() -> Task<MLModel?, Never> {
        loadLock.lock()
        defer { loadLock.unlock() }
        if let task = loadTask { return task }
        let task = Task<MLModel?, Never>(priority: .utility) {
            let model = await loadModel()
            loadLock.withLock { loadedModel = model }
            return model
        }
        loadTask = task
        return task
    }

    private let windowSize: Int
    private let swingConfidenceThreshold: Double

    /// Non-blocking: `analyze` runs per frame window and must never wait on a load. A nil
    /// here simply routes the caller to the PoseHeuristics fallback until the load lands.
    private var model: MLModel? {
        Self.loadLock.withLock { Self.loadedModel }
    }

    init(windowSize: Int = 15, swingConfidenceThreshold: Double = 0.85) {
        self.windowSize = windowSize
        self.swingConfidenceThreshold = swingConfidenceThreshold
    }

    /// Test seam: the model arrives asynchronously, so asserting `isAvailable` right after
    /// `warmUp()` is a race, not a test. Starts the load if nothing has, and resolves once
    /// the shared snapshot is populated — or immediately if the bundle has no model.
    func waitForModelLoad() async {
        _ = await Self.startLoadIfNeeded().value
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

    /// Returns a zero-filled [1, 3, 18] array as a fallback when no VNHumanBodyPoseObservation
    /// is available (e.g. no person detected in frame). The model treats zero-padded frames
    /// as "no pose data", which helps avoid false positives from missing detections.
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

    private static func loadModel() async -> MLModel? {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        guard let url = Bundle.main.url(forResource: "GolfSwingClassifier", withExtension: "mlmodelc") else {
            AppLogger.detection.info("SwingClassifier: model not found in bundle (expected during development)")
            return nil
        }

        do {
            let model = try await MLModel.load(contentsOf: url, configuration: config)
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
