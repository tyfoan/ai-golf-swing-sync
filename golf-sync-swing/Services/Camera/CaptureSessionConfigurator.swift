//
//  CaptureSessionConfigurator.swift
//  golf-sync-swing
//
//  Configures AVCaptureSession with video/audio inputs, outputs, and device format.
//  Handles format negotiation (1080p60 targeting), low-light boost, and stabilization.
//
//  There is deliberately NO audio DATA output here: the movie file output records the
//  microphone track on its own, and nothing in the app consumes raw audio sample buffers.
//

import AVFoundation
import UIKit
import os

final class CaptureSessionConfigurator {

    struct Configuration {
        var position: AVCaptureDevice.Position = .back
        var frameRate: Double = 60
    }

    struct ConfiguredOutputs {
        let videoDeviceInput: AVCaptureDeviceInput?
        let audioDeviceInput: AVCaptureDeviceInput?
        let videoDataOutput: AVCaptureVideoDataOutput?
        let movieFileOutput: AVCaptureMovieFileOutput?
    }

    /// A device format paired with the frame-rate range that justified choosing it.
    private struct FormatChoice {
        let format: AVCaptureDevice.Format
        let range: AVFrameRateRange
    }

    /// `probe` receives one line per configuration step with the milliseconds that step
    /// took. Cold bring-up is a chain of serial system calls and a 7-second total tells
    /// you nothing about which call was slow; only a real device can answer that.
    func configure(
        session: AVCaptureSession,
        config: Configuration,
        videoDelegate: AVCaptureVideoDataOutputSampleBufferDelegate,
        videoQueue: DispatchQueue,
        probe: (String) -> Void = { _ in }
    ) -> (outputs: ConfiguredOutputs, error: CameraError?) {
        var lastStamp = ProcessInfo.processInfo.systemUptime
        func stamp(_ phase: String) {
            let now = ProcessInfo.processInfo.systemUptime
            probe("configure.\(phase) \(String(format: "%.0fms", (now - lastStamp) * 1000))")
            lastStamp = now
        }

        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        // The app owns AVAudioSession (CameraService.configureAudioSession). Left at its
        // default of `true`, AVCaptureSession re-derives the category/mode and re-activates
        // the audio session itself inside `startRunning()` — duplicating work the app has
        // already done, and observed on device as a 15s `startRunning` bracketing a
        // `FigAudioSession(AV) err=-19224`. Every `startRunning` path in CameraService now
        // guarantees an active, correctly categorised audio session before it starts.
        session.automaticallyConfiguresApplicationAudioSession = false

        if session.isMultitaskingCameraAccessSupported {
            session.isMultitaskingCameraAccessEnabled = true
        }

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        stamp("emptySession")

        // Video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: config.position) else {
            return abort(session, with: .noVideoDevice)
        }
        stamp("videoDeviceDiscovery")

        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            return abort(session, with: .configurationFailed(error.localizedDescription))
        }
        stamp("videoInputCreate")

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }
        stamp("videoInputAdd")

        let choice = configureDeviceFormat(device: videoDevice, targetFPS: config.frameRate)
        stamp("deviceFormat")
        probe("configure.format \(describe(choice))")

        // Audio input. The microphone track is recorded by the movie file output and consumed
        // downstream (export, comparison, Photos, the unmute control), so this input stays.
        // It is added AFTER CameraService has configured AVAudioSession — with
        // `automaticallyConfiguresApplicationAudioSession` off nothing else establishes the
        // category, so that ordering is load-bearing. Do not reorder.
        let audioDevice = AVCaptureDevice.default(for: .audio)
        // Stamped outside the `if let` so a nil lookup still reports its cost instead of
        // folding silently into the next phase.
        stamp("audioDeviceDiscovery")

        var audioInput: AVCaptureDeviceInput?
        if let audioDevice, let input = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
        }
        stamp("audioInputAdd")

        // Video data output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(videoDelegate, queue: videoQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        var configuredVideoOutput: AVCaptureVideoDataOutput?
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            configuredVideoOutput = videoOutput

            // Rotation is applied later by CaptureRotationSubject (device-correct angle).
            if let connection = videoOutput.connection(with: .video),
               connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }
        stamp("videoDataOutputAdd")

        // Movie file output
        let movieOutput = AVCaptureMovieFileOutput()
        // 1-second fragments keep the in-progress file readable for mid-recording
        // replay playback. Larger intervals (e.g., 5s) leave SwingReplayView's
        // AVURLAsset stuck waiting for the next moov flush when a swing finishes
        // mid-fragment.
        movieOutput.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 1)
        var configuredMovieOutput: AVCaptureMovieFileOutput?
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            configuredMovieOutput = movieOutput

            if let connection = movieOutput.connection(with: .video) {
                // Rotation is applied later by CaptureRotationSubject (device-correct angle).
                if config.position == .front, connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
                // Set here, inside begin/commitConfiguration, NOT at recording start:
                // changing stabilization on a running session rebuilds the pipeline and
                // blanks the preview at the exact moment recording begins.
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
        }
        stamp("movieFileOutputAdd")

        session.commitConfiguration()
        stamp("commit")

        let outputs = ConfiguredOutputs(
            videoDeviceInput: videoInput,
            audioDeviceInput: audioInput,
            videoDataOutput: configuredVideoOutput,
            movieFileOutput: configuredMovieOutput
        )

        return (outputs, nil)
    }

    /// Closes an aborted configuration: the session has already been emptied, so it must be
    /// committed before returning or every later `beginConfiguration` nests against it.
    private func abort(_ session: AVCaptureSession, with error: CameraError) -> (outputs: ConfiguredOutputs, error: CameraError?) {
        session.commitConfiguration()
        let empty = ConfiguredOutputs(videoDeviceInput: nil, audioDeviceInput: nil, videoDataOutput: nil, movieFileOutput: nil)
        return (empty, error)
    }

    // MARK: - Device Format

    /// Returns the format that was activated, so the caller can report it through `probe`.
    /// nil when the device refused configuration or exposed nothing fast enough.
    private func configureDeviceFormat(device: AVCaptureDevice, targetFPS: Double) -> FormatChoice? {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            guard let choice = preferredChoice(for: device, targetFPS: targetFPS) else { return nil }
            apply(choice, to: device, targetFPS: targetFPS)
            return choice
        } catch {
            AppLogger.camera.error("Failed to configure device format: \(error.localizedDescription)")
            return nil
        }
    }

    /// 1080p first, any resolution second — resolution is the preference the app actually has.
    private func preferredChoice(for device: AVCaptureDevice, targetFPS: Double) -> FormatChoice? {
        let fullHD = device.formats.filter { isFullHD($0) }
        return slowestSufficientChoice(among: fullHD, targetFPS: targetFPS)
            ?? largestSufficientChoice(among: device.formats, targetFPS: targetFPS)
    }

    /// Among formats that can sustain `targetFPS`, the SLOWEST one wins.
    ///
    /// Every candidate already covers the requested cadence and the frame duration is pinned
    /// to `targetFPS` immediately afterwards, so a 240 fps format delivers exactly the same
    /// 30 fps stream as the 30 fps format — while costing far more sensor bandwidth and
    /// offering a narrower set of stabilization modes (high-speed formats commonly drop
    /// `.cinematicExtended`, silently downgrading `preferredVideoStabilizationMode = .auto`).
    private func slowestSufficientChoice(among formats: [AVCaptureDevice.Format], targetFPS: Double) -> FormatChoice? {
        var best: FormatChoice?
        for format in formats {
            for range in format.videoSupportedFrameRateRanges where range.maxFrameRate >= targetFPS {
                guard best.map({ range.maxFrameRate < $0.range.maxFrameRate }) ?? true else { continue }
                best = FormatChoice(format: format, range: range)
            }
        }
        return best
    }

    /// Fallback when no 1080p format qualifies: highest resolution, and within one resolution
    /// the same slowest-sufficient rule as above.
    private func largestSufficientChoice(among formats: [AVCaptureDevice.Format], targetFPS: Double) -> FormatChoice? {
        var best: FormatChoice?
        var bestResolution = 0
        for format in formats {
            let resolution = pixelCount(of: format)
            for range in format.videoSupportedFrameRateRanges where range.maxFrameRate >= targetFPS {
                let winsOnResolution = resolution > bestResolution
                let winsOnFrameRate = resolution == bestResolution
                    && (best.map { range.maxFrameRate < $0.range.maxFrameRate } ?? true)
                guard winsOnResolution || winsOnFrameRate else { continue }
                best = FormatChoice(format: format, range: range)
                bestResolution = resolution
            }
        }
        return best
    }

    private func apply(_ choice: FormatChoice, to device: AVCaptureDevice, targetFPS: Double) {
        device.activeFormat = choice.format
        let actualFPS = min(targetFPS, choice.range.maxFrameRate)
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(actualFPS))
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration

        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
        }
    }

    private func isFullHD(_ format: AVCaptureDevice.Format) -> Bool {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return dimensions.width == 1920 && dimensions.height == 1080
    }

    private func pixelCount(of format: AVCaptureDevice.Format) -> Int {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return Int(dimensions.width) * Int(dimensions.height)
    }

    // MARK: - Reporting

    /// Which format the tie-break actually landed on. Not verifiable from a desk, and the
    /// subtype matters beyond the camera: a 10-bit `x420` format makes the movie output write
    /// HLG HEVC, which changes what the export and comparison pipelines receive downstream.
    private func describe(_ choice: FormatChoice?) -> String {
        guard let choice else { return "none" }
        let dimensions = CMVideoFormatDescriptionGetDimensions(choice.format.formatDescription)
        let subtype = CMFormatDescriptionGetMediaSubType(choice.format.formatDescription)
        return "\(dimensions.width)x\(dimensions.height) subtype=\(fourCharCodeString(subtype)) maxFPS=\(Int(choice.range.maxFrameRate))"
    }

    private func fourCharCodeString(_ code: FourCharCode) -> String {
        let characters = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((code >> $0) & 0xFF))) }
        return String(characters)
    }
}
