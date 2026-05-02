//
//  VideoExportService.swift
//  golf-sync-swing
//

import Foundation
import AVFoundation
import UIKit
import Photos
import os

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
        let asset1 = AVURLAsset(url: video1URL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let asset2 = AVURLAsset(url: video2URL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

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
            do {
                try compositionAudioTrack1.insertTimeRange(timeRange1, of: audioTrack1, at: video1StartTime)
            } catch {
                AppLogger.storage.warning("Export: failed to add audio: \(error.localizedDescription)")
            }
        }

        if let audioTrack2 = try await asset2.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack2 = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            do {
                try compositionAudioTrack2.insertTimeRange(timeRange2, of: audioTrack2, at: video2StartTime)
            } catch {
                AppLogger.storage.warning("Export: failed to add audio: \(error.localizedDescription)")
            }
        }

        // Create video composition using the new API
        let renderSize = config.resolution
        let cellHeight = renderSize.height / 2

        let videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
        videoComposition.renderSize = renderSize
        let frameRate1 = try await track1.load(.nominalFrameRate)
        let frameRate2 = try await track2.load(.nominalFrameRate)
        let maxFrameRate = max(frameRate1, frameRate2, 30)
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(maxFrameRate))

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
        var exportSucceeded = false
        defer {
            if !exportSucceeded {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

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
            exportSucceeded = true
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

    /// Save video to Photos library, cleaning up the temp file on success.
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
                if success {
                    try? FileManager.default.removeItem(at: url)
                }
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

    /// Remove orphaned export files from the temp directory.
    /// Called at app launch to reclaim disk space.
    static func cleanupOrphanedExports() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil
        ) else { return }

        let exports = contents.filter { $0.lastPathComponent.hasPrefix("export_") && $0.pathExtension == "mp4" }
        for file in exports {
            try? FileManager.default.removeItem(at: file)
        }

        guard !exports.isEmpty else { return }
        AppLogger.storage.info("Cleaned up \(exports.count) orphaned export(s)")
    }

    // MARK: - Layout-config export (new)

    /// Export with explicit per-video transforms and an aspect-ratio-driven render size.
    /// When `swingTrim` is provided (`(swing1, swing2)`), each video is trimmed to its
    /// SwingTimeRange before composition; otherwise full clips are exported.
    static func exportComparison(
        layoutConfig: VideoLayoutConfig,
        video1URL: URL,
        video2URL: URL,
        syncOffset: TimeInterval,
        swingTrim: (SwingTimeRange, SwingTimeRange)? = nil,
        progress: @escaping (Float) -> Void,
        completion: @escaping (Result<URL, ExportError>) -> Void
    ) {
        Task {
            do {
                let outputURL = try await performLayoutExport(
                    layoutConfig: layoutConfig,
                    video1URL: video1URL,
                    video2URL: video2URL,
                    syncOffset: syncOffset,
                    swingTrim: swingTrim,
                    progress: progress
                )
                await MainActor.run { completion(.success(outputURL)) }
            } catch let error as ExportError {
                await MainActor.run { completion(.failure(error)) }
            } catch {
                await MainActor.run { completion(.failure(.exportFailed(error.localizedDescription))) }
            }
        }
    }

    private static func performLayoutExport(
        layoutConfig: VideoLayoutConfig,
        video1URL: URL,
        video2URL: URL,
        syncOffset: TimeInterval,
        swingTrim: (SwingTimeRange, SwingTimeRange)?,
        progress: @escaping (Float) -> Void
    ) async throws -> URL {
        let asset1 = AVURLAsset(url: video1URL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let asset2 = AVURLAsset(url: video2URL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        guard let track1 = try await asset1.loadTracks(withMediaType: .video).first,
              let track2 = try await asset2.loadTracks(withMediaType: .video).first else {
            throw ExportError.missingVideoTrack
        }

        let fullDuration1 = try await asset1.load(.duration)
        let fullDuration2 = try await asset2.load(.duration)

        // Compute per-video source slice (start + duration) — either the swing range or the full clip.
        let slice1 = sliceFor(swing: swingTrim?.0, fullDuration: fullDuration1)
        let slice2 = sliceFor(swing: swingTrim?.1, fullDuration: fullDuration2)

        // When trimming, slices have new timelines starting at zero, so the
        // absolute-time syncOffset (= s1.contactTime - s2.contactTime) is wrong.
        // Convert it to slice-relative: (s1.contact - s1.start) - (s2.contact - s2.start).
        let effectiveSync = effectiveSyncOffset(
            originalSyncOffset: syncOffset, swingTrim: swingTrim
        )

        let (v1Start, v2Start, effectiveDuration) = applySyncOffset(
            syncOffset: effectiveSync, duration1: slice1.duration, duration2: slice2.duration
        )

        let composition = AVMutableComposition()
        guard let track1c = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let track2c = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.missingVideoTrack
        }
        // For sequential mode, track2 plays AFTER track1 (back-to-back).
        // For sideBySide / stacked, both tracks play in parallel from their offsets.
        let track1InsertAt: CMTime
        let track2InsertAt: CMTime
        if layoutConfig.mode == .sequential {
            track1InsertAt = .zero
            track2InsertAt = slice1.duration
        } else {
            track1InsertAt = v1Start
            track2InsertAt = v2Start
        }

        try track1c.insertTimeRange(CMTimeRange(start: slice1.start, duration: slice1.duration), of: track1, at: track1InsertAt)
        try track2c.insertTimeRange(CMTimeRange(start: slice2.start, duration: slice2.duration), of: track2, at: track2InsertAt)

        // Audio per isMuted flag, also trimmed when applicable
        if !layoutConfig.transforms[0].isMuted,
           let audio1 = try await asset1.loadTracks(withMediaType: .audio).first,
           let audio1c = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audio1c.insertTimeRange(CMTimeRange(start: slice1.start, duration: slice1.duration), of: audio1, at: track1InsertAt)
        }
        if !layoutConfig.transforms[1].isMuted,
           let audio2 = try await asset2.loadTracks(withMediaType: .audio).first,
           let audio2c = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audio2c.insertTimeRange(CMTimeRange(start: slice2.start, duration: slice2.duration), of: audio2, at: track2InsertAt)
        }

        let renderSize = layoutConfig.aspectRatio.exportSize
        let cells = cellRects(for: layoutConfig.aspectRatio)
        let size1 = try await track1.load(.naturalSize)
        let pref1 = try await track1.load(.preferredTransform)
        let size2 = try await track2.load(.naturalSize)
        let pref2 = try await track2.load(.preferredTransform)
        let frameRate1 = try await track1.load(.nominalFrameRate)
        let frameRate2 = try await track2.load(.nominalFrameRate)
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(frameRate1, frameRate2, 30)))

        let videoComposition: AVMutableVideoComposition

        switch layoutConfig.mode {
        case .sequential:
            // Tracks are already inserted back-to-back; standard composition handles
            // single-track-at-a-time playback automatically (no overlap, no per-cell crop).
            videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
            videoComposition.renderSize = renderSize
            videoComposition.frameDuration = frameDuration

        case .sideBySide, .stacked:
            // For stacked, both cells share the full canvas; for sideBySide each takes its half.
            let cellRectsForLayout: [CGRect] = (layoutConfig.mode == .stacked)
                ? [CGRect(origin: .zero, size: renderSize), CGRect(origin: .zero, size: renderSize)]
                : cells

            let cellConfigs: [CellConfiguration] = [
                CellConfiguration(
                    cellRect: cellRectsForLayout[0], videoTrackID: track1c.trackID,
                    naturalSize: size1, preferredTransform: pref1,
                    userScale: layoutConfig.transforms[0].scale,
                    userOffset: layoutConfig.transforms[0].offset,
                    containerSize: layoutConfig.transforms[0].containerSize
                ),
                CellConfiguration(
                    cellRect: cellRectsForLayout[1], videoTrackID: track2c.trackID,
                    naturalSize: size2, preferredTransform: pref2,
                    userScale: layoutConfig.transforms[1].scale,
                    userOffset: layoutConfig.transforms[1].offset,
                    containerSize: layoutConfig.transforms[1].containerSize
                )
            ]
            let compositorLayout: CompositorLayout = (layoutConfig.mode == .stacked)
                ? .stacked(opacity: layoutConfig.stackedOpacity ?? 0.5)
                : .sideBySide
            CollageVideoCompositor.configureShared(cells: cellConfigs, layout: compositorLayout)

            videoComposition = AVMutableVideoComposition()
            videoComposition.customVideoCompositorClass = CollageVideoCompositor.self
            videoComposition.renderSize = renderSize
            videoComposition.frameDuration = frameDuration

            let layer1 = AVMutableVideoCompositionLayerInstruction(assetTrack: track1c)
            let layer2 = AVMutableVideoCompositionLayerInstruction(assetTrack: track2c)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: effectiveDuration)
            instruction.backgroundColor = UIColor.black.cgColor
            instruction.layerInstructions = [layer1, layer2]
            videoComposition.instructions = [instruction]
        }

        return try await runExport(composition: composition, videoComposition: videoComposition, progress: progress)
    }

    /// When the export trims each video to its swing range, the `syncOffset`
    /// passed in (absolute = `s1.contactTime - s2.contactTime`) no longer aligns
    /// the contact frames in the new slice-local timelines. This converts it.
    /// When NOT trimming, the original offset is correct.
    static func effectiveSyncOffset(
        originalSyncOffset: TimeInterval,
        swingTrim: (SwingTimeRange, SwingTimeRange)?
    ) -> TimeInterval {
        guard let trim = swingTrim else { return originalSyncOffset }
        let s1ContactInSlice = trim.0.contactTime - trim.0.startTime
        let s2ContactInSlice = trim.1.contactTime - trim.1.startTime
        return s1ContactInSlice - s2ContactInSlice
    }

    /// Returns (start, duration) in source-asset time. With a SwingTimeRange we
    /// clamp to [0, fullDuration] to defend against stale ranges; otherwise we
    /// return the entire asset.
    private static func sliceFor(swing: SwingTimeRange?, fullDuration: CMTime) -> (start: CMTime, duration: CMTime) {
        guard let swing else { return (.zero, fullDuration) }
        let fullSeconds = max(0, fullDuration.seconds)
        let startSec = min(max(0, swing.startTime), fullSeconds)
        let endSec = min(max(startSec, swing.endTime), fullSeconds)
        let start = CMTime(seconds: startSec, preferredTimescale: 600)
        let duration = CMTime(seconds: endSec - startSec, preferredTimescale: 600)
        return (start, duration)
    }

    /// Splits the export render canvas in half along the arrangement axis.
    private static func cellRects(for aspectRatio: ExportAspectRatio) -> [CGRect] {
        let size = aspectRatio.exportSize
        switch aspectRatio.arrangement {
        case .horizontal:
            let halfW = size.width / 2
            return [
                CGRect(x: 0,     y: 0, width: halfW, height: size.height),
                CGRect(x: halfW, y: 0, width: halfW, height: size.height)
            ]
        case .vertical:
            let halfH = size.height / 2
            return [
                CGRect(x: 0, y: 0,     width: size.width, height: halfH),
                CGRect(x: 0, y: halfH, width: size.width, height: halfH)
            ]
        }
    }

    private static func applySyncOffset(
        syncOffset: TimeInterval, duration1: CMTime, duration2: CMTime
    ) -> (v1Start: CMTime, v2Start: CMTime, effective: CMTime) {
        if syncOffset >= 0 {
            let v2 = CMTime(seconds: syncOffset, preferredTimescale: 600)
            return (.zero, v2, CMTimeMaximum(duration1, CMTimeAdd(v2, duration2)))
        } else {
            let v1 = CMTime(seconds: -syncOffset, preferredTimescale: 600)
            return (v1, .zero, CMTimeMaximum(CMTimeAdd(v1, duration1), duration2))
        }
    }

    private static func runExport(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        progress: @escaping (Float) -> Void
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_\(UUID().uuidString).mp4")
        var exportSucceeded = false
        defer {
            if !exportSucceeded { try? FileManager.default.removeItem(at: outputURL) }
        }

        var session: AVAssetExportSession?
        for preset in [AVAssetExportPreset1920x1080, AVAssetExportPresetHighestQuality, AVAssetExportPresetMediumQuality] {
            if let s = AVAssetExportSession(asset: composition, presetName: preset) {
                session = s
                break
            }
        }
        guard let exportSession = session else {
            throw ExportError.exportFailed("Could not create export session")
        }

        exportSession.videoComposition = videoComposition
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        let progressTask = Task {
            while !Task.isCancelled {
                await MainActor.run { progress(exportSession.progress) }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        await exportSession.export()
        progressTask.cancel()

        if exportSession.status == .completed {
            exportSucceeded = true
            return outputURL
        }
        let msg = exportSession.error?.localizedDescription ?? "Unknown error (status: \(exportSession.status.rawValue))"
        throw ExportError.exportFailed(msg)
    }
}
