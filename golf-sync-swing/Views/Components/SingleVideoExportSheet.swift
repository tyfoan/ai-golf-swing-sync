//
//  SingleVideoExportSheet.swift
//  golf-sync-swing
//
//  Bottom sheet for exporting a single source video to Photos.
//  Three targets: full video, all swings concatenated, or just the
//  currently-selected swing. No editor, no aspect picker.
//

import SwiftUI
import Photos

struct SingleVideoExportSheet: View {
    let video: SwingVideo
    let selectedSwing: SwingMarker?
    let onDismiss: () -> Void

    @State private var selection: ExportSelection
    @State private var isExporting = false
    @State private var progress: Float = 0
    @State private var errorMessage: String?
    @State private var savedConfirmation = false
    @State private var exportHandle: ExportHandle?

    init(video: SwingVideo, mode: VideoPlaybackMode, selectedSwing: SwingMarker?, onDismiss: @escaping () -> Void) {
        self.video = video
        self.selectedSwing = selectedSwing
        self.onDismiss = onDismiss
        _selection = State(initialValue: Self.defaultSelection(mode: mode, selectedSwing: selectedSwing, video: video))
    }

    enum ExportSelection: Hashable {
        case fullVideo, allSwings, currentSwing

        var label: String {
            switch self {
            case .fullVideo:    return String(localized: "Full Video")
            case .allSwings:    return String(localized: "All Swings")
            case .currentSwing: return String(localized: "This Swing")
            }
        }
    }

    private static func defaultSelection(mode: VideoPlaybackMode, selectedSwing: SwingMarker?, video: SwingVideo) -> ExportSelection {
        if selectedSwing != nil && mode == .swingsOnly { return .currentSwing }
        if mode == .swingsOnly && !video.swings.isEmpty { return .allSwings }
        return .fullVideo
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                content
            }
            .padding()
            .navigationTitle("Export Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        exportHandle?.cancel()
                        onDismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onDisappear { exportHandle?.cancel() }
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

    private var idleContent: some View {
        VStack(spacing: 20) {
            selectionPicker

            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            exportButton
        }
    }

    private var exportButton: some View {
        Button(action: startExport) {
            Text("Export to Photos")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(canExport ? Color.fairwayGreen : Color.gray)
                .foregroundStyle(.white)
                .cornerRadius(12)
        }
        .disabled(!canExport)
    }

    private var selectionPicker: some View {
        Picker("Export", selection: $selection) {
            Text(ExportSelection.fullVideo.label).tag(ExportSelection.fullVideo)
            if !video.swings.isEmpty {
                Text(ExportSelection.allSwings.label).tag(ExportSelection.allSwings)
            }
            if selectedSwing != nil {
                Text(ExportSelection.currentSwing.label).tag(ExportSelection.currentSwing)
            }
        }
        .pickerStyle(.segmented)
    }

    private var progressContent: some View {
        OperationProgressView(
            title: "Exporting… \(Int(progress * 100))%",
            subtitle: "This may take a moment",
            progress: Double(progress)
        )
        .tint(Color.fairwayGreen)
    }

    private var successContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.fairwayGreen)
            Text("Saved to Photos").font(.headline)
            Button { onDismiss() } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.fairwayGreen)
                    .foregroundStyle(.white).cornerRadius(12)
            }
        }
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            Text("Export Failed").font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { errorMessage = nil } label: {
                Text("Try Again")
                    .font(.headline)
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.fairwayGreen)
                    .foregroundStyle(.white).cornerRadius(12)
            }
        }
    }

    private var title: String {
        switch selection {
        case .fullVideo:    return String(localized: "Export Full Video")
        case .allSwings:    return String(localized: "Export All Swings")
        case .currentSwing: return String(localized: "Export This Swing")
        }
    }

    private var subtitle: String {
        switch selection {
        case .fullVideo:
            let minutes = Int(video.duration) / 60
            let seconds = Int(video.duration) % 60
            return String(localized: "Duration: \(minutes):\(String(format: "%02d", seconds))", comment: "Video duration in m:ss format")
        case .allSwings:
            let count = video.swings.count
            let total = video.swings.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
            let totalText = String(format: "%.1f", total)
            return String(localized: "^[\(count) swing](inflect: true) · ~\(totalText)s total", comment: "Swing-count summary on export sheet (inflected plural + total seconds)")
        case .currentSwing:
            guard let s = selectedSwing else { return "" }
            let seconds = String(format: "%.1f", s.endTime - s.startTime)
            return String(localized: "~\(seconds) seconds", comment: "Duration of selected swing in seconds")
        }
    }

    private var canExport: Bool {
        switch selection {
        case .fullVideo:    return true
        case .allSwings:    return !video.swings.isEmpty
        case .currentSwing: return selectedSwing != nil
        }
    }

    private func startExport() {
        guard let url = video.validLocalURL else {
            errorMessage = "Video file unavailable"
            return
        }
        let swings = swingRanges()
        isExporting = true
        exportHandle = VideoExportService.exportSingleVideo(
            videoURL: url, swings: swings,
            progress: { p in Task { @MainActor in progress = p } },
            completion: { result in
                isExporting = false
                exportHandle = nil
                switch result {
                case .success(let outputURL):
                    saveToPhotos(url: outputURL)
                case .failure(.cancelled):
                    // Cancel button already triggered onDismiss; nothing to do.
                    break
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        )
    }

    private func swingRanges() -> [SwingTimeRange]? {
        switch selection {
        case .fullVideo:
            return nil
        case .allSwings:
            return video.swings.map { SwingTimeRange(startTime: $0.startTime, contactTime: $0.contactTime, endTime: $0.endTime) }
        case .currentSwing:
            guard let s = selectedSwing else { return nil }
            return [SwingTimeRange(startTime: s.startTime, contactTime: s.contactTime, endTime: s.endTime)]
        }
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
