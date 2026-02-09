//
//  ComparisonView.swift
//  golf-sync-swing
//
//  Dark immersive side-by-side video comparison.
//  Default mode: independent swing loops (free).
//  Synced/Onion/Overlay modes require premium.
//

import SwiftUI

struct ComparisonView: View {
    let video1: SwingVideo
    let video2: SwingVideo
    let swing1: SwingTimeRange
    let swing2: SwingTimeRange

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ComparisonViewModel?
    @State private var showExportSheet = false
    @State private var exportProgress: Float = 0
    @State private var isExporting = false
    @State private var showDoneSheet = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let viewModel = viewModel {
                contentStack(viewModel: viewModel)
            } else {
                ProgressView().tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { onViewAppear() }
        .onDisappear { viewModel?.pause() }
        .sheet(isPresented: $showExportSheet) { exportSheet }
        .confirmationDialog("Done", isPresented: $showDoneSheet, titleVisibility: .hidden) {
            Button("Export Video") { showExportSheet = true }
            Button("Done") { dismiss() }
            Button("Cancel", role: .cancel) { }
        }
    }
}

// MARK: - Content Layout

private extension ComparisonView {
    func contentStack(viewModel: ComparisonViewModel) -> some View {
        VStack(spacing: 0) {
            topBar(viewModel: viewModel)
            ComparisonVideoAreaView(viewModel: viewModel)
            controlsPanel(viewModel: viewModel)
        }
    }

    func topBar(viewModel: ComparisonViewModel) -> some View {
        HStack {
            circleButton(icon: "xmark") { showDoneSheet = true }
            Spacer()
            circleButton(icon: "arrow.left.arrow.right") { viewModel.swapVideos() }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    func circleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body).fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
    }
}

// MARK: - Controls Panel

private extension ComparisonView {
    func controlsPanel(viewModel: ComparisonViewModel) -> some View {
        VStack(spacing: 12) {
            ComparisonTimelineSlider(viewModel: viewModel)
            syncOffsetRow(viewModel: viewModel)
            modePicker(viewModel: viewModel)
            premiumControls(viewModel: viewModel)
            ComparisonControlsView(viewModel: viewModel)
            doneButton
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder
    func syncOffsetRow(viewModel: ComparisonViewModel) -> some View {
        if viewModel.comparisonMode.isSynchronized {
            SyncOffsetStrip(viewModel: viewModel)
        }
    }

    func modePicker(viewModel: ComparisonViewModel) -> some View {
        Menu {
            ForEach(ComparisonMode.allCases) { mode in
                modeMenuItem(mode: mode, viewModel: viewModel)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.comparisonMode.iconName)
                    .font(.caption)
                Text(viewModel.comparisonMode.rawValue)
                    .font(.subheadline).fontWeight(.medium)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .foregroundStyle(Color.appTeal)
        }
    }

    @ViewBuilder
    func modeMenuItem(mode: ComparisonMode, viewModel: ComparisonViewModel) -> some View {
        if mode.isAvailable {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.comparisonMode = mode
                }
            } label: {
                HStack {
                    Label(mode.rawValue, systemImage: mode.iconName)
                    if mode == viewModel.comparisonMode {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } else {
            Button { } label: {
                Label("\(mode.rawValue) (Pro)", systemImage: "lock.fill")
            }
            .disabled(true)
        }
    }

    @ViewBuilder
    func premiumControls(viewModel: ComparisonViewModel) -> some View {
        if viewModel.comparisonMode == .onionSkin {
            onionSkinSlider(viewModel: viewModel)
        }
    }

    func onionSkinSlider(viewModel: ComparisonViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
            Slider(value: Binding(
                get: { viewModel.onionSkinOpacity },
                set: { viewModel.onionSkinOpacity = $0 }
            ), in: 0.1...0.9)
            .tint(Color.appTeal)
            Image(systemName: "circle.righthalf.filled")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    var doneButton: some View {
        Button { showDoneSheet = true } label: {
            Text("DONE")
                .font(.headline).fontWeight(.bold).foregroundStyle(.white)
                .frame(width: 200, height: 48)
                .background(Color.appTeal)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    var exportSheet: some View {
        if let viewModel = viewModel {
            ExportProgressView(
                viewModel: viewModel, isExporting: $isExporting,
                progress: $exportProgress, onDismiss: { showExportSheet = false }
            )
        }
    }
}

// MARK: - Setup

private extension ComparisonView {
    func onViewAppear() {
        viewModel = ComparisonViewModel(
            video1: video1, video2: video2,
            swing1: swing1, swing2: swing2
        )
    }
}
