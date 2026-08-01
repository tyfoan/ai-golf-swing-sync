//
//  CaptureSessionConfigurator.swift
//  golf-sync-swing
//
//  Builds the capture graph in two passes. `configure` is the PREVIEW pass — video input,
//  format negotiation (1080p60 targeting), low-light boost, video-data output: everything a
//  live frame needs and nothing more, because on device the full graph's cold `startRunning`
//  measured 15.5–21.5 s while the audio route negotiated, and none of that work produces a
//  pixel. `installRecordingPipeline` is the RECORDING pass — microphone input, movie file
//  output, stabilization — installed against the RUNNING session during the record countdown
//  (see `CameraService.armRecordingPipeline`), so its cost hides behind time a take already
//  spends.
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

    struct PreviewGraphOutputs {
        let videoDeviceInput: AVCaptureDeviceInput?
        let videoDataOutput: AVCaptureVideoDataOutput?
    }

    /// What the recording pass added. The microphone is best-effort — a device without one
    /// records silent video, exactly as the single-pass configure always did. The movie
    /// output is not: a take with nowhere to write is an error, not a degradation.
    struct RecordingPipelineOutputs {
        let audioDeviceInput: AVCaptureDeviceInput?
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
    ) -> (outputs: PreviewGraphOutputs, error: CameraError?) {
        var lastStamp = ProcessInfo.processInfo.systemUptime
        func stamp(_ phase: String) {
            let now = ProcessInfo.processInfo.systemUptime
            probe("configure.\(phase) \(String(format: "%.0fms", (now - lastStamp) * 1000))")
            lastStamp = now
        }

        // Named before anything is built, so every timing below is attributable to the graph that
        // actually got requested. `multitaskingSupported` rides along because the flag beneath it
        // is one of the knobs, and "we skipped it" and "the device never offered it" are different
        // facts that produce the same absent line.
        let experiment = CaptureExperiment.current
        probe("configure.experiment \(experiment.summary) multitaskingSupported=\(session.isMultitaskingCameraAccessSupported)")

        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        // The app owns AVAudioSession (CameraService.configureAudioSession). Left at its
        // default of `true`, AVCaptureSession re-derives the category/mode and re-activates
        // the audio session itself inside `startRunning()` — duplicating work the app has
        // already done, and observed on device as a 15s `startRunning` bracketing a
        // `FigAudioSession(AV) err=-19224`. Every `startRunning` path in CameraService now
        // guarantees an active, correctly categorised audio session before it starts.
        session.automaticallyConfiguresApplicationAudioSession = false

        if session.isMultitaskingCameraAccessSupported, experiment.includesMultitaskingAccess {
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

        // NO microphone here, deliberately: it belongs to `installRecordingPipeline`. A mic
        // input drags the whole audio stack into `startRunning` — the route negotiation the
        // preview never needed and the user waited out behind "Preparing camera…".

        // Video data output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(videoDelegate, queue: videoQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        var configuredVideoOutput: AVCaptureVideoDataOutput?
        if experiment.includesVideoDataOutput, session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            configuredVideoOutput = videoOutput

            // Rotation is applied later by CaptureRotationSubject (device-correct angle).
            if let connection = videoOutput.connection(with: .video),
               connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }
        stamp("videoDataOutputAdd")

        session.commitConfiguration()
        stamp("commit")

        let outputs = PreviewGraphOutputs(
            videoDeviceInput: videoInput,
            videoDataOutput: configuredVideoOutput
        )

        return (outputs, nil)
    }

    /// Closes an aborted configuration: the session has already been emptied, so it must be
    /// committed before returning or every later `beginConfiguration` nests against it.
    private func abort(_ session: AVCaptureSession, with error: CameraError) -> (outputs: PreviewGraphOutputs, error: CameraError?) {
        session.commitConfiguration()
        return (PreviewGraphOutputs(videoDeviceInput: nil, videoDataOutput: nil), error)
    }

    // MARK: - Recording Pipeline (second pass)

    /// The recording pass, run against the RUNNING session during the record countdown. The
    /// caller (`CameraService.armRecordingPipeline`) has already configured and activated
    /// AVAudioSession — with `automaticallyConfiguresApplicationAudioSession` off nothing
    /// else establishes the category, so that ordering is load-bearing. Do not reorder.
    func installRecordingPipeline(
        session: AVCaptureSession,
        position: AVCaptureDevice.Position,
        probe: (String) -> Void = { _ in }
    ) -> (outputs: RecordingPipelineOutputs, error: CameraError?) {
        var lastStamp = ProcessInfo.processInfo.systemUptime
        func stamp(_ phase: String) {
            let now = ProcessInfo.processInfo.systemUptime
            probe("arm.\(phase) \(String(format: "%.0fms", (now - lastStamp) * 1000))")
            lastStamp = now
        }

        let experiment = CaptureExperiment.current
        session.beginConfiguration()

        let audioInput = addMicrophoneInput(to: session, experiment: experiment)
        stamp("audioInputAdd")

        guard experiment.includesMovieOutput else {
            // A measurement launch, not a session: the omission is the experiment's point.
            session.commitConfiguration()
            return (RecordingPipelineOutputs(audioDeviceInput: audioInput, movieFileOutput: nil), nil)
        }

        let movieOutput = makeMovieFileOutput()
        guard session.canAddOutput(movieOutput) else {
            // Self-cleaning: a failed arm must leave the graph EXACTLY as it found it. The
            // mic input added above would otherwise ride along with
            // `isRecordingPipelineArmed` still false — unreachable by
            // `removeRecordingPipeline` (flag-gated) and dragging the audio stack into
            // every later preview start.
            if let audioInput { session.removeInput(audioInput) }
            session.commitConfiguration()
            return (
                RecordingPipelineOutputs(audioDeviceInput: nil, movieFileOutput: nil),
                .configurationFailed("movie file output rejected")
            )
        }
        session.addOutput(movieOutput)
        configureMovieConnection(of: movieOutput, position: position, experiment: experiment)
        stamp("movieFileOutputAdd")

        session.commitConfiguration()
        stamp("commit")

        return (RecordingPipelineOutputs(audioDeviceInput: audioInput, movieFileOutput: movieOutput), nil)
    }

    /// Strips what `installRecordingPipeline` added, so the next start is a minimal start
    /// again. Parts are identified by shape rather than by held references: a filter cannot
    /// go stale across the configure passes that rebuild the graph wholesale.
    func removeRecordingPipeline(session: AVCaptureSession, probe: (String) -> Void = { _ in }) {
        let t0 = ProcessInfo.processInfo.systemUptime
        session.beginConfiguration()
        session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .filter { $0.device.hasMediaType(.audio) }
            .forEach { session.removeInput($0) }
        session.outputs
            .filter { $0 is AVCaptureMovieFileOutput }
            .forEach { session.removeOutput($0) }
        session.commitConfiguration()
        probe("arm.remove \(String(format: "%.0fms", (ProcessInfo.processInfo.systemUptime - t0) * 1000))")
    }

    /// The microphone track is recorded by the movie file output and consumed downstream
    /// (export, comparison, Photos, the unmute control). Best-effort by design.
    private func addMicrophoneInput(
        to session: AVCaptureSession,
        experiment: CaptureExperiment
    ) -> AVCaptureDeviceInput? {
        guard experiment.includesMicrophone,
              let audioDevice = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: audioDevice),
              session.canAddInput(input) else { return nil }
        session.addInput(input)
        return input
    }

    private func makeMovieFileOutput() -> AVCaptureMovieFileOutput {
        let movieOutput = AVCaptureMovieFileOutput()
        // 1-second fragments keep the in-progress file readable for mid-recording
        // replay playback. Larger intervals (e.g., 5s) leave SwingReplayView's
        // AVURLAsset stuck waiting for the next moov flush when a swing finishes
        // mid-fragment.
        movieOutput.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 1)
        return movieOutput
    }

    private func configureMovieConnection(
        of movieOutput: AVCaptureMovieFileOutput,
        position: AVCaptureDevice.Position,
        experiment: CaptureExperiment
    ) {
        guard let connection = movieOutput.connection(with: .video) else { return }
        // Rotation is applied later by CaptureRotationSubject (device-correct angle).
        if position == .front, connection.isVideoMirroringSupported {
            connection.isVideoMirrored = true
        }
        // Set here, inside begin/commitConfiguration, NOT at recording start: changing
        // stabilization outside a configuration pass rebuilds the pipeline and blanks the
        // preview at the exact moment recording begins. Inside the countdown's pass, the
        // rebuild hides behind the ticks.
        if connection.isVideoStabilizationSupported, experiment.includesStabilization {
            connection.preferredVideoStabilizationMode = .auto
        }
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
