//
//  AspectRatioPickerView.swift
//  golf-sync-swing
//

import SwiftUI

struct AspectRatioPickerView: View {
    let onSelect: (ExportAspectRatio) -> Void
    let onCancel: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                topBar
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        section(title: "Popular", presets: ExportAspectRatio.allCases.filter(\.isPrimary))
                        section(title: "More", presets: ExportAspectRatio.allCases.filter { !$0.isPrimary })
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button { onCancel() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            Spacer()
            Text("Choose Format")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func section(title: String, presets: [ExportAspectRatio]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(presets) { preset in
                    AspectRatioCard(preset: preset) { onSelect(preset) }
                }
            }
        }
    }
}

private struct AspectRatioCard: View {
    let preset: ExportAspectRatio
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                preview
                Text(preset.displayName)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var preview: some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(0.15))
            arrangementShape
        }
        .aspectRatio(preset.ratio, contentMode: .fit)
        .frame(height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var arrangementShape: some View {
        switch preset.arrangement {
        case .horizontal:
            HStack(spacing: 2) {
                Rectangle().fill(Color.green.opacity(0.6))
                Rectangle().fill(Color.blue.opacity(0.6))
            }
        case .vertical:
            VStack(spacing: 2) {
                Rectangle().fill(Color.green.opacity(0.6))
                Rectangle().fill(Color.blue.opacity(0.6))
            }
        }
    }
}
