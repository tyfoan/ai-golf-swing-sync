//
//  ComparisonView.swift
//  golf-sync-swing
//
//  Dark immersive video comparison with side-by-side, stacked, and sequential modes.
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
    @State private var showPaywall = false
    @Environment(\.scenePhase) private var scenePhase

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
        // Pause only — never tear the player down here. `onDisappear` also fires when this
        // view merely presents the export sheet or the paywall, and `onViewAppear` is
        // guarded on `viewModel == nil`, so a teardown could never be undone: the
        // comparison screen came back permanently black. The time observer is released in
        // `ComparisonViewModel.deinit`, which is the correct place for it.
        .onDisappear { viewModel?.pause() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { viewModel?.pause() }
        }
        .sheet(isPresented: $showExportSheet) { exportSheet }
        .fullScreenCover(isPresented: $showPaywall) {
            AppPaywallView(source: .featureGate, onDismiss: { showPaywall = false })
        }
    }
}

// MARK: - Content Layout

private extension ComparisonView {
    func contentStack(viewModel: ComparisonViewModel) -> some View {
        VStack(spacing: 0) {
            topBar(viewModel: viewModel)
            videoArea(viewModel: viewModel)
            controlsPanel(viewModel: viewModel)
                .disabled(viewModel.buildError != nil)
        }
    }

    func videoArea(viewModel: ComparisonViewModel) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ComparisonVideoAreaView(viewModel: viewModel)
            circleButton(icon: "arrow.left.arrow.right", accessibilityLabel: "Swap videos") {
                viewModel.swapVideos()
            }
            .padding(16)
            if let message = viewModel.buildError {
                buildErrorOverlay(message: message, viewModel: viewModel)
            }
        }
    }

    func topBar(viewModel: ComparisonViewModel) -> some View {
        HStack {
            circleButton(icon: "xmark", accessibilityLabel: "Close comparison") { dismiss() }
            Spacer()
            circleButton(icon: "square.and.arrow.up", accessibilityLabel: "Export comparison") {
                showExportSheet = true
            }
            .disabled(viewModel.buildError != nil)
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    func circleButton(icon: String, accessibilityLabel: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body).fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Controls Panel

private extension ComparisonView {
    func controlsPanel(viewModel: ComparisonViewModel) -> some View {
        VStack(spacing: 12) {
            ComparisonTimelineSlider(viewModel: viewModel)
            modePicker(viewModel: viewModel)
            premiumControls(viewModel: viewModel)
            ComparisonControlsView(viewModel: viewModel)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
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
                Text(viewModel.comparisonMode.displayName)
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
                    Label(mode.displayName, systemImage: mode.iconName)
                    if mode == viewModel.comparisonMode {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } else {
            Button {
                if let feature = mode.premiumFeature {
                    Analytics.shared.track(.featureGateHit(feature: feature))
                }
                showPaywall = true
            } label: {
                Label(String(localized: "\(mode.displayName) (Pro)", comment: "Mode picker label for premium-locked modes"), systemImage: "lock.fill")
            }
        }
    }

    @ViewBuilder
    func premiumControls(viewModel: ComparisonViewModel) -> some View {
        if viewModel.comparisonMode.showsOpacitySlider {
            stackedOpacitySlider(viewModel: viewModel)
        }
    }

    func stackedOpacitySlider(viewModel: ComparisonViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
            Slider(value: Binding(
                get: { Double(viewModel.stackedOpacity) },
                set: { viewModel.stackedOpacity = CGFloat($0) }
            ), in: 0.1...0.9)
            .tint(Color.appTeal)
            Image(systemName: "circle.righthalf.filled")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    var exportSheet: some View {
        if let viewModel = viewModel,
           let url1 = video1.validLocalURL,
           let url2 = video2.validLocalURL {
            let swapped = viewModel.isSwapped
            ExportFlowCoordinator(
                video1URL: swapped ? url2 : url1,
                video2URL: swapped ? url1 : url2,
                swing1: swapped ? swing2 : swing1,
                swing2: swapped ? swing1 : swing2,
                syncOffset: swapped ? -viewModel.syncOffset : viewModel.syncOffset,
                comparisonViewModel: viewModel,
                onDismiss: { showExportSheet = false }
            )
        } else {
            Text("Videos unavailable")
                .padding()
                .onAppear { showExportSheet = false }
        }
    }
}

// MARK: - Build Error State

private extension ComparisonView {
    /// Covers the video area (including the swap button) when the composition
    /// could not be built, replacing the black screen with a retry path.
    func buildErrorOverlay(message: String, viewModel: ComparisonViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.6))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            retryButton(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    func retryButton(viewModel: ComparisonViewModel) -> some View {
        Button {
            viewModel.retryBuild()
        } label: {
            Text(String(localized: "Try Again", comment: "Button that retries loading the comparison videos after a failure"))
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.black)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(Color.appTeal)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Setup

private extension ComparisonView {
    func onViewAppear() {
        guard viewModel == nil else { return }
        let vm = ComparisonViewModel(
            video1: video1, video2: video2,
            swing1: swing1, swing2: swing2
        )
        viewModel = vm
        Analytics.shared.track(.comparisonOpened(mode: vm.comparisonMode))
        vm.play()
    }
}
