//
//  VideoArrangement.swift
//  golf-sync-swing
//
//  How the two swings share an export canvas.
//

import Foundation

nonisolated enum VideoArrangement: Equatable {
    /// Side by side, each in its own half.
    case horizontal
    /// One above the other.
    case vertical
    /// Both on the whole canvas: blended (stacked) or one after the other (sequential).
    case overlaid
}
