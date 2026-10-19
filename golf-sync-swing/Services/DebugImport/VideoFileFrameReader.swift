//
//  VideoFileFrameReader.swift
//  golf-sync-swing
//
//  DEBUG-only. Decodes a video file one upright frame at a time, with each frame's
//  presentation time on the file's zero-based timeline.
//
//  Camera buffers reach the detector upright (the capture connection rotates them),
//  and Vision assumes upright input. A file stored upright is read in the capture
//  session's own pixel format (420f). A file that relies on a rotation transform,
//  such as a portrait iPhone recording, is read through a video composition that
//  applies that transform.
//

#if DEBUG

import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

final class VideoFileFrameReader {

    struct Frame {
        let pixelBuffer: CVPixelBuffer
        let time: TimeInterval
    }

    enum ReaderError: Error {
        case noVideoTrack
        case cannotStartReading
        case readingFailed
    }

    private let reader: AVAssetReader
    private let output: AVAssetReaderOutput

    init(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ReaderError.noVideoTrack
        }
        reader = try AVAssetReader(asset: asset)
        output = try await Self.uprightOutput(for: track, of: asset)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ReaderError.cannotStartReading }
    }

    /// The next decoded frame, or nil at the end of the file. A decoding failure throws
    /// rather than passing for the end of the video.
    func nextFrame() throws -> Frame? {
        while let sample = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            return Frame(pixelBuffer: pixelBuffer, time: time)
        }
        guard reader.status != .failed else { throw reader.error ?? ReaderError.readingFailed }
        return nil
    }

    private static func uprightOutput(for track: AVAssetTrack, of asset: AVAsset) async throws -> AVAssetReaderOutput {
        let transform = try await track.load(.preferredTransform)
        guard !transform.isIdentity else {
            return AVAssetReaderTrackOutput(track: track, outputSettings: pixelFormat(cameraPixelFormat))
        }
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: pixelFormat(kCVPixelFormatType_32BGRA))
        output.videoComposition = try await AVVideoComposition.videoComposition(withPropertiesOf: asset)
        return output
    }

    /// Matches CaptureSessionConfigurator's video data output.
    private static let cameraPixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange

    private static func pixelFormat(_ format: OSType) -> [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: format]
    }
}

#endif
