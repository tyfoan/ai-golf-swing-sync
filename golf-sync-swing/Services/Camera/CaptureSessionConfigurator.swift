//
//  CaptureSessionConfigurator.swift
//  golf-sync-swing
//
//  Configures AVCaptureSession with video/audio inputs, outputs, and device format.
//  Handles format negotiation (1080p60 targeting), low-light boost, and stabilization.
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
        let audioDataOutput: AVCaptureAudioDataOutput?
        let movieFileOutput: AVCaptureMovieFileOutput?
    }

    func configure(
        session: AVCaptureSession,
        config: Configuration,
        videoDelegate: AVCaptureVideoDataOutputSampleBufferDelegate,
        audioDelegate: AVCaptureAudioDataOutputSampleBufferDelegate,
        videoQueue: DispatchQueue,
        audioQueue: DispatchQueue
    ) -> (outputs: ConfiguredOutputs, error: CameraError?) {
        session.beginConfiguration()
        session.sessionPreset = .inputPriority

        if session.isMultitaskingCameraAccessSupported {
            session.isMultitaskingCameraAccessEnabled = true
        }

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        // Video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: config.position) else {
            session.commitConfiguration()
            return (ConfiguredOutputs(videoDeviceInput: nil, audioDeviceInput: nil, videoDataOutput: nil, audioDataOutput: nil, movieFileOutput: nil), .noVideoDevice)
        }

        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            session.commitConfiguration()
            return (ConfiguredOutputs(videoDeviceInput: nil, audioDeviceInput: nil, videoDataOutput: nil, audioDataOutput: nil, movieFileOutput: nil), .configurationFailed(error.localizedDescription))
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }

        configureDeviceFormat(device: videoDevice, targetFPS: config.frameRate)

        // Audio input
        var audioInput: AVCaptureDeviceInput?
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            if let input = try? AVCaptureDeviceInput(device: audioDevice),
               session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            }
        }

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

            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = false
                }
            }
        }

        // Audio data output
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(audioDelegate, queue: audioQueue)
        var configuredAudioOutput: AVCaptureAudioDataOutput?
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
            configuredAudioOutput = audioOutput
        }

        // Movie file output
        let movieOutput = AVCaptureMovieFileOutput()
        movieOutput.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 1)
        var configuredMovieOutput: AVCaptureMovieFileOutput?
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            configuredMovieOutput = movieOutput

            if let connection = movieOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if config.position == .front && connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
        }

        session.commitConfiguration()

        let outputs = ConfiguredOutputs(
            videoDeviceInput: videoInput,
            audioDeviceInput: audioInput,
            videoDataOutput: configuredVideoOutput,
            audioDataOutput: configuredAudioOutput,
            movieFileOutput: configuredMovieOutput
        )

        return (outputs, nil)
    }

    // MARK: - Device Format

    private func configureDeviceFormat(device: AVCaptureDevice, targetFPS: Double) {
        do {
            try device.lockForConfiguration()

            var bestFormat: AVCaptureDevice.Format?
            var bestFrameRateRange: AVFrameRateRange?

            // Target 1080p at target frame rate
            for format in device.formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                guard dimensions.width == 1920 && dimensions.height == 1080 else { continue }
                for range in format.videoSupportedFrameRateRanges {
                    if range.maxFrameRate >= targetFPS {
                        if bestFrameRateRange == nil || range.maxFrameRate > bestFrameRateRange!.maxFrameRate {
                            bestFormat = format
                            bestFrameRateRange = range
                        }
                    }
                }
            }

            // Fallback: highest resolution at target frame rate
            if bestFormat == nil {
                var bestResolution: Int = 0
                for format in device.formats {
                    let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    let resolution = Int(dimensions.width) * Int(dimensions.height)
                    for range in format.videoSupportedFrameRateRanges {
                        if range.maxFrameRate >= targetFPS && resolution > bestResolution {
                            bestFormat = format
                            bestFrameRateRange = range
                            bestResolution = resolution
                        }
                    }
                }
            }

            if let format = bestFormat, let range = bestFrameRateRange {
                device.activeFormat = format
                let actualFPS = min(targetFPS, range.maxFrameRate)
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(actualFPS))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(actualFPS))

                if device.isLowLightBoostSupported {
                    device.automaticallyEnablesLowLightBoostWhenAvailable = true
                }
            }

            device.unlockForConfiguration()
        } catch {
            AppLogger.camera.error("Failed to configure device format: \(error.localizedDescription)")
        }
    }
}
