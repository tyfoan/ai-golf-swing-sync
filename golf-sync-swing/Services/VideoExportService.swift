//
//  VideoExportService.swift
//  golf-sync-swing
//

import Foundation
import AVFoundation
import UIKit
import Photos

final class VideoExportService {

    enum ExportError: LocalizedError {
        case missingVideoTrack
        case exportFailed(String)
        case photoLibraryAccessDenied

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack:
                return "Could not load video track"
            case .exportFailed(let message):
                return "Export failed: \(message)"
            case .photoLibraryAccessDenied:
                return "Photo library access denied"
            }
        }
    }

    struct ExportConfiguration {
        var resolution: CGSize = CGSize(width: 1080, height: 1920)
        var includeWatermark: Bool = false  // Disabled by default - can cause export issues
        var watermarkText: String = "Golf Sync Swing"
    }

    /// Export side-by-side comparison video
    static func exportComparison(
        video1URL: URL,
        video2URL: URL,
        syncOffset: TimeInterval,
        config: ExportConfiguration = ExportConfiguration(),
        progress: @escaping (Float) -> Void,
        completion: @escaping (Result<URL, ExportError>) -> Void
    ) {
        Task {
            do {
                let outputURL = try await performExport(
                    video1URL: video1URL,
                    video2URL: video2URL,
                    syncOffset: syncOffset,
                    config: config,
                    progress: progress
                )
                await MainActor.run {
                    completion(.success(outputURL))
                }
            } catch let error as ExportError {
                await MainActor.run {
                    completion(.failure(error))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(.exportFailed(error.localizedDescription)))
                }
            }
        }
    }

    private static func performExport(
        video1URL: URL,
        video2URL: URL,
        syncOffset: TimeInterval,
        config: ExportConfiguration,
        progress: @escaping (Float) -> Void
    ) async throws -> URL {
        let asset1 = AVAsset(url: video1URL)
        let asset2 = AVAsset(url: video2URL)

        // Load video tracks
        guard let track1 = try await asset1.loadTracks(withMediaType: .video).first,
              let track2 = try await asset2.loadTracks(withMediaType: .video).first else {
            throw ExportError.missingVideoTrack
        }

        let duration1 = try await asset1.load(.duration)
        let duration2 = try await asset2.load(.duration)

        // Apply sync offset - negative means video2 starts first
        let effectiveDuration: CMTime
        let video1StartTime: CMTime
        let video2StartTime: CMTime

        if syncOffset >= 0 {
            video1StartTime = .zero
            video2StartTime = CMTime(seconds: syncOffset, preferredTimescale: 600)
            effectiveDuration = CMTimeMaximum(duration1, CMTimeAdd(video2StartTime, duration2))
        } else {
            video1StartTime = CMTime(seconds: -syncOffset, preferredTimescale: 600)
            video2StartTime = .zero
            effectiveDuration = CMTimeMaximum(CMTimeAdd(video1StartTime, duration1), duration2)
        }

        let size1 = try await track1.load(.naturalSize)
        let transform1 = try await track1.load(.preferredTransform)
        let size2 = try await track2.load(.naturalSize)
        let transform2 = try await track2.load(.preferredTransform)

        // Create composition
        let composition = AVMutableComposition()

        guard let compositionTrack1 = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
              let compositionTrack2 = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw ExportError.missingVideoTrack
        }

        // Insert video tracks
        let timeRange1 = CMTimeRange(start: .zero, duration: duration1)
        try compositionTrack1.insertTimeRange(timeRange1, of: track1, at: video1StartTime)

        let timeRange2 = CMTimeRange(start: .zero, duration: duration2)
        try compositionTrack2.insertTimeRange(timeRange2, of: track2, at: video2StartTime)

        // Add audio tracks if available
        if let audioTrack1 = try await asset1.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack1 = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compositionAudioTrack1.insertTimeRange(timeRange1, of: audioTrack1, at: video1StartTime)
        }

        // Create video composition using the new API
        let renderSize = config.resolution
        let cellHeight = renderSize.height / 2

        let videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        // Create layer instructions
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: effectiveDuration)
        instruction.backgroundColor = UIColor.black.cgColor

        // Transform for video 1 (top)
        let layerInstruction1 = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack1)
        let transform1Final = calculateTransform(
            videoSize: size1,
            preferredTransform: transform1,
            cellRect: CGRect(x: 0, y: 0, width: renderSize.width, height: cellHeight)
        )
        layerInstruction1.setTransform(transform1Final, at: .zero)

        // Transform for video 2 (bottom)
        let layerInstruction2 = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack2)
        let transform2Final = calculateTransform(
            videoSize: size2,
            preferredTransform: transform2,
            cellRect: CGRect(x: 0, y: cellHeight, width: renderSize.width, height: cellHeight)
        )
        layerInstruction2.setTransform(transform2Final, at: .zero)

        instruction.layerInstructions = [layerInstruction1, layerInstruction2]
        videoComposition.instructions = [instruction]

        // Export
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_\(UUID().uuidString).mp4")

        // Try different presets if highest quality fails
        var exportSession: AVAssetExportSession?
        let presets = [AVAssetExportPreset1920x1080, AVAssetExportPresetHighestQuality, AVAssetExportPresetMediumQuality]

        for preset in presets {
            if let session = AVAssetExportSession(asset: composition, presetName: preset) {
                exportSession = session
                break
            }
        }

        guard let session = exportSession else {
            throw ExportError.exportFailed("Could not create export session")
        }

        session.videoComposition = videoComposition
        session.outputURL = outputURL
        session.outputFileType = .mp4

        // Monitor progress
        let progressTask = Task {
            while !Task.isCancelled {
                await MainActor.run {
                    progress(session.progress)
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }

        await session.export()
        progressTask.cancel()

        if session.status == .completed {
            return outputURL
        } else {
            let errorMessage = session.error?.localizedDescription ?? "Unknown error (status: \(session.status.rawValue))"
            throw ExportError.exportFailed(errorMessage)
        }
    }

    private static func calculateTransform(
        videoSize: CGSize,
        preferredTransform: CGAffineTransform,
        cellRect: CGRect
    ) -> CGAffineTransform {
        // Get display size after rotation
        let displaySize = videoSize.applying(preferredTransform)
        let videoWidth = abs(displaySize.width)
        let videoHeight = abs(displaySize.height)

        // Calculate aspect-fit scale
        let scaleX = cellRect.width / videoWidth
        let scaleY = cellRect.height / videoHeight
        let scale = min(scaleX, scaleY)

        // Build transform: rotate + scale + translate
        var rotationOnly = preferredTransform
        rotationOnly.tx = 0
        rotationOnly.ty = 0

        var transform = CGAffineTransform.identity
        transform = transform.concatenating(rotationOnly)
        transform = transform.scaledBy(x: scale, y: scale)

        // Calculate video's bounding box center after rotation+scale
        let corner1 = CGPoint.zero.applying(transform)
        let corner2 = CGPoint(x: videoSize.width, y: 0).applying(transform)
        let corner3 = CGPoint(x: videoSize.width, y: videoSize.height).applying(transform)
        let corner4 = CGPoint(x: 0, y: videoSize.height).applying(transform)

        let minX = min(corner1.x, corner2.x, corner3.x, corner4.x)
        let maxX = max(corner1.x, corner2.x, corner3.x, corner4.x)
        let minY = min(corner1.y, corner2.y, corner3.y, corner4.y)
        let maxY = max(corner1.y, corner2.y, corner3.y, corner4.y)

        let boundingCenterX = (minX + maxX) / 2
        let boundingCenterY = (minY + maxY) / 2

        // Move center to cell center
        let targetCenterX = cellRect.midX
        let targetCenterY = cellRect.midY

        transform.tx += targetCenterX - boundingCenterX
        transform.ty += targetCenterY - boundingCenterY

        return transform
    }

    /// Save video to Photos library
    static func saveToPhotos(url: URL, completion: @escaping (Result<Void, ExportError>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(.failure(.photoLibraryAccessDenied))
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        completion(.success(()))
                    } else {
                        completion(.failure(.exportFailed(error?.localizedDescription ?? "Save failed")))
                    }
                }
            }
        }
    }
}
