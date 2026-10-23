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
        let layout = ExportCanvasLayout(canvas: size, arrangement: viewModel.arrangement)
        return ZStack(alignment: .topLeading) {
            Color.exportCanvas
            ForEach(viewModel.visiblePositions, id: \.self) { position in
                placedTile(at: position, cell: layout.cellRects[position], cornerRadius: layout.cornerRadius)
            }
        }
        .modifier(CanvasCard(cornerRadius: Self.cornerRadius))
    }

    private func placedTile(at position: Int, cell: CGRect, cornerRadius: CGFloat) -> some View {
        tile(at: position, cornerRadius: cornerRadius)
            .frame(width: cell.width, height: cell.height)
            .mask(alignment: .topLeading) {
                firstSwingMask(at: position, tile: cell.size, cornerRadius: cornerRadius)
            }
            .offset(x: cell.minX, y: cell.minY)
    }

    private func tile(at position: Int, cornerRadius: CGFloat) -> some View {
        let layout = viewModel.buildLayoutConfig().compositorLayout
        return ZoomableVideoTile(
            player: viewModel.comparison.player,
            cutout: atlas.cutout(forTrack: viewModel.comparison.trackOrder[position]),
            transform: $viewModel.transforms[position],
            cornerRadius: cornerRadius
        )
        .opacity(layout.opacity(ofCellAt: position))
        .allowsHitTesting(viewModel.isFramable(position))
    }

    /// A blended swing shows only inside the first swing's card; any other tile is whole.
    @ViewBuilder
    private func firstSwingMask(at position: Int, tile: CGSize, cornerRadius: CGFloat) -> some View {
        if viewModel.buildLayoutConfig().compositorLayout.isBlended(cellAt: position) {
            TileCard(
                aspect: atlas.cutout(forTrack: viewModel.comparison.trackOrder[0]).slot.size,
                tile: tile,
                transform: viewModel.transforms[0],
                cornerRadius: cornerRadius
            ).shape
        } else {
            Rectangle()
        }
    }

    private func fittedSize(ratio: CGFloat, in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let width = min(size.width, size.height * ratio)
        return CGSize(width: width, height: width / ratio)
    }
}

/// The canvas as a raised card on the cream sheet: rounded, with a hairline and a shadow,
/// so its own cream still reads as the file's edge.
private struct CanvasCard: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.black.opacity(0.06)) }
            .background {
                shape.fill(Color.exportCanvas)
                    .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
            }
    }
}
