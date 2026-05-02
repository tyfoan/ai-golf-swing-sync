//
//  SingleVideoExportSheet.swift
//  golf-sync-swing
//
//  Bottom sheet for exporting a single source video to Photos.
//  No editor, no aspect picker — saves in source aspect.
//

import SwiftUI
import Photos

struct SingleVideoExportSheet: View {
    let video: SwingVideo
    let mode: VideoPlaybackMode
    let onDismiss: () -> Void

    @State private var isExporting = false
    @State private var progress: Float = 0
    @State private var errorMessage: String?
    @State private var savedConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            handle
            content
        }
        .padding(20)
        .background(Color(.systemBackground))
        .presentationDetents([.fraction(0.42)])
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            errorContent(errorMessage)
        } else if savedConfirmation {
            successContent
        } else if isExporting {
            progressContent
        } else {
            idleContent
        }
    }

    private var handle: some View {
        Capsule()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 36, height: 4)
            .padding(.top, 4)
    }

    private var idleContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.up.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.appTeal)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: startExport) {
                Text("Export to Photos")
                    .font(.headline).fontWeight(.bold).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(canExport ? Color.appTeal : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .disabled(!canExport)
        }
    }

    private var progressContent: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress).tint(Color.appTeal)
            Text("\(Int(progress * 100))% — Exporting…").font(.caption)
        }
    }

    private var successContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Saved to Photos").font(.headline)
            Button("Done", action: onDismiss).buttonStyle(.borderedProminent)
        }
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Export failed").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Button("Close", action: onDismiss).buttonStyle(.bordered)
        }
    }

    private var title: String {
        mode == .swingsOnly ? "Export Swings Only" : "Export Full Video"
    }

    private var subtitle: String {
        switch mode {
        case .swingsOnly:
            let count = video.swings.count
            let totalSeconds = video.swings.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
            let s = String(format: "%.1f", totalSeconds)
            return "\(count) swing\(count == 1 ? "" : "s") · ~\(s) seconds total"
        case .fullVideo:
            let m = Int(video.duration) / 60
            let s = Int(video.duration) % 60
            return String(format: "Duration: %d:%02d", m, s)
        }
    }

    private var canExport: Bool {
        if mode == .swingsOnly { return !video.swings.isEmpty }
        return true
    }

    private func startExport() {
        guard let url = video.validLocalURL else {
            errorMessage = "Video file unavailable"
            return
        }
        let swings: [SwingTimeRange]? = (mode == .swingsOnly)
            ? video.swings.map { SwingTimeRange(startTime: $0.startTime, contactTime: $0.contactTime, endTime: $0.endTime) }
            : nil
        isExporting = true
        VideoExportService.exportSingleVideo(
            videoURL: url, swings: swings,
            progress: { p in Task { @MainActor in progress = p } },
            completion: { result in
                isExporting = false
                switch result {
                case .success(let outputURL):
                    saveToPhotos(url: outputURL)
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        )
    }

    private func saveToPhotos(url: URL) {
        VideoExportService.saveToPhotos(url: url) { result in
            switch result {
            case .success:
                savedConfirmation = true
            case .failure(let err):
                errorMessage = err.localizedDescription
            }
        }
    }
}
