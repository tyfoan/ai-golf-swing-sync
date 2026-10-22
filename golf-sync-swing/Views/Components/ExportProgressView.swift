//
//  ExportProgressView.swift
//  golf-sync-swing
//

import SwiftUI

struct ExportProgressView: View {
    let video1URL: URL
    let video2URL: URL
    let syncOffset: TimeInterval
    let layoutConfig: VideoLayoutConfig?
    let swingTrim: (SwingTimeRange, SwingTimeRange)?
    @Binding var isExporting: Bool
    @Binding var progress: Float
    let onDismiss: () -> Void

    init(
        video1URL: URL,
        video2URL: URL,
        syncOffset: TimeInterval,
        layoutConfig: VideoLayoutConfig? = nil,
        swingTrim: (SwingTimeRange, SwingTimeRange)? = nil,
        isExporting: Binding<Bool>,
        progress: Binding<Float>,
        onDismiss: @escaping () -> Void
    ) {
        self.video1URL = video1URL
        self.video2URL = video2URL
        self.syncOffset = syncOffset
        self.layoutConfig = layoutConfig
        self.swingTrim = swingTrim
        self._isExporting = isExporting
        self._progress = progress
        self.onDismiss = onDismiss
    }

    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    @State private var showShareSheet = false
    @State private var savedToPhotos = false
    @State private var selectedQuality: ExportQuality = .defaultChoice
    @State private var showPaywall = false
    @State private var trimToSwing: Bool = true
    @State private var exportHandle: ExportHandle?

    var body: some View {
        NavigationStack {
            // Scrolls so the Export button stays reachable on a 4.7-inch screen,
            // where the quality rows and the trim toggle outgrow a half sheet.
            ScrollView {
                currentStage
                    .padding()
            }
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
        .presentationDetents([.medium, .large])
        .fullScreenCover(isPresented: $showPaywall) {
            AppPaywallView(source: .featureGate, onDismiss: { showPaywall = false })
        }
        .onDisappear { exportHandle?.cancel() }
    }
}

// MARK: - Stage Router

private extension ExportProgressView {
    @ViewBuilder
    var currentStage: some View {
        if isExporting {
            exportingView
        } else if let error = errorMessage {
            errorView(error)
        } else if exportedURL != nil {
            successView
        } else {
            preExportView
        }
    }
}

// MARK: - Pre-Export

private extension ExportProgressView {
    var preExportView: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(headlineText)
                .font(.headline)
                .multilineTextAlignment(.center)

            ExportQualityPicker(
                selection: $selectedQuality,
                renderSize: renderSize(for:),
                onLockedTap: showLockedQualityPaywall
            )

            if swingTrim != nil {
                trimToggle
            }

            exportButton
        }
    }

    var trimToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $trimToSwing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trimToSwing ? "Trim to swing" : "Export full clips")
                        .font(.subheadline.weight(.semibold))
                    Text(trimToSwing
                         ? "Only the detected swing window from each video"
                         : "The full recorded clips, end to end")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    var headlineText: String {
        guard let config = layoutConfig else {
            return String(localized: "Export side-by-side comparison video", comment: "Export sheet headline for the legacy stacked comparison export")
        }
        let dimensions = ExportQuality.dimensions(of: renderSize(for: effectiveQuality))
        return [config.aspectRatio.displayName, dimensions].joined(separator: " · ")
    }

    /// The quality the export will actually render at. UI guards keep locked
    /// tiers unselectable, but the render path must never trust view state
    /// for entitlements — premium tiers fall back to .standard when locked.
    var effectiveQuality: ExportQuality {
        guard selectedQuality.requiresPremium else { return selectedQuality }
        return FeatureAccess.isUnlocked(.exportHD) ? selectedQuality : .standard
    }

    func renderSize(for quality: ExportQuality) -> CGSize {
        guard let config = layoutConfig else { return quality.resolution }
        return quality.renderSize(for: config.aspectRatio.exportSize)
    }

    func showLockedQualityPaywall() {
        Analytics.shared.track(.featureGateHit(feature: .exportHD))
        showPaywall = true
    }

    var exportButton: some View {
        Button { startExport() } label: {
            Text("Export Video")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.fairwayGreen)
                .foregroundStyle(.white)
                .cornerRadius(12)
        }
    }
}

// MARK: - Exporting

private extension ExportProgressView {
    var exportingView: some View {
        OperationProgressView(
            title: String(localized: "Exporting… \(Int(progress * 100))%", comment: "Export progress title with percent complete (0–100)"),
            subtitle: String(localized: "This may take a moment", comment: "Subtitle under the export progress bar"),
            progress: Double(progress)
        )
        .tint(Color.fairwayGreen)
    }
}

// MARK: - Error

private extension ExportProgressView {
    func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text("Export Failed").font(.headline)

            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
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
}

// MARK: - Success

private extension ExportProgressView {
    var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: savedToPhotos ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 60))
                .foregroundStyle(Color.fairwayGreen)

            Text(savedToPhotos ? "Saved to Photos" : "Export Complete")
                .font(.headline)

            if !savedToPhotos {
                saveToPhotosButton
                shareButton
            }

            Button { onDismiss() } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity).padding()
                    .background(savedToPhotos ? Color.fairwayGreen : Color.secondary.opacity(0.2))
                    .foregroundStyle(savedToPhotos ? .white : .primary)
                    .cornerRadius(12)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL { ShareSheet(items: [url]) }
        }
    }

    var saveToPhotosButton: some View {
        Button { saveToPhotos() } label: {
            Label("Save to Photos", systemImage: "photo.on.rectangle")
                .font(.headline)
                .frame(maxWidth: .infinity).padding()
                .background(Color.fairwayGreen)
                .foregroundStyle(.white).cornerRadius(12)
        }
    }

    var shareButton: some View {
        Button { showShareSheet = true } label: {
            Label("Share", systemImage: "square.and.arrow.up")
                .font(.headline)
                .frame(maxWidth: .infinity).padding()
                .background(Color.secondary.opacity(0.2))
                .foregroundStyle(.primary).cornerRadius(12)
        }
    }
}

// MARK: - Export Actions

private extension ExportProgressView {
    func startExport() {
        isExporting = true
        progress = 0
        errorMessage = nil
        let quality = effectiveQuality
        Analytics.shared.track(.exportStarted(
            aspectRatio: layoutConfig?.aspectRatio,
            quality: quality.rawValue
        ))
        exportHandle = makeExportHandle(quality: quality)
    }

    func makeExportHandle(quality: ExportQuality) -> ExportHandle {
        if let config = layoutConfig {
            return VideoExportService.exportComparison(
                layoutConfig: config,
                video1URL: video1URL,
                video2URL: video2URL,
                syncOffset: syncOffset,
                swingTrim: trimToSwing ? swingTrim : nil,
                renderSize: quality.renderSize(for: config.aspectRatio.exportSize),
                progress: { p in Task { @MainActor in progress = p } },
                completion: handleExportResult
            )
        }
        return VideoExportService.exportComparison(
            video1URL: video1URL,
            video2URL: video2URL,
            syncOffset: syncOffset,
            config: VideoExportService.ExportConfiguration(resolution: quality.resolution),
            progress: { p in Task { @MainActor in progress = p } },
            completion: handleExportResult
        )
    }

    func handleExportResult(_ result: Result<URL, VideoExportService.ExportError>) {
        isExporting = false
        exportHandle = nil
        switch result {
        case .success(let url):
            exportedURL = url
            Analytics.shared.track(.exportCompleted(
                aspectRatio: layoutConfig?.aspectRatio,
                isHD: effectiveQuality.requiresPremium
            ))
        case .failure(.cancelled):
            // Cancel path: the view's Cancel button already triggered
            // onDismiss before this completion arrived. Nothing to do.
            break
        case .failure(let error):
            Analytics.shared.track(.exportFailed(
                aspectRatio: layoutConfig?.aspectRatio,
                reason: String(describing: error)
            ))
            errorMessage = error.localizedDescription
        }
    }

    func saveToPhotos() {
        guard let url = exportedURL else { return }
        VideoExportService.saveToPhotos(url: url) { result in
            switch result {
            case .success: savedToPhotos = true
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }
}
