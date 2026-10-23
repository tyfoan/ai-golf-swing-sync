//
//  PairArrangement.swift
//  golf-sync-swing
//
//  How the stage shows the two swings for each parallel comparison mode: which layout
//  places the panes, which way the swap arrow points, and how each pane is dressed.
//  Sequential has no pair — it shows one pane at a time.
//

import SwiftUI

/// How one pane is dressed in an arrangement.
struct PaneStyle {
    /// The card takes the swing's own shape. Off for overlaid panes, which must share
    /// one frame so the two swings line up.
    var hugsSwing = true
    var showsBackdrop = true
    var videoOpacity: Double = 1
    var chipAlignment: Alignment = .topLeading
}

protocol PairArrangement {
    var layout: AnyLayout { get }
    var swapSymbol: String { get }
    /// `position` 0 is the first pane on screen — the back one when they overlap.
    func style(ofPaneAt position: Int, overlayOpacity: CGFloat) -> PaneStyle
}

extension ComparisonMode {
    /// Nil for sequential, which shows one pane at a time instead of a pair.
    var pairArrangement: PairArrangement? {
        switch self {
        case .sideBySide: return ColumnsArrangement()
        case .topBottom: return RowsArrangement()
        case .stacked: return OverlayArrangement()
        case .sequential: return nil
        }
    }
}

struct ColumnsArrangement: PairArrangement {
    var layout: AnyLayout { AnyLayout(BalancedPairLayout(axis: .horizontal)) }
    var swapSymbol: String { "arrow.left.arrow.right" }

    func style(ofPaneAt position: Int, overlayOpacity: CGFloat) -> PaneStyle { PaneStyle() }
}

struct RowsArrangement: PairArrangement {
    var layout: AnyLayout { AnyLayout(BalancedPairLayout(axis: .vertical)) }
    var swapSymbol: String { "arrow.up.arrow.down" }

    func style(ofPaneAt position: Int, overlayOpacity: CGFloat) -> PaneStyle { PaneStyle() }
}

/// The front swing is see-through and draws no backdrop of its own, so the back swing
/// shows through it — the same blend the exported file gets.
struct OverlayArrangement: PairArrangement {
    var layout: AnyLayout { AnyLayout(OverlayPairLayout()) }
    var swapSymbol: String { "square.2.layers.3d" }

    func style(ofPaneAt position: Int, overlayOpacity: CGFloat) -> PaneStyle {
        guard position > 0 else { return PaneStyle(hugsSwing: false) }
        return PaneStyle(
            hugsSwing: false, showsBackdrop: false,
            videoOpacity: Double(overlayOpacity), chipAlignment: .topTrailing
        )
    }
}
