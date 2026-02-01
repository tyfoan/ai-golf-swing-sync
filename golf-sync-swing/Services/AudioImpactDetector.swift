//
//  AudioImpactDetector.swift
//  golf-sync-swing
//
//  Real-time audio impact detection for golf swing
//  Detects the distinctive "click" of club-ball contact
//

import AVFoundation
import Accelerate

/// Audio-based impact detector for confirming golf swing impact
/// Uses onset detection to find sudden audio transients (ball strike sound)
final class AudioImpactDetector: @unchecked Sendable {

    // MARK: - Configuration

    /// Minimum energy threshold to consider as potential impact (normalized 0-1)
    private let energyThreshold: Float = 0.15

    /// Minimum ratio of current energy to recent average for onset detection
    private let onsetRatio: Float = 3.0

    /// Window size for energy calculation (samples)
    private let windowSize: Int = 512

    /// History duration for baseline calculation (seconds)
    private let historyDuration: TimeInterval = 0.5

    /// Minimum time between detected impacts (seconds)
    private let minImpactInterval: TimeInterval = 1.0

    /// Time window to confirm impact with video (seconds)
    /// Audio impact must be within this window of video impact to be considered valid
    let confirmationWindow: TimeInterval = 0.15

    // MARK: - State

    private let lock = NSLock()
    private var energyHistory: [(timestamp: TimeInterval, energy: Float)] = []
    private var lastImpactTime: TimeInterval = -10.0
    private var sampleRate: Double = 44100.0

    // MARK: - Callback

    /// Called when audio impact is detected
    var onImpactDetected: (@Sendable (TimeInterval, Float) -> Void)?

    // MARK: - Public API

    /// Process audio samples for impact detection
    /// - Parameters:
    ///   - samples: Audio sample buffer (mono or first channel)
    ///   - timestamp: Presentation timestamp of the buffer
    ///   - sampleRate: Audio sample rate
    func processAudio(samples: UnsafePointer<Float>, count: Int, timestamp: TimeInterval, sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }

        self.sampleRate = sampleRate

        // Calculate RMS energy of the buffer
        var energy: Float = 0
        vDSP_rmsqv(samples, 1, &energy, vDSP_Length(count))

        // Add to history
        energyHistory.append((timestamp, energy))

        // Trim old history
        let cutoff = timestamp - historyDuration
        energyHistory.removeAll { $0.timestamp < cutoff }

        // Need enough history for onset detection
        guard energyHistory.count >= 5 else { return }

        // Don't detect too soon after last impact
        guard timestamp - lastImpactTime > minImpactInterval else { return }

        // Calculate recent average energy (excluding current)
        let recentEnergies = energyHistory.dropLast()
        let avgEnergy = recentEnergies.reduce(0.0) { $0 + $1.energy } / Float(recentEnergies.count)

        // Onset detection: sudden spike above threshold AND above average
        let isAboveThreshold = energy > energyThreshold
        let isOnset = avgEnergy > 0.001 && (energy / avgEnergy) > onsetRatio

        // Also check for absolute spike (for quiet environments)
        let isAbsoluteSpike = energy > 0.3

        if isAboveThreshold && (isOnset || isAbsoluteSpike) {
            // Calculate confidence based on how strong the onset is
            let confidence = min(1.0, energy / 0.5)
            lastImpactTime = timestamp

            onImpactDetected?(timestamp, confidence)
        }
    }

    /// Process CMSampleBuffer from audio capture
    func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // Get audio format
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
        let sampleRate = asbd?.mSampleRate ?? 44100.0

        // Get raw audio data
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let data = dataPointer else { return }

        // Convert to float samples (assuming 16-bit PCM)
        let sampleCount = length / 2
        var floatSamples = [Float](repeating: 0, count: sampleCount)

        data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { int16Ptr in
            var scale = Float(Int16.max)
            vDSP_vflt16(int16Ptr, 1, &floatSamples, 1, vDSP_Length(sampleCount))
            vDSP_vsdiv(floatSamples, 1, &scale, &floatSamples, 1, vDSP_Length(sampleCount))
        }

        processAudio(samples: floatSamples, count: sampleCount, timestamp: timestamp, sampleRate: sampleRate)
    }

    /// Check if an audio impact was detected near a given timestamp
    /// - Parameters:
    ///   - videoImpactTime: Video-detected impact timestamp
    /// - Returns: Audio impact timestamp if found within confirmation window, nil otherwise
    func findNearbyImpact(near videoImpactTime: TimeInterval) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }

        // Check if last detected impact is within confirmation window
        if abs(lastImpactTime - videoImpactTime) < confirmationWindow {
            return lastImpactTime
        }

        return nil
    }

    /// Reset detector state
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        energyHistory.removeAll()
        lastImpactTime = -10.0
    }
}
