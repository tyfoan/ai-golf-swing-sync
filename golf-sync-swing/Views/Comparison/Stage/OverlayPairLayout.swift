//
//  OverlayPairLayout.swift
//  golf-sync-swing
//
//  Both swing panes over the whole stage, the later one on top; the swap control, when
//  there is one, in the bottom-trailing corner where it hides the least of a golfer.
//

import SwiftUI

struct OverlayPairLayout: Layout {
    var inset: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for pane in subviews.prefix(2) {
            pane.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
        let corner = CGPoint(x: bounds.maxX - inset, y: bounds.maxY - inset)
        subviews.dropFirst(2).first?.place(at: corner, anchor: .bottomTrailing, proposal: .unspecified)
    }
}
