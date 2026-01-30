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

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
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
            .padding()
            .navigationTitle("Export Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .disabled(isExporting)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var preExportView: some View {
        VStack(spacing: 24) {
            Image(systemName: "film.stack")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Export side-by-side comparison video")
                .font(.headline)
                .multilineTextAlignment(.center)

            Button {
                startExport()
            } label: {
                Text("Export Video")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
        }
    }

    private var exportingView: some View {
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

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text("Export Failed")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                errorMessage = nil
            } label: {
                Text("Try Again")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
        }
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: savedToPhotos ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text(savedToPhotos ? "Saved to Photos" : "Export Complete")
                .font(.headline)

            if !savedToPhotos {
                Button {
                    saveToPhotos()
                } label: {
                    Label("Save to Photos", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }

                Button {
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.secondary.opacity(0.2))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }
            }

            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(savedToPhotos ? Color.accentColor : Color.secondary.opacity(0.2))
                    .foregroundStyle(savedToPhotos ? .white : .primary)
                    .cornerRadius(12)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func startExport() {
        isExporting = true
        progress = 0
        errorMessage = nil

        VideoExportService.exportComparison(
            video1URL: viewModel.video1.localURL,
            video2URL: viewModel.video2.localURL,
            syncOffset: viewModel.syncOffset,
            progress: { p in
                progress = p
            },
            completion: { result in
                isExporting = false
                switch result {
                case .success(let url):
                    exportedURL = url
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        )
    }

    private func saveToPhotos() {
        guard let url = exportedURL else { return }

        VideoExportService.saveToPhotos(url: url) { result in
            switch result {
            case .success:
                savedToPhotos = true
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
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
