//
//  PhotosSaveService.swift
//  golf-sync-swing
//
//  Saves trimmed swing clips to the Photos library via PHAssetChangeRequest.
//  No internal database. The Photos app is the library.
//

import AVFoundation
import Photos
import os

protocol PhotosSaving: Sendable {
    func saveClip(from sourceURL: URL, startTime: TimeInterval, endTime: TimeInterval) async throws
    func saveFullRecording(from sourceURL: URL) async throws
    static func requestAuthorization() async -> Bool
}

struct PhotosSaveService: PhotosSaving {

    static func requestAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard status != .authorized else { return true }
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return newStatus == .authorized
    }

    func saveClip(from sourceURL: URL, startTime: TimeInterval, endTime: TimeInterval) async throws {
        AppLogger.photos.info("saveClip begin url=\(sourceURL.lastPathComponent, privacy: .public) start=\(String(format: "%.3f", startTime), privacy: .public) end=\(String(format: "%.3f", endTime), privacy: .public)")

        let asset = AVURLAsset(url: sourceURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let composition = AVMutableComposition()

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
              let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw PhotosSaveError.exportFailed("No video track found")
        }

        // Clamp the requested range against the asset's actual duration. The
        // detection pipeline computes endTime = impactTime + 1.0 with no bounds
        // check — if the user stops recording shortly after a swing, endTime
        // can land past EOF and AVAssetExportSession stalls forever seeking
        // beyond the file end.
        let assetDuration = try await asset.load(.duration)
        let durationSeconds = max(0, CMTimeGetSeconds(assetDuration))
        let clampedStart = max(0, min(startTime, durationSeconds))
        let clampedEnd = max(clampedStart, min(endTime, durationSeconds))
        let timeRange = CMTimeRange(
            start: CMTime(seconds: clampedStart, preferredTimescale: 600),
            end: CMTime(seconds: clampedEnd, preferredTimescale: 600)
        )

        try compositionTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        compositionTrack.preferredTransform = preferredTransform

        AppLogger.photos.info("saveClip preflight duration=\(String(format: "%.3f", durationSeconds), privacy: .public) clampedStart=\(String(format: "%.3f", clampedStart), privacy: .public) clampedEnd=\(String(format: "%.3f", clampedEnd), privacy: .public) transform=[\(String(format: "%.2f", preferredTransform.a), privacy: .public) \(String(format: "%.2f", preferredTransform.b), privacy: .public) \(String(format: "%.2f", preferredTransform.c), privacy: .public) \(String(format: "%.2f", preferredTransform.d), privacy: .public) \(String(format: "%.2f", preferredTransform.tx), privacy: .public) \(String(format: "%.2f", preferredTransform.ty), privacy: .public)]")

        // Add audio if available
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audioCompositionTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        // Passthrough copies the source bitstream without re-encoding —
        // ~10–40× faster than HighestQuality. We briefly switched to
        // HighestQuality as insurance against a suspected HEVC-fragmented-
        // passthrough stall, but device logs proved the clamp above was the
        // real fix (export end status=3 / progress=1.0 / error=nil with no
        // stall). If the hang ever returns the four os_log checkpoints will
        // show "export begin" with no matching "export end" — at that point
        // we'd know Passthrough is the culprit and switch the preset back.
        let preset = AVAssetExportPresetPassthrough
        guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw PhotosSaveError.exportFailed("Cannot create export session")
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mov

        AppLogger.photos.info("export begin preset=\(preset, privacy: .public) rangeStart=\(String(format: "%.3f", clampedStart), privacy: .public) rangeEnd=\(String(format: "%.3f", clampedEnd), privacy: .public) output=\(outputURL.lastPathComponent, privacy: .public)")

        await exporter.export()

        AppLogger.photos.info("export end status=\(exporter.status.rawValue) progress=\(String(format: "%.3f", exporter.progress), privacy: .public) error=\(exporter.error?.localizedDescription ?? "nil", privacy: .public)")

        guard exporter.status == .completed else {
            throw PhotosSaveError.exportFailed(exporter.error?.localizedDescription ?? "Unknown error")
        }

        try await saveToPhotos(url: outputURL)

        AppLogger.detection.info("Saved trimmed clip to Photos (\(String(format: "%.1f", clampedStart))-\(String(format: "%.1f", clampedEnd))s)")
    }

    func saveFullRecording(from sourceURL: URL) async throws {
        try await saveToPhotos(url: sourceURL)
        AppLogger.detection.info("Saved full recording to Photos")
    }

    private func saveToPhotos(url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

enum PhotosSaveError: LocalizedError {
    case exportFailed(String)
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .exportFailed(let reason):
            return String(localized: "Export failed: \(reason)", comment: "PhotosSaveError: AVAssetExportSession failure — placeholder is the underlying reason")
        case .authorizationDenied:
            return String(localized: "Photos access denied. Please enable in Settings.", comment: "PhotosSaveError: user has denied Photos write permission")
        }
    }
}
