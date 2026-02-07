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

    var impactFrame: Int { eventPeaks[.impact]?.frame ?? 0 }
    var impactProb: Float { eventPeaks[.impact]?.prob ?? 0 }

    func impactTimestamp(in frames: [RGBFrameData]) -> TimeInterval {
        frames[impactFrame].timestamp
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
            }

            if dominantEvent == SwingNetEvent.noEvent.rawValue {
                analysis.noEventDominantFrameCount += 1
            }
        }

        return analysis
    }
}
