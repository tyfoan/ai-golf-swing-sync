//
//  ComparisonVideoAreaView.swift
//  golf-sync-swing
//
//  Renders dual video players in the active ComparisonMode:
//  side-by-side, onion skin (opacity blend), or full overlay.
//

import SwiftUI
import AVFoundation

struct ComparisonVideoAreaView: View {
    let viewModel: ComparisonViewModel
    let isAutoSyncing: Bool
    let autoSyncStatus: String
    let showSyncConfirmation: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                modeLayout(geometry: geometry)
                syncOverlay
            }
        }
    }
}

// MARK: - Mode Layouts

private extension ComparisonVideoAreaView {
    @ViewBuilder
    func modeLayout(geometry: GeometryProxy) -> some View {
        switch viewModel.comparisonMode {
        case .sideBySide:
            sideBySideLayout(geometry: geometry)
        case .onionSkin:
            onionSkinLayout(geometry: geometry)
        case .overlay:
            overlayLayout(geometry: geometry)
        }
    }

    func sideBySideLayout(geometry: GeometryProxy) -> some View {
        HStack(spacing: 2) {
            videoPanel(player: viewModel.effectivePlayer1, width: geometry.size.width / 2 - 1)
            videoPanel(player: viewModel.effectivePlayer2, width: geometry.size.width / 2 - 1)
        }
        .frame(maxHeight: .infinity)
    }

    func onionSkinLayout(geometry: GeometryProxy) -> some View {
        ZStack {
            VideoPlayerView(player: viewModel.effectivePlayer1)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VideoPlayerView(player: viewModel.effectivePlayer2)
                .opacity(viewModel.onionSkinOpacity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .onTapGesture { viewModel.togglePlayPause() }
    }

    func overlayLayout(geometry: GeometryProxy) -> some View {
        ZStack {
            VideoPlayerView(player: viewModel.effectivePlayer1)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VideoPlayerView(player: viewModel.effectivePlayer2)
                .blendMode(.screen)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .onTapGesture { viewModel.togglePlayPause() }
    }
}

// MARK: - Video Panel (Side-By-Side)

private extension ComparisonVideoAreaView {
    func videoPanel(player: AVPlayer, width: CGFloat) -> some View {
        VideoPlayerView(player: player)
            .frame(width: width)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { viewModel.togglePlayPause() }
    }
}

// MARK: - Sync Overlay

private extension ComparisonVideoAreaView {
    @ViewBuilder
    var syncOverlay: some View {
        if isAutoSyncing {
            syncProgressBanner
        } else if showSyncConfirmation {
            syncConfirmationBanner
        }
    }

    var syncProgressBanner: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text(autoSyncStatus).font(.caption).foregroundStyle(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.bottom, 8)
        }
    }

    var syncConfirmationBanner: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appTeal)
                Text("Synced at impact")
                    .font(.caption).fontWeight(.medium).foregroundStyle(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.bottom, 8)
            .transition(.opacity)
        }
    }
}
