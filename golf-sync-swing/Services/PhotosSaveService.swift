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
        let asset = AVURLAsset(url: sourceURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let composition = AVMutableComposition()

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
              let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw PhotosSaveError.exportFailed("No video track found")
        }

        let timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )

        try compositionTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        compositionTrack.preferredTransform = try await videoTrack.load(.preferredTransform)

        // Add audio if available
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audioCompositionTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        // Passthrough preset copies the source video bitstream without re-encoding,
        // which is dramatically faster (near file-copy speed) than HighestQuality
        // for the trim+save flow. The source is already an h264 .mov from
        // AVCaptureMovieFileOutput, so re-encoding adds no quality and burns time.
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw PhotosSaveError.exportFailed("Cannot create export session")
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mov

        await exporter.export()

        guard exporter.status == .completed else {
            throw PhotosSaveError.exportFailed(exporter.error?.localizedDescription ?? "Unknown error")
        }

        try await saveToPhotos(url: outputURL)

        AppLogger.detection.info("Saved trimmed clip to Photos (\(String(format: "%.1f", startTime))-\(String(format: "%.1f", endTime))s)")
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
