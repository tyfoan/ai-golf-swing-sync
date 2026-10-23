//
//  CompositorLayout.swift
//  golf-sync-swing
//
//  Branch hint for CollageVideoCompositor: cells drawn side by side, one swing after the
//  other in the same cell, or the second swing blended over the first.
//

import Foundation
import CoreGraphics

nonisolated enum CompositorLayout: Equatable {
    case sideBySide          // per-cell crop, transforms applied independently
    case sequential          // one cell, the swing whose turn it is
    case stacked(opacity: CGFloat)

    /// Sequential draws only the last swing that has a frame: a finished swing's track can
    /// still hand the compositor its last frame, and no fill covers it any more.
    var showsOneSwingAtATime: Bool {
        self == .sequential
    }

    /// Whether the cell is the swing blended over the first one. It shows only inside the
    /// first swing's card, so it never washes over the cream around it.
    func isBlended(cellAt index: Int) -> Bool {
        switch self {
        case .sideBySide, .sequential: return false
        case .stacked:                 return index == 1
        }
    }

    /// The blended swing at the overlay opacity; everything else solid.
    func opacity(ofCellAt index: Int) -> CGFloat {
        switch self {
        case .sideBySide, .sequential: return 1
        case .stacked(let opacity):    return index == 1 ? opacity : 1
        }
    }
}
