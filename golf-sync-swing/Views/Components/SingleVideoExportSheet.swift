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
        VStack(spacing: 16) {
            handle
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .presentationDetents([.fraction(0.5)])
        .presentationBackground(Color(.systemBackground))
        .presentationDragIndicator(.hidden)
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
    }

    private var idleContent: some View {
        VStack(spacing: 16) {
            selectionPicker

            Image(systemName: "square.and.arrow.up.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.appTeal)

            VStack(spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            Button(action: startExport) {
                Text("Export to Photos")
                    .font(.headline).fontWeight(.bold).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(canExport ? Color.appTeal : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
            }
            .disabled(!canExport)
            .padding(.top, 4)
        }
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
        .tint(Color.appTeal)
        .padding(.top, 32)
    }

    private var successContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Saved to Photos").font(.headline)
            Button("Done", action: onDismiss).buttonStyle(.borderedProminent)
        }
        .padding(.top, 16)
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Export Failed").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Close", action: onDismiss).buttonStyle(.bordered)
        }
        .padding(.top, 8)
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
