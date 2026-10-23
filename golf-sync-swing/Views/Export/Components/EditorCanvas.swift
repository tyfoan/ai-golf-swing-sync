//
//  EditorCanvas.swift
//  golf-sync-swing
//
//  The export as it will look: the chosen aspect ratio, split or overlaid exactly as
//  the exporter splits it (ExportCanvasLayout), one ZoomableVideoTile per swing. In the
//  overlaid modes only the swing being framed takes gestures, and sequential shows just
//  that swing.
//

import SwiftUI

struct EditorCanvas: View {
    @Bindable var viewModel: ExportEditorViewModel
    let atlas: ComparisonAtlas

    static let cornerRadius: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let size = fittedSize(ratio: viewModel.aspectRatio.ratio, in: geo.size)
            canvas(size: size)
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func canvas(size: CGSize) -> some View {
        let cells = ExportCanvasLayout(canvas: size, arrangement: viewModel.arrangement).cellRects
        return ZStack(alignment: .topLeading) {
            Color.exportCanvas
            ForEach(viewModel.visiblePositions, id: \.self) { position in
                tile(at: position)
                    .frame(width: cells[position].width, height: cells[position].height)
                    .offset(x: cells[position].minX, y: cells[position].minY)
            }
        }
        .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06))
        }
        .background {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color.exportCanvas)
                .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        }
    }

    private func tile(at position: Int) -> some View {
        let layout = viewModel.buildLayoutConfig().compositorLayout
        return ZoomableVideoTile(
            player: viewModel.comparison.player,
            cutout: atlas.cutout(forTrack: viewModel.comparison.trackOrder[position]),
            transform: $viewModel.transforms[position],
            showsBackdrop: layout.drawsBackdrop(cellAt: position)
        )
        .opacity(layout.opacity(ofCellAt: position))
        .allowsHitTesting(viewModel.isFramable(position))
    }

    private func fittedSize(ratio: CGFloat, in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let width = min(size.width, size.height * ratio)
        return CGSize(width: width, height: width / ratio)
    }
}
