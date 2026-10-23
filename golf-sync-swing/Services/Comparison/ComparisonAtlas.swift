//
//  ComparisonAtlas.swift
//  golf-sync-swing
//
//  Where each swing sits inside the comparison composition's frames.
//
//  The composition no longer lays the two swings out for the screen. It draws both
//  impact-aligned tracks into one frame — an atlas — and the stage cuts each swing back
//  out with its own player layer (CompositionSlotView). Arrangement, swap and overlay
//  opacity are therefore SwiftUI's business: changing them never touches AVFoundation,
//  so they are instant and cannot stall playback.
//

import CoreGraphics

nonisolated struct ComparisonAtlas: Equatable {
    /// The composition's render size, in pixels.
    let canvas: CGSize
    /// One rectangle per video track, in track order: where that swing is drawn.
    let slots: [CGRect]

    /// Width over height of a track's swing as drawn.
    func aspectRatio(ofTrack index: Int) -> CGFloat {
        let slot = slots[index]
        return slot.height > 0 ? slot.width / slot.height : 1
    }

    /// The part of the frame a pane shows for a track: one pixel in from the slot's edge,
    /// because scaling samples neighbouring pixels and a slot's neighbour is the gutter.
    func cutout(forTrack index: Int) -> SlotCutout {
        SlotCutout(canvas: canvas, slot: slots[index].insetBy(dx: 1, dy: 1))
    }
}

/// A rectangle of the composition's frame, in the frame's own pixels.
nonisolated struct SlotCutout: Equatable {
    let canvas: CGSize
    let slot: CGRect
}
