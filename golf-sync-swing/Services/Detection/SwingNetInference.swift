//
//  SwingNetInference.swift
//  golf-sync-swing
//
//  Handles CoreML model loading and inference. Takes cropped 160x160 frames,
//  normalizes with ImageNet mean/std, runs through SwingNet in 64-frame chunks,
//  and returns per-frame softmax probabilities (9 classes).
//

import CoreML
import CoreVideo
import os

// MARK: - Protocol

protocol SwingNetInferring: Sendable {
    func infer(frames: [(CVPixelBuffer, TimeInterval)]) throws -> [[Float]]
}

// MARK: - Implementation

final class SwingNetInference: SwingNetInferring {

    private let model: MLModel
    private let sequenceLength = 64
    private let mean: [Float] = [0.485, 0.456, 0.406]
    private let std: [Float] = [0.229, 0.224, 0.225]

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        self.model = try SwingNet(configuration: config).model
        AppLogger.detection.info("SwingNet model loaded")
    }

    // MARK: - Chunked Inference

    func infer(frames: [(CVPixelBuffer, TimeInterval)]) throws -> [[Float]] {
        var allProbs: [[Float]] = []
        var chunkStart = 0

        while chunkStart < frames.count {
            let chunkEnd = min(chunkStart + sequenceLength, frames.count)
            let chunk = Array(frames[chunkStart..<chunkEnd])
            let chunkProbs = try inferChunk(chunk)
            allProbs.append(contentsOf: chunkProbs)
            chunkStart += sequenceLength
        }

        return allProbs
    }

    // MARK: - Single Chunk

    private func inferChunk(_ chunk: [(CVPixelBuffer, TimeInterval)]) throws -> [[Float]] {
        let inputArray = try buildInputArray(from: chunk)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["input": inputArray])
        let prediction = try model.prediction(from: provider)

        guard let outputArray = prediction.featureValue(for: "var_838")?.multiArrayValue else {
            throw SyncEngineError.analysisFailure("SwingNet produced no output")
        }

        return parseOutput(outputArray, frameCount: chunk.count)
    }

    // MARK: - Input Preparation

    private func buildInputArray(from chunk: [(CVPixelBuffer, TimeInterval)]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: sequenceLength), 3, 160, 160], dataType: .float32)
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)

        for (frameIdx, (buffer, _)) in chunk.enumerated() {
            writeNormalizedPixels(from: buffer, to: pointer, frameIndex: frameIdx)
        }

        zeroPadRemainder(pointer: pointer, filledFrames: chunk.count)
        return array
    }

    private func zeroPadRemainder(pointer: UnsafeMutablePointer<Float>, filledFrames: Int) {
        let filledCount = filledFrames * 3 * 160 * 160
        let totalCount = sequenceLength * 3 * 160 * 160
        guard filledCount < totalCount else { return }
        pointer.advanced(by: filledCount).initialize(repeating: 0, count: totalCount - filledCount)
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
                let b = Float(pixelData[pixelOffset]) / 255.0
                let g = Float(pixelData[pixelOffset + 1]) / 255.0
                let r = Float(pixelData[pixelOffset + 2]) / 255.0

                pointer[frameOffset + 0 * 160 * 160 + y * 160 + x] = (r - mean[0]) / std[0]
                pointer[frameOffset + 1 * 160 * 160 + y * 160 + x] = (g - mean[1]) / std[1]
                pointer[frameOffset + 2 * 160 * 160 + y * 160 + x] = (b - mean[2]) / std[2]
            }
        }
    }

    // MARK: - Output Parsing

    private func parseOutput(_ array: MLMultiArray, frameCount: Int) -> [[Float]] {
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        return (0..<frameCount).map { frameIdx in
            softmax(pointer, offset: frameIdx * 9, count: 9)
        }
    }

    private func softmax(_ pointer: UnsafePointer<Float>, offset: Int, count: Int) -> [Float] {
        var maxVal: Float = -Float.greatestFiniteMagnitude
        for i in 0..<count { maxVal = max(maxVal, pointer[offset + i]) }

        var exps = [Float](repeating: 0, count: count)
        var expSum: Float = 0
        for i in 0..<count {
            exps[i] = exp(pointer[offset + i] - maxVal)
            expSum += exps[i]
        }

        return exps.map { $0 / expSum }
    }
}
