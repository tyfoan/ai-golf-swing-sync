//
//  CapturePiPTile.swift
//  golf-sync-swing
//
//  The picture-in-picture tile on the Camera tab: a fixed 120×160 box with a caption, a swap
//  glyph, and whatever is not currently on the main screen inside it.
//
//  The tile is a CONTROL. Tapping it swaps the two surfaces — the swing goes full-screen and
//  the camera comes down here, or the other way round. It knows nothing about either content;
//  its caller decides what goes in and what the tap does, so this file cannot be the place a
//  camera preview ever gets mounted.
//

import SwiftUI

struct CapturePiPTile<Content: View>: View {

    /// Already localized, and it names what is IN the tile — "LIVE" or "SWING 2" — never the
    /// mode. It is the only thing that says which of the two surfaces is the live camera.
    let badge: String

    /// VoiceOver's name for the tap. The glyph is the sighted affordance; this is the other one.
    let accessibilityDescription: String

    let onSwap: () -> Void

    @ViewBuilder let content: Content

    /// A `Button`, not an `onTapGesture`: the button trait, the accessibility label and the
    /// press behaviour all come with it, and "obvious affordance that it is tappable" means
    /// VoiceOver as much as it means the glyph.
    ///
    /// The label REPLACES the aggregated child labels, so setting it alone silently deletes the
    /// caption — the one thing that says which surface is the live camera. The badge comes back
    /// as the VALUE, which is what it is: the control's name says what the tap does, its value
    /// says what the tile currently holds. Sighted users read the same two facts off the glyph
    /// and the caption.
    var body: some View {
        Button(action: onSwap) { tile }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityValue(badge)
    }

    /// **The whole tile is the hit target, and that is enough.** 120×160pt is roughly three
    /// times the 44pt minimum in both axes. Do not "fix" this by padding the tile out into the
    /// preview: the rail it lives in is `maxWidth: .infinity`, so a shape or a slop margin
    /// applied one level too high becomes a full-width invisible tap surface over the camera.
    /// `contentShape` is scoped to the rounded rect for the same reason.
    private var tile: some View {
        ZStack {
            Color.black
            content
            caption
            swapGlyph
        }
        .frame(width: Metrics.width, height: Metrics.height)
        .clipShape(Metrics.shape)
        .overlay(Metrics.shape.stroke(Color.sand, lineWidth: 2))
        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
        .contentShape(Metrics.shape)
    }

    private var caption: some View {
        Text(badge)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Diagonally opposite the caption, so a tall letterboxed frame can never put the two on
    /// top of each other.
    private var swapGlyph: some View {
        Image(systemName: "arrow.left.arrow.right")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(6)
            .background(Color.black.opacity(0.6), in: Circle())
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

// MARK: - Metrics

/// Sized once, here. A generic type cannot hold stored statics, and these are the numbers the
/// ring buffer's 240px long edge was chosen against — see `SwingFrameBuffer.maximumEdge`.
private enum Metrics {
    static let width: CGFloat = 120
    static let height: CGFloat = 160
    static let cornerRadius: CGFloat = 12
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius) }
}
