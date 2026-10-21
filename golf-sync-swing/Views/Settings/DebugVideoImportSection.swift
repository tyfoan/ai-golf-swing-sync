//
//  DebugVideoImportSection.swift
//  golf-sync-swing
//
//  DEBUG-only Settings section: pick a library video and run the live swing
//  detector on it. The only way to get swings into the simulator, which has no
//  camera. Compiled out of release builds.
//

#if DEBUG

import SwiftData
import SwiftUI

struct DebugVideoImportSection: View {

    @Environment(\.modelContext) private var modelContext

    @State private var isPickerPresented = false
    @State private var isImporting = false
    @State private var status = "No video imported yet"

    var body: some View {
        Section {
            importButton
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("debugImport.status")
        } header: {
            Label("Debug Import", systemImage: "film.stack")
        } footer: {
            Text("Runs every frame of the file through the camera's swing detector. Markers come only from detection.")
        }
        .sheet(isPresented: $isPickerPresented) {
            VideoPickerView(isPresented: $isPickerPresented) { url in
                Task { await importVideo(at: url) }
            }
        }
    }

    private var importButton: some View {
        Button {
            isPickerPresented = true
        } label: {
            Label("Import Video and Detect Swings", systemImage: "square.and.arrow.down")
        }
        .disabled(isImporting)
        .accessibilityIdentifier("debugImport.button")
    }

    private func importVideo(at url: URL) async {
        isImporting = true
        status = "Detecting swings…"
        defer { isImporting = false }
        do {
            let report = try await DebugVideoImporter().importVideo(from: url, into: modelContext)
            status = Self.summary(of: report)
        } catch {
            status = "Import failed: \(error.localizedDescription)"
        }
    }

    private static func summary(of report: VideoFileSwingDetector.Report) -> String {
        let poses = "pose found in \(report.framesWithPose) of \(report.framesAnalysed) frames"
        return report.clips.isEmpty
            ? "No swing detected (\(poses)), saved without markers"
            : "Swings detected: \(report.clips.count) (\(poses))"
    }
}

#endif
