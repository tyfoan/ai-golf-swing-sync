//
//  BalancedPairLayout.swift
//  golf-sync-swing
//
//  Splits the stage between the two swing panes so neither swing ends up much smaller
//  than the other. Each pane gets the share that gives both fitted swings the same area
//  — a landscape pro above a portrait recording gets less height than the recording,
//  because the recording needs the height to be seen — and no pane takes more than its
//  swing can use. Same-shaped swings split the stage evenly.
//
//  A third subview, when there is one, is the swap control: it sits on the seam.
//

import SwiftUI

/// Width over height of the swing a pane shows.
struct PaneAspect: LayoutValueKey {
    static let defaultValue: CGFloat = 1
}

struct BalancedPairLayout: Layout {
    let axis: Axis
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let panes = Array(subviews.prefix(2))
        let frames = paneFrames(in: bounds, aspects: panes.map { $0[PaneAspect.self] })
        for (pane, frame) in zip(panes, frames) {
            pane.place(at: frame.origin, proposal: ProposedViewSize(frame.size))
        }
        guard let accessory = subviews.dropFirst(2).first, let first = frames.first else { return }
        accessory.place(at: seamCentre(after: first, in: bounds), anchor: .center, proposal: .unspecified)
    }

    private func paneFrames(in bounds: CGRect, aspects: [CGFloat]) -> [CGRect] {
        let split = BalancedSplit(total: axis.length(of: bounds.size) - spacing, across: axis.across(of: bounds.size))
        var offset: CGFloat = 0
        return split.lengths(for: aspects.map(axis.extentRatio)).map { length in
            defer { offset += length + spacing }
            return axis.frame(at: offset, length: length, in: bounds)
        }
    }

    private func seamCentre(after first: CGRect, in bounds: CGRect) -> CGPoint {
        axis == .vertical
            ? CGPoint(x: bounds.midX, y: first.maxY + spacing / 2)
            : CGPoint(x: first.maxX + spacing / 2, y: bounds.midY)
    }
}

/// The arithmetic of the split. With `ratio` = a swing's extent across the panes over
/// its extent along them, a pane `length` long shows `ratio × length²` of swing until
/// the swing meets the far edges at `across / ratio`; equal areas put each length in
/// proportion to `1 / √ratio`.
struct BalancedSplit {
    let total: CGFloat
    let across: CGFloat

    func lengths(for ratios: [CGFloat]) -> [CGFloat] {
        let caps = ratios.map { across / $0 }
        let weights = ratios.map { 1 / $0.squareRoot() }
        let sum = weights.reduce(0, +)
        return clamped(weights.map { total * $0 / sum }, caps: caps)
    }

    /// No pane longer than its swing can use. When both swings fit whole, they share
    /// what is left; otherwise at most one can overrun, and the other takes the rest.
    private func clamped(_ lengths: [CGFloat], caps: [CGFloat]) -> [CGFloat] {
        let spare = total - caps.reduce(0, +)
        guard spare < 0 else { return caps.map { $0 + spare / 2 } }
        guard let over = lengths.indices.first(where: { lengths[$0] > caps[$0] }) else { return lengths }
        return lengths.indices.map { $0 == over ? caps[over] : total - caps[over] }
    }
}

private extension Axis {
    func length(of size: CGSize) -> CGFloat { self == .vertical ? size.height : size.width }

    func across(of size: CGSize) -> CGFloat { self == .vertical ? size.width : size.height }

    /// A swing's extent across the panes over its extent along them.
    func extentRatio(_ aspect: CGFloat) -> CGFloat { self == .vertical ? aspect : 1 / aspect }

    func frame(at offset: CGFloat, length: CGFloat, in bounds: CGRect) -> CGRect {
        self == .vertical
            ? CGRect(x: bounds.minX, y: bounds.minY + offset, width: bounds.width, height: length)
            : CGRect(x: bounds.minX + offset, y: bounds.minY, width: length, height: bounds.height)
    }
}
