//
//  SwingNetDetector.swift
//  golf-sync-swing
//
//  SwingNet-based swing detection using the GolfDB pretrained model.
//  Detects 9 swing events including precise Impact frame (event index 5).
//
//  Delegates to collaborators:
//    PersonCropper          - Pose-based person detection + frame cropping
//    RGBFrameBuffer         - Thread-safe sliding window of RGB frames
//    SwingNetPredictor      - CoreML SwingNet model wrapper
//    SwingValidationPipeline - Polymorphic validation rules
//    MotionGateService      - Adaptive classification stride
//

import AVFoundation
import CoreML
import Foundation

/// SwingNet event indices
enum SwingNetEvent: Int, CaseIterable {
    case address = 0
    case toeUp = 1
    case midBackswing = 2
    case top = 3
    case midDownswing = 4
    case impact = 5
    case midFollowThrough = 6
    case finish = 7
    case noEvent = 8

    var name: String {
        switch self {
        case .address: return "address"
        case .toeUp: return "toe_up"
        case .midBackswing: return "mid_backswing"
        case .top: return "top"
        case .midDownswing: return "mid_downswing"
        case .impact: return "impact"
        case .midFollowThrough: return "mid_follow_through"
        case .finish: return "finish"
        case .noEvent: return "no_event"
        }
    }

    var isSwingPhase: Bool { self != .noEvent }
}

final class SwingNetDetector: @unchecked Sendable {

    // MARK: - Configuration

    private let windowSize: Int = 64
    private let frameWidth: Int = 160
    private let frameHeight: Int = 160
    private let minDetectionInterval: TimeInterval = 2.0
    private let preSwingBuffer: TimeInterval = 1.0
    private let postImpactBuffer: TimeInterval = 1.0
    private let corroboratingEventThreshold: Float = 0.10

    // MARK: - Collaborators

    private let personCropper: PersonCropping
    private let frameBuffer: RGBFrameBuffer
    private let predictor: SwingNetPredicting
    private let validationPipeline: SwingValidationPipeline
    private let motionGate: MotionGateService

    // MARK: - State

    private let lock = NSLock()
    private var frameCounter: Int = 0
    private var adaptiveStride: Int = 30
    private var lastDetectionTime: TimeInterval = -10.0
    private var impactTime: TimeInterval?
    private var totalFramesProcessed: Int = 0

    /// Last successful analysis (for top-of-backswing extraction by VideoSyncEngine)
    private var lastAnalysis: SwingNetAnalysis?
    private var lastAnalysisFrames: [RGBFrameData]?

    // MARK: - Public State

    private(set) var isTrackingSwing: Bool = false
    private(set) var isMotionDetected: Bool = false
    private(set) var detectedSwings: [SwingBounds] = []

    /// Top-of-backswing timestamp from the last validated analysis
    var topOfBackswingTime: TimeInterval? {
        guard let analysis = lastAnalysis,
              let topPeak = analysis.eventPeaks[.top],
              topPeak.prob >= corroboratingEventThreshold,
              let frames = lastAnalysisFrames,
              topPeak.frame < frames.count else { return nil }
        return frames[topPeak.frame].timestamp
    }

    /// Top-of-backswing confidence from the last validated analysis
    var topOfBackswingConfidence: Double {
        guard let analysis = lastAnalysis,
              let topPeak = analysis.eventPeaks[.top] else { return 0 }
        return Double(topPeak.prob)
    }

    // MARK: - Callbacks

    var onSwingDetected: (@Sendable (SwingBounds) -> Void)?
    var onPhaseChanged: ((_ phase: String, _ confidence: Double) -> Void)?

    // MARK: - Init

    init(
        personCropper: PersonCropping = PersonCropper(),
        frameBuffer: RGBFrameBuffer = RGBFrameBuffer(capacity: 64),
        predictor: SwingNetPredicting = SwingNetPredictor(),
        validationPipeline: SwingValidationPipeline = .default(),
        motionGate: MotionGateService = MotionGateService()
    ) {
        self.personCropper = personCropper
        self.frameBuffer = frameBuffer
        self.predictor = predictor
        self.validationPipeline = validationPipeline
        self.motionGate = motionGate
    }

    // MARK: - Public API

    func processFrame(_ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) {
        totalFramesProcessed += 1

        guard let rgbData = personCropper.extractRGBData(from: pixelBuffer, frameWidth: frameWidth, frameHeight: frameHeight) else {
            return
        }

        let motionState = motionGate.update(with: rgbData)
        isMotionDetected = motionState != .idle

        switch motionState {
        case .idle:   adaptiveStride = 30
        case .active: adaptiveStride = 8
        case .peak:   adaptiveStride = 5
        }

        frameBuffer.append(RGBFrameData(timestamp: timestamp, rgbData: rgbData))

        lock.lock()
        guard timestamp - lastDetectionTime > minDetectionInterval else {
            lock.unlock()
            return
        }
        lock.unlock()

        frameCounter += 1
        if frameCounter >= adaptiveStride && frameBuffer.isFull {
            frameCounter = 0
            runClassification()
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        frameBuffer.clear()
        frameCounter = 0
        lastDetectionTime = -10.0
        impactTime = nil
        isTrackingSwing = false
        detectedSwings.removeAll()
        totalFramesProcessed = 0
        isMotionDetected = false
        adaptiveStride = 30
        motionGate.reset()
        lastAnalysis = nil
        lastAnalysisFrames = nil
        print("SwingNetDetector: Reset")
    }

    // MARK: - Classification

    private func runClassification() {
        let frames = frameBuffer.snapshot(last: windowSize)
        guard frames.count >= windowSize else { return }

        guard let analysis = predictor.predict(frames: frames, frameWidth: frameWidth, frameHeight: frameHeight) else {
            return
        }

        if let rejection = validationPipeline.validate(analysis) {
            print("SwingNet: rejected: \(rejection)")
            return
        }

        let impactTimestamp = analysis.impactTimestamp(in: frames)
        print("SwingNet: VALIDATED impact=\(String(format: "%.2f", impactTimestamp))s (\(Int(analysis.impactProb * 100))%)")

        lock.lock()
        lastAnalysis = analysis
        lastAnalysisFrames = frames

        if self.impactTime == nil || abs(impactTimestamp - self.impactTime!) > minDetectionInterval {
            self.impactTime = impactTimestamp

            let addressFrame = analysis.eventPeaks[.address]?.frame ?? 0
            let addressTimestamp = frames[addressFrame].timestamp

            let rawFinishFrame = analysis.eventPeaks[.finish]?.frame ?? 0
            let finishFrame = rawFinishFrame > analysis.impactFrame
                ? rawFinishFrame
                : min(63, analysis.impactFrame + 15)
            let finishTimestamp = frames[min(finishFrame, frames.count - 1)].timestamp

            let swing = SwingBounds(
                startTime: max(0, addressTimestamp - preSwingBuffer),
                impactTime: impactTimestamp,
                endTime: finishTimestamp + postImpactBuffer,
                confidence: Double(analysis.impactProb),
                detectionTime: frames.last?.timestamp ?? impactTimestamp,
                audioConfirmed: false
            )

            detectedSwings.append(swing)
            lastDetectionTime = frames.last?.timestamp ?? impactTimestamp
            lock.unlock()

            print("SWING: \(String(format: "%.2f", swing.startTime))s -> \(String(format: "%.2f", swing.impactTime))s -> \(String(format: "%.2f", swing.endTime))s")
            onSwingDetected?(swing)
            onPhaseChanged?("impact", Double(analysis.impactProb))
        } else {
            lock.unlock()
        }
    }
}
