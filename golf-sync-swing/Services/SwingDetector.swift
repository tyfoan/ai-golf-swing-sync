//
//  SwingDetector.swift
//  golf-sync-swing
//
//  Automatic swing phase detection using Vision body pose + audio analysis
//

import Foundation
import Vision
import AVFoundation
import Accelerate

/// Detected swing phase with timestamp and confidence
struct DetectedPhase: Identifiable {
    let id = UUID()
    let phase: SwingPhase
    let timestamp: TimeInterval
    let confidence: Double
}

/// Golf swing phases
enum SwingPhase: String, CaseIterable {
    case address = "Address"
    case backswing = "Backswing"
    case top = "Top"
    case downswing = "Downswing"
    case impact = "Impact"
    case followThrough = "Follow Through"
    case finish = "Finish"
}

/// Result of swing analysis
struct SwingDetectionResult {
    let impactTime: TimeInterval?
    let impactConfidence: Double
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    let phases: [DetectedPhase]

    var hasValidDetection: Bool {
        impactTime != nil && impactConfidence > 0.5
    }
}

/// Pose data for a single frame
struct FramePose {
    let timestamp: TimeInterval
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let confidence: Float

    func position(for joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        joints[joint]
    }
}

/// Main service for detecting golf swing phases
final class SwingDetector {

    // MARK: - Configuration

    /// Minimum confidence for pose detection
    private let minPoseConfidence: Float = 0.3

    /// Velocity threshold for detecting movement (normalized units per second)
    private let movementThreshold: Double = 0.15

    /// Velocity threshold for impact detection
    private let impactVelocityThreshold: Double = 0.4

    /// Acceleration threshold for impact detection
    private let impactAccelerationThreshold: Double = 0.3

    /// Key joints to track for golf swing
    private let keyJoints: [VNHumanBodyPoseObservation.JointName] = [
        .rightWrist,
        .leftWrist,
        .rightElbow,
        .leftElbow,
        .rightShoulder,
        .leftShoulder,
        .rightHip,
        .leftHip
    ]

    // MARK: - Public API

    /// Analyze a video for golf swing phases
    /// - Parameters:
    ///   - url: URL of the video file
    ///   - progress: Progress callback (0.0 to 1.0)
    /// - Returns: Detection result with impact time, start/end, and phases
    func analyzeVideo(at url: URL, progress: @escaping (Float) -> Void) async throws -> SwingDetectionResult {
        // Extract poses from video frames
        let poses = try await extractPoses(from: url, progress: { p in
            progress(p * 0.7) // Pose extraction is 70% of work
        })

        guard poses.count > 10 else {
            return SwingDetectionResult(
                impactTime: nil,
                impactConfidence: 0,
                startTime: nil,
                endTime: nil,
                phases: []
            )
        }

        // Detect impact from pose velocity
        let (poseImpactTime, poseImpactConfidence) = detectImpactFromPoses(poses)
        progress(0.8)

        // Detect impact from audio (if available)
        let audioImpactTime = try? await detectImpactFromAudio(url: url)
        progress(0.9)

        // Combine results (prefer audio if both available and close)
        let (finalImpactTime, finalConfidence) = combineImpactDetections(
            poseImpact: poseImpactTime,
            poseConfidence: poseImpactConfidence,
            audioImpact: audioImpactTime
        )

        // Detect start and end times
        let (startTime, endTime) = detectSwingBounds(
            poses: poses,
            impactTime: finalImpactTime
        )

        // Build phase list
        var phases: [DetectedPhase] = []
        if let start = startTime {
            phases.append(DetectedPhase(phase: .address, timestamp: start, confidence: 0.7))
        }
        if let impact = finalImpactTime {
            phases.append(DetectedPhase(phase: .impact, timestamp: impact, confidence: finalConfidence))
        }
        if let end = endTime {
            phases.append(DetectedPhase(phase: .finish, timestamp: end, confidence: 0.7))
        }

        progress(1.0)

        return SwingDetectionResult(
            impactTime: finalImpactTime,
            impactConfidence: finalConfidence,
            startTime: startTime,
            endTime: endTime,
            phases: phases.sorted { $0.timestamp < $1.timestamp }
        )
    }

    // MARK: - Pose Extraction

    private func extractPoses(from url: URL, progress: @escaping (Float) -> Void) async throws -> [FramePose] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first

        guard let track = videoTrack else {
            throw SwingDetectorError.noVideoTrack
        }

        let fps = try await track.load(.nominalFrameRate)
        let totalFrames = Int(duration * Double(fps))

        // Determine sample interval based on frame rate
        let sampleInterval: Int
        switch fps {
        case 0..<45: sampleInterval = 1
        case 45..<90: sampleInterval = 2
        case 90..<180: sampleInterval = 3
        default: sampleInterval = 4
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var poses: [FramePose] = []
        let request = VNDetectHumanBodyPoseRequest()

        for frameIndex in stride(from: 0, to: totalFrames, by: sampleInterval) {
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(fps))
            let timestamp = time.seconds

            do {
                let (cgImage, _) = try await generator.image(at: time)

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])

                if let observation = request.results?.first {
                    let pose = extractPose(from: observation, at: timestamp)
                    if let pose = pose {
                        poses.append(pose)
                    }
                }
            } catch {
                // Skip frames that fail to process
                continue
            }

            let currentProgress = Float(frameIndex) / Float(totalFrames)
            progress(currentProgress)
        }

        return poses
    }

    private func extractPose(from observation: VNHumanBodyPoseObservation, at timestamp: TimeInterval) -> FramePose? {
        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        var totalConfidence: Float = 0
        var jointCount: Float = 0

        for jointName in keyJoints {
            guard let point = try? observation.recognizedPoint(jointName),
                  point.confidence > minPoseConfidence else {
                continue
            }

            joints[jointName] = point.location
            totalConfidence += point.confidence
            jointCount += 1
        }

        // Need at least wrist points for swing detection
        guard joints[.rightWrist] != nil || joints[.leftWrist] != nil else {
            return nil
        }

        let avgConfidence = jointCount > 0 ? totalConfidence / jointCount : 0

        return FramePose(
            timestamp: timestamp,
            joints: joints,
            confidence: avgConfidence
        )
    }

    // MARK: - Impact Detection (Pose-based)

    private func detectImpactFromPoses(_ poses: [FramePose]) -> (time: TimeInterval?, confidence: Double) {
        guard poses.count >= 5 else {
            return (nil, 0)
        }

        // Calculate wrist velocity for each frame
        var velocities: [(timestamp: TimeInterval, velocity: Double, acceleration: Double)] = []

        for i in 2..<poses.count {
            let current = poses[i]
            let prev = poses[i - 2]

            // Get primary wrist (right for right-handed, but check both)
            let currentWrist = current.position(for: .rightWrist) ?? current.position(for: .leftWrist)
            let prevWrist = prev.position(for: .rightWrist) ?? prev.position(for: .leftWrist)

            guard let cw = currentWrist, let pw = prevWrist else {
                continue
            }

            let dt = current.timestamp - prev.timestamp
            guard dt > 0 else { continue }

            // Velocity (positive Y is up in Vision coordinates)
            let velocityY = (cw.y - pw.y) / dt

            // Calculate acceleration if we have enough history
            var acceleration: Double = 0
            if velocities.count > 0 {
                let prevVelocity = velocities.last!.velocity
                acceleration = (velocityY - prevVelocity) / dt
            }

            velocities.append((current.timestamp, velocityY, acceleration))
        }

        // Find impact: maximum downward velocity with sudden deceleration
        var bestImpact: (time: TimeInterval, score: Double)? = nil

        for i in 1..<velocities.count {
            let v = velocities[i]

            // Impact signature: fast downward motion (negative velocity) + sudden deceleration (positive acceleration)
            let isDownward = v.velocity < -impactVelocityThreshold
            let isDecelerating = v.acceleration > impactAccelerationThreshold

            if isDownward && isDecelerating {
                let score = abs(v.velocity) * v.acceleration
                if bestImpact == nil || score > bestImpact!.score {
                    bestImpact = (v.timestamp, score)
                }
            }
        }

        if let impact = bestImpact {
            // Normalize confidence to 0-1 range
            let confidence = min(1.0, impact.score / 2.0)
            return (impact.time, confidence)
        }

        // Fallback: find frame with maximum downward velocity
        if let maxDownward = velocities.filter({ $0.velocity < 0 }).min(by: { $0.velocity < $1.velocity }) {
            return (maxDownward.timestamp, 0.4) // Lower confidence for fallback
        }

        return (nil, 0)
    }

    // MARK: - Impact Detection (Audio-based)

    private func detectImpactFromAudio(url: URL) async throws -> TimeInterval? {
        let asset = AVURLAsset(url: url)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var amplitudes: [(time: TimeInterval, amplitude: Float)] = []
        var currentTime: TimeInterval = 0
        let sampleRate: Double = 44100
        let windowSize = 1024 // Samples per window

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                break
            }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            guard let data = dataPointer else { continue }

            let sampleCount = length / 2 // 16-bit samples
            let samples = UnsafeBufferPointer(start: UnsafeRawPointer(data).assumingMemoryBound(to: Int16.self), count: sampleCount)

            // Process in windows
            for windowStart in stride(from: 0, to: sampleCount - windowSize, by: windowSize) {
                var sum: Float = 0
                for i in windowStart..<(windowStart + windowSize) {
                    sum += abs(Float(samples[i]))
                }
                let avgAmplitude = sum / Float(windowSize)

                let windowTime = currentTime + Double(windowStart) / sampleRate
                amplitudes.append((windowTime, avgAmplitude))
            }

            currentTime += Double(sampleCount) / sampleRate
        }

        // Find sudden amplitude spike (impact sound)
        guard amplitudes.count > 10 else { return nil }

        // Calculate baseline amplitude
        let sortedAmps = amplitudes.map { $0.amplitude }.sorted()
        let medianAmp = sortedAmps[sortedAmps.count / 2]

        // Find peaks that are significantly above baseline
        var bestPeak: (time: TimeInterval, ratio: Float)? = nil

        for i in 5..<(amplitudes.count - 5) {
            let current = amplitudes[i].amplitude
            let prevAvg = (amplitudes[i-1].amplitude + amplitudes[i-2].amplitude + amplitudes[i-3].amplitude) / 3
            let ratio = current / max(prevAvg, medianAmp, 1)

            // Impact should be >3x the surrounding amplitude
            if ratio > 3.0 {
                if bestPeak == nil || ratio > bestPeak!.ratio {
                    bestPeak = (amplitudes[i].time, ratio)
                }
            }
        }

        return bestPeak?.time
    }

    // MARK: - Combine Detections

    private func combineImpactDetections(
        poseImpact: TimeInterval?,
        poseConfidence: Double,
        audioImpact: TimeInterval?
    ) -> (time: TimeInterval?, confidence: Double) {
        switch (poseImpact, audioImpact) {
        case (nil, nil):
            return (nil, 0)

        case (let pose?, nil):
            return (pose, poseConfidence)

        case (nil, let audio?):
            return (audio, 0.7) // Audio-only has medium confidence

        case (let pose?, let audio?):
            // If both detections are close (within 0.1s), prefer audio (more precise)
            let timeDiff = abs(pose - audio)
            if timeDiff < 0.1 {
                // High confidence when both agree
                return (audio, min(1.0, poseConfidence + 0.2))
            } else if timeDiff < 0.3 {
                // Medium agreement - average the times
                let avgTime = (pose + audio) / 2
                return (avgTime, poseConfidence * 0.8)
            } else {
                // Disagreement - prefer pose if high confidence, else audio
                if poseConfidence > 0.6 {
                    return (pose, poseConfidence * 0.7)
                } else {
                    return (audio, 0.5)
                }
            }
        }
    }

    // MARK: - Swing Bounds Detection

    private func detectSwingBounds(
        poses: [FramePose],
        impactTime: TimeInterval?
    ) -> (start: TimeInterval?, end: TimeInterval?) {
        guard poses.count > 5 else {
            return (nil, nil)
        }

        // Calculate movement magnitude for each frame
        var movements: [(timestamp: TimeInterval, magnitude: Double)] = []

        for i in 1..<poses.count {
            let current = poses[i]
            let prev = poses[i - 1]

            let currentWrist = current.position(for: .rightWrist) ?? current.position(for: .leftWrist)
            let prevWrist = prev.position(for: .rightWrist) ?? prev.position(for: .leftWrist)

            guard let cw = currentWrist, let pw = prevWrist else {
                continue
            }

            let dx = cw.x - pw.x
            let dy = cw.y - pw.y
            let magnitude = sqrt(dx * dx + dy * dy)
            let dt = current.timestamp - prev.timestamp

            if dt > 0 {
                movements.append((current.timestamp, magnitude / dt))
            }
        }

        // Find swing start: first frame where movement exceeds threshold
        // Look before impact time if available
        var startTime: TimeInterval? = nil
        let searchEndTime = impactTime ?? movements.last?.timestamp ?? 0

        for m in movements {
            if m.timestamp > searchEndTime { break }
            if m.magnitude > movementThreshold {
                // Found movement - backtrack to find quiet period start
                let quietIndex = movements.firstIndex { $0.timestamp >= m.timestamp - 0.5 } ?? 0
                startTime = movements[quietIndex].timestamp
                break
            }
        }

        // Find swing end: frame where movement drops after impact
        var endTime: TimeInterval? = nil

        if let impact = impactTime {
            // Look for movement to settle after impact
            let postImpact = movements.filter { $0.timestamp > impact }
            var quietCount = 0

            for m in postImpact {
                if m.magnitude < movementThreshold {
                    quietCount += 1
                    if quietCount >= 3 {
                        endTime = m.timestamp
                        break
                    }
                } else {
                    quietCount = 0
                }
            }

            // Fallback: end 1.5 seconds after impact
            if endTime == nil && postImpact.count > 0 {
                endTime = min(impact + 1.5, postImpact.last!.timestamp)
            }
        }

        return (startTime, endTime)
    }
}

// MARK: - Errors

enum SwingDetectorError: LocalizedError {
    case noVideoTrack
    case analysisFailure(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "Video does not contain a video track"
        case .analysisFailure(let message):
            return "Swing analysis failed: \(message)"
        }
    }
}
