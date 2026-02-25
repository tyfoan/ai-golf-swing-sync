//
//  SwingNetDetector.swift
//  golf-sync-swing
//
//  Loads the SwingNet CoreML model and runs inference on a sequence of
//  160x160 person-cropped frames. Returns a SwingDetectionResult with
//  the exact impact frame timestamp determined by argmax(probs[:, 5]).
//
//  SwingNet outputs 9 per-frame probabilities:
//    0=Address, 1=Toe-up, 2=Mid-backswing, 3=Top,
//    4=Mid-downswing, 5=Impact, 6=Mid-follow-through, 7=Finish,
//    8=No-event
//

import CoreML
import CoreVideo
import os

// MARK: - Protocol

protocol SwingNetDetecting: Sendable {
    func detect(frames: [(CVPixelBuffer, TimeInterval)]) throws -> SwingDetectionResult
}

// MARK: - Event Indices

enum SwingNetEvent: Int, CaseIterable {
    case address = 0
    case toeUp = 1
    case midBackswing = 2
    case top = 3
    case midDownswing = 4
    case impact = 5
    case midFollowThrough = 6
    case finish = 7
}

// MARK: - Implementation

final class SwingNetDetector: SwingNetDetecting {

    private let model: MLModel
    private let sequenceLength = 64

    // ImageNet normalization constants
    private let mean: [Float] = [0.485, 0.456, 0.406]
    private let std: [Float] = [0.229, 0.224, 0.225]

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        self.model = try SwingNet(configuration: config).model
        AppLogger.detection.info("SwingNet model loaded")
    }

    // MARK: - Detection

    func detect(frames: [(CVPixelBuffer, TimeInterval)]) throws -> SwingDetectionResult {
        guard !frames.isEmpty else {
            return SwingDetectionResult(impactTime: nil, impactConfidence: 0, startTime: nil, endTime: nil)
        }

        let allProbs = try inferAllChunks(frames: frames)
        return extractEvents(probabilities: allProbs, timestamps: frames.map(\.1))
    }

    // MARK: - Chunked Inference

    private func inferAllChunks(frames: [(CVPixelBuffer, TimeInterval)]) throws -> [[Float]] {
        var allProbs: [[Float]] = []
        var chunkStart = 0

        while chunkStart < frames.count {
            let chunkEnd = min(chunkStart + sequenceLength, frames.count)
            let chunkFrames = Array(frames[chunkStart..<chunkEnd])
            let chunkProbs = try inferChunk(chunkFrames)
            allProbs.append(contentsOf: chunkProbs)
            chunkStart += sequenceLength
        }

        return allProbs
    }

    private func inferChunk(_ chunk: [(CVPixelBuffer, TimeInterval)]) throws -> [[Float]] {
        let inputArray = try buildInputArray(from: chunk)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["input": inputArray])
        let prediction = try model.prediction(from: provider)

        guard let outputArray = prediction.featureValue(for: "var_838")?.multiArrayValue else {
            throw SyncEngineError.analysisFailure("SwingNet produced no output")
        }

        return parseOutputArray(outputArray, actualFrameCount: chunk.count)
    }

    // MARK: - Input Preparation

    private func buildInputArray(from chunk: [(CVPixelBuffer, TimeInterval)]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: sequenceLength), 3, 160, 160], dataType: .float32)
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)

        for (frameIdx, (buffer, _)) in chunk.enumerated() {
            writeNormalizedPixels(from: buffer, to: pointer, frameIndex: frameIdx)
        }

        // Zero-pad remaining frames if chunk is shorter than sequenceLength
        let filledCount = chunk.count * 3 * 160 * 160
        let totalCount = sequenceLength * 3 * 160 * 160
        if filledCount < totalCount {
            pointer.advanced(by: filledCount).initialize(repeating: 0, count: totalCount - filledCount)
        }

        return array
    }

    private func writeNormalizedPixels(from buffer: CVPixelBuffer, to pointer: UnsafeMutablePointer<Float>, frameIndex: Int) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }

        let pixelData = baseAddress.assumingMemoryBound(to: UInt8.self)
        let frameOffset = frameIndex * 3 * 160 * 160

        for y in 0..<min(height, 160) {
            for x in 0..<min(width, 160) {
                let pixelOffset = y * bytesPerRow + x * 4
                // BGRA format → extract R, G, B
                let b = Float(pixelData[pixelOffset]) / 255.0
                let g = Float(pixelData[pixelOffset + 1]) / 255.0
                let r = Float(pixelData[pixelOffset + 2]) / 255.0

                let rIdx = frameOffset + 0 * 160 * 160 + y * 160 + x
                let gIdx = frameOffset + 1 * 160 * 160 + y * 160 + x
                let bIdx = frameOffset + 2 * 160 * 160 + y * 160 + x

                pointer[rIdx] = (r - mean[0]) / std[0]
                pointer[gIdx] = (g - mean[1]) / std[1]
                pointer[bIdx] = (b - mean[2]) / std[2]
            }
        }
    }

    // MARK: - Output Parsing

    private func parseOutputArray(_ array: MLMultiArray, actualFrameCount: Int) -> [[Float]] {
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        var probs: [[Float]] = []

        for frameIdx in 0..<actualFrameCount {
            var row = [Float](repeating: 0, count: 9)
            let rowStart = frameIdx * 9
            let rowMax = softmax(pointer, offset: rowStart, count: 9)
            for c in 0..<9 {
                row[c] = rowMax[c]
            }
            probs.append(row)
        }

        return probs
    }

    private func softmax(_ pointer: UnsafePointer<Float>, offset: Int, count: Int) -> [Float] {
        var maxVal: Float = -Float.greatestFiniteMagnitude
        for i in 0..<count {
            maxVal = max(maxVal, pointer[offset + i])
        }

        var expSum: Float = 0
        var exps = [Float](repeating: 0, count: count)
        for i in 0..<count {
            exps[i] = exp(pointer[offset + i] - maxVal)
            expSum += exps[i]
        }

        return exps.map { $0 / expSum }
    }

    // MARK: - Event Extraction

    private func extractEvents(probabilities: [[Float]], timestamps: [TimeInterval]) -> SwingDetectionResult {
        guard probabilities.count == timestamps.count else {
            return SwingDetectionResult(impactTime: nil, impactConfidence: 0, startTime: nil, endTime: nil)
        }

        let eventFrames = findEventFrames(probabilities: probabilities)

        let impactFrame = eventFrames[SwingNetEvent.impact.rawValue]
        let impactConfidence = Double(probabilities[impactFrame][SwingNetEvent.impact.rawValue])
        let impactTime = timestamps[impactFrame]

        let addressFrame = eventFrames[SwingNetEvent.address.rawValue]
        let finishFrame = eventFrames[SwingNetEvent.finish.rawValue]
        let startTime = timestamps[addressFrame]
        let endTime = timestamps[finishFrame]

        AppLogger.detection.info(
            "SwingNet: impact=\(impactFrame) (\(String(format: "%.2f", impactTime))s) conf=\(String(format: "%.3f", impactConfidence))"
        )

        return SwingDetectionResult(
            impactTime: impactTime,
            impactConfidence: impactConfidence,
            startTime: startTime,
            endTime: endTime
        )
    }

    private func findEventFrames(probabilities: [[Float]]) -> [Int] {
        // For each event column (0-7), find the frame with highest probability
        var eventFrames = [Int](repeating: 0, count: 8)

        for eventIdx in 0..<8 {
            var bestFrame = 0
            var bestProb: Float = -1

            for frameIdx in 0..<probabilities.count {
                let prob = probabilities[frameIdx][eventIdx]
                if prob > bestProb {
                    bestProb = prob
                    bestFrame = frameIdx
                }
            }

            eventFrames[eventIdx] = bestFrame
        }

        return eventFrames
    }
}
