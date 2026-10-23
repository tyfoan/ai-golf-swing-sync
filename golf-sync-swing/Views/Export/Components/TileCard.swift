//
//  TileCard.swift
//  golf-sync-swing
//
//  Where a swing's card sits in its editor tile: fitted to the tile, then panned and
//  zoomed the way ZoomableVideoTile draws it (offset before scale, so the visible shift
//  is offset × scale). A blended Stacked swing is masked to the first swing's card, as
//  CellRenderer cuts it in the file.
//

import SwiftUI

struct TileCard {
    let aspect: CGSize
    let tile: CGSize
    let transform: VideoTransform
    let cornerRadius: CGFloat

    /// The card as a mask in the tile's top-left space.
    var shape: some View {
        let rect = self.rect
        return RoundedRectangle(cornerRadius: cornerRadius * transform.scale, style: .circular)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    var rect: CGRect {
        let scale = fitScale * transform.scale
        let size = CGSize(width: aspect.width * scale, height: aspect.height * scale)
        let centerX = tile.width / 2 + transform.offset.x * transform.scale
        let centerY = tile.height / 2 + transform.offset.y * transform.scale
        return CGRect(x: centerX - size.width / 2, y: centerY - size.height / 2, width: size.width, height: size.height)
    }

    private var fitScale: CGFloat {
        guard aspect.width > 0, aspect.height > 0 else { return 0 }
        return min(tile.width / aspect.width, tile.height / aspect.height)
    }
}
