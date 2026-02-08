//
//  SwingNetPredictor.swift
//  golf-sync-swing
//
//  Wraps the CoreML SwingNet model for golf swing event detection.
//  Input: 64 RGB frames (160x160) -> Output: per-frame event probabilities.
//

import CoreML
import Foundation

/// Parsed SwingNet output
struct SwingNetAnalysis {
    /// Per-event: (peakFrameIndex, peakProbability)
    var eventPeaks: [SwingNetEvent: (frame: Int, prob: Float)] = [:]
    var noEventDominantFrameCount: Int = 0

    /// Raw impact probabilities for all 64 frames (enables sub-frame interpolation)
    var impactProbabilities: [Float] = []

    var impactFrame: Int { eventPeaks[.impact]?.frame ?? 0 }
    var impactProb: Float { eventPeaks[.impact]?.prob ?? 0 }

    /// Probability-weighted centroid timestamp around the peak impact frame.
    /// Uses ±2 frames to interpolate sub-frame precision (~8ms at 30fps).
    func impactTimestamp(in frames: [RGBFrameData]) -> TimeInterval {
        let peak = impactFrame
        guard !frames.isEmpty, peak < frames.count else { return 0 }
        guard impactProbabilities.count == 64 else { return frames[peak].timestamp }

        let radius = 2
        let lo = max(0, peak - radius)
        let hi = min(frames.count - 1, peak + radius)

        var weightedTime: Double = 0
        var totalWeight: Double = 0

        for i in lo...hi {
            let w = Double(max(0, impactProbabilities[i]))
            weightedTime += w * frames[i].timestamp
            totalWeight += w
        }

        guard totalWeight > 0 else { return frames[peak].timestamp }
        return weightedTime / totalWeight
    }
}

protocol SwingNetPredicting: Sendable {
    var isLoaded: Bool { get }
    func predict(frames: [RGBFrameData], frameWidth: Int, frameHeight: Int) -> SwingNetAnalysis?
}

final class SwingNetPredictor: SwingNetPredicting, @unchecked Sendable {

    private var swingNet: SwingNet?
    private(set) var isLoaded: Bool = false

    private let imagenetMean: [Float] = [0.485, 0.456, 0.406]
    private let imagenetStd: [Float] = [0.229, 0.224, 0.225]

    init() {
        loadModel()
    }

    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            swingNet = try SwingNet(configuration: config)
            isLoaded = true
            print("SwingNetPredictor: loaded")
        } catch {
            isLoaded = false
            print("SwingNetPredictor: FAILED to load: \(error.localizedDescription)")
        }
    }

    func predict(frames: [RGBFrameData], frameWidth: Int, frameHeight: Int) -> SwingNetAnalysis? {
        guard isLoaded, let model = swingNet else { return nil }
        guard let input = buildInput(from: frames, frameWidth: frameWidth, frameHeight: frameHeight) else { return nil }

        do {
            let prediction = try model.prediction(video_frames: input)
            return analyzeOutput(prediction.event_probabilities)
        } catch {
            return nil
        }
    }

    // MARK: - Private

    private func buildInput(from frames: [RGBFrameData], frameWidth: Int, frameHeight: Int) -> MLMultiArray? {
        do {
            let input = try MLMultiArray(shape: [1, 64, 3, 160, 160] as [NSNumber], dataType: .float32)
            let pixelsPerChannel = frameWidth * frameHeight
            let pixelsPerFrame = 3 * pixelsPerChannel

            let scales: [Float] = [
                1.0 / (255.0 * imagenetStd[0]),
                1.0 / (255.0 * imagenetStd[1]),
                1.0 / (255.0 * imagenetStd[2])
            ]
            let biases: [Float] = [
                -imagenetMean[0] / imagenetStd[0],
                -imagenetMean[1] / imagenetStd[1],
                -imagenetMean[2] / imagenetStd[2]
            ]

            let ptr = UnsafeMutablePointer<Float>(OpaquePointer(input.dataPointer))

            for (frameIdx, frameData) in frames.enumerated() {
                let frameOffset = frameIdx * pixelsPerFrame
                for ch in 0..<3 {
                    let channelOffset = frameOffset + ch * pixelsPerChannel
                    let srcOffset = ch * pixelsPerChannel
                    let scale = scales[ch]
                    let bias = biases[ch]
                    for i in 0..<pixelsPerChannel {
                        ptr[channelOffset + i] = Float(frameData.rgbData[srcOffset + i]) * scale + bias
                    }
                }
            }

            return input
        } catch {
            return nil
        }
    }

    private func analyzeOutput(_ probabilities: MLMultiArray) -> SwingNetAnalysis {
        var analysis = SwingNetAnalysis()
        let eventCount = 9
        var impactProbs = [Float](repeating: 0, count: 64)

        for event in SwingNetEvent.allCases {
            analysis.eventPeaks[event] = (frame: 0, prob: 0)
        }

        for frameIdx in 0..<64 {
            var dominantEvent: Int = 0
            var dominantProb: Float = -1

            for eventIdx in 0..<eventCount {
                let prob = probabilities[[0, frameIdx, eventIdx] as [NSNumber]].floatValue

                if prob > dominantProb {
                    dominantProb = prob
                    dominantEvent = eventIdx
                }

                guard let event = SwingNetEvent(rawValue: eventIdx) else { continue }
                if prob > (analysis.eventPeaks[event]?.prob ?? 0) {
                    analysis.eventPeaks[event] = (frame: frameIdx, prob: prob)
                }

                if eventIdx == SwingNetEvent.impact.rawValue {
                    impactProbs[frameIdx] = prob
                }
            }

            if dominantEvent == SwingNetEvent.noEvent.rawValue {
                analysis.noEventDominantFrameCount += 1
            }
        }

        analysis.impactProbabilities = impactProbs
        return analysis
    }
}
