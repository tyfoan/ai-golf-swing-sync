//
//  CompositorLayout.swift
//  golf-sync-swing
//
//  Branch hint for CollageVideoCompositor: cells drawn side by side (which also covers
//  sequential's one-cell-at-a-time), or the second swing blended over the first.
//

import Foundation
import CoreGraphics

nonisolated enum CompositorLayout: Equatable {
    case sideBySide          // per-cell crop, transforms applied independently
    case stacked(opacity: CGFloat)

    /// Whether a cell gets the blurred fill behind its swing. A blended swing must not:
    /// its own fill would hide the swing underneath.
    func drawsBackdrop(cellAt index: Int) -> Bool {
        switch self {
        case .sideBySide: return true
        case .stacked:    return index == 0
        }
    }

    /// The blended swing at the overlay opacity; everything else solid.
    func opacity(ofCellAt index: Int) -> CGFloat {
        switch self {
        case .sideBySide:           return 1
        case .stacked(let opacity): return index == 1 ? opacity : 1
        }
    }
}
