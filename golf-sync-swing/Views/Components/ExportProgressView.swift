//
//  ExportProgressView.swift
//  golf-sync-swing
//

import SwiftUI

struct ExportProgressView: View {
    let viewModel: ComparisonViewModel
    @Binding var isExporting: Bool
    @Binding var progress: Float
    let onDismiss: () -> Void

    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    @State private var showShareSheet = false
    @State private var savedToPhotos = false
    @State private var selectedQuality: ExportQuality = .standard
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                currentStage
            }
            .padding()
            .navigationTitle("Export Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .disabled(isExporting)
                }
            }
        }
        .presentationDetents([.medium])
        .fullScreenCover(isPresented: $showPaywall) {
            AppPaywallView(source: .featureGate, onDismiss: { showPaywall = false })
        }
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
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Export side-by-side comparison video")
                .font(.headline)
                .multilineTextAlignment(.center)

            qualityPicker

            exportButton
        }
    }

    var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quality").font(.subheadline).foregroundStyle(.secondary)
            ForEach(ExportQuality.allCases) { quality in
                qualityRow(quality)
            }
        }
    }

    func qualityRow(_ quality: ExportQuality) -> some View {
        let locked = quality.requiresPremium && !FeatureAccess.isUnlocked(.exportHD)
        return Button {
            guard !locked else {
                showPaywall = true
                return
            }
            selectedQuality = quality
        } label: {
            HStack {
                Image(systemName: selectedQuality == quality ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedQuality == quality ? Color.fairwayGreen : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(quality.label)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundStyle(locked ? .secondary : .primary)
                    Text(quality.detail)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 12)
            .background(
                selectedQuality == quality
                    ? Color.fairwayGreen.opacity(0.1)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(locked)
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
        VStack(spacing: 16) {
            ProgressView(value: Double(progress))
                .progressViewStyle(.linear)

            Text("Exporting... \(Int(progress * 100))%")
                .font(.headline)

            Text("This may take a moment")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
        guard let url1 = viewModel.video1.validLocalURL,
              let url2 = viewModel.video2.validLocalURL else {
            errorMessage = "One or both video files are missing. Please re-import the videos."
            return
        }

        isExporting = true
        progress = 0
        errorMessage = nil

        let config = VideoExportService.ExportConfiguration(
            resolution: selectedQuality.resolution
        )

        VideoExportService.exportComparison(
            video1URL: url1,
            video2URL: url2,
            syncOffset: viewModel.syncOffset,
            config: config,
            progress: { p in Task { @MainActor in progress = p } },
            completion: { result in
                isExporting = false
                switch result {
                case .success(let url): exportedURL = url
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
        )
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

// MARK: - Export Quality

enum ExportQuality: String, CaseIterable, Identifiable {
    case standard
    case high
    case ultra

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .high:     return "HD"
        case .ultra:    return "Full HD"
        }
    }

    var detail: String {
        switch self {
        case .standard: return "720 x 1280 - Smaller file"
        case .high:     return "1080 x 1920 - Recommended"
        case .ultra:    return "1440 x 2560 - Best quality"
        }
    }

    var resolution: CGSize {
        switch self {
        case .standard: return CGSize(width: 720, height: 1280)
        case .high:     return CGSize(width: 1080, height: 1920)
        case .ultra:    return CGSize(width: 1440, height: 2560)
        }
    }

    var requiresPremium: Bool {
        switch self {
        case .standard: return false
        case .high:     return true
        case .ultra:    return true
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
