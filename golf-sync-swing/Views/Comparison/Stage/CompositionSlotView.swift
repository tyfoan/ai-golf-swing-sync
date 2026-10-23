//
//  CompositionSlotView.swift
//  golf-sync-swing
//
//  Shows one swing cut out of the comparison composition. The composition draws both
//  swings into a single frame (ComparisonAtlas); this view stretches a player layer to
//  the whole frame and slides it so the requested slot fits — or fills — the view, with
//  everything outside the slot clipped away. Several of these share ONE AVPlayer (the
//  pattern of Apple's AVLoupe sample), so every pane shows the same decoded,
//  impact-aligned frame and nothing can drift.
//

import AVFoundation
import SwiftUI
import UIKit

/// How a slot meets its view: whole and letterboxed, or cropped to cover it.
enum SlotGravity {
    case fit, fill

    func scale(of content: CGSize, in bounds: CGSize) -> CGFloat {
        let widthRatio = bounds.width / content.width
        let heightRatio = bounds.height / content.height
        switch self {
        case .fit: return min(widthRatio, heightRatio)
        case .fill: return max(widthRatio, heightRatio)
        }
    }
}

struct CompositionSlotView: UIViewRepresentable {
    let player: AVPlayer
    let cutout: SlotCutout
    var gravity: SlotGravity = .fit

    func makeUIView(context: Context) -> SlotPlayerView {
        SlotPlayerView()
    }

    func updateUIView(_ view: SlotPlayerView, context: Context) {
        view.show(cutout, of: player, gravity: gravity)
    }

    /// Detached on the way out, so a layer that is gone never keeps a claim on the
    /// player's output.
    static func dismantleUIView(_ view: SlotPlayerView, coordinator: ()) {
        view.detach()
    }
}

/// UIKit side of CompositionSlotView: a clipping view holding a player layer the size of
/// the whole composition frame.
final class SlotPlayerView: UIView {
    private let slotClip = UIView()
    private let playerLayer = AVPlayerLayer()
    private var cutout: SlotCutout?
    private var gravity = SlotGravity.fit

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        slotClip.clipsToBounds = true
        playerLayer.videoGravity = .resize
        slotClip.layer.addSublayer(playerLayer)
        addSubview(slotClip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ cutout: SlotCutout, of player: AVPlayer, gravity: SlotGravity) {
        if playerLayer.player !== player { playerLayer.player = player }
        guard cutout != self.cutout || gravity != self.gravity else { return }
        self.cutout = cutout
        self.gravity = gravity
        setNeedsLayout()
    }

    func detach() {
        playerLayer.player = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let cutout, cutout.slot.width > 0, cutout.slot.height > 0 else { return }
        let scale = gravity.scale(of: cutout.slot.size, in: bounds.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slotClip.frame = centredFrame(of: cutout.slot.size, scale: scale)
        playerLayer.frame = wholeFrame(of: cutout, scale: scale)
        CATransaction.commit()
    }

    /// The slot as it appears in this view, centred.
    private func centredFrame(of slot: CGSize, scale: CGFloat) -> CGRect {
        let size = CGSize(width: slot.width * scale, height: slot.height * scale)
        let origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        return CGRect(origin: origin, size: size)
    }

    /// The whole composition frame, slid so the slot's corner sits at the clip's origin.
    private func wholeFrame(of cutout: SlotCutout, scale: CGFloat) -> CGRect {
        CGRect(
            x: -cutout.slot.minX * scale, y: -cutout.slot.minY * scale,
            width: cutout.canvas.width * scale, height: cutout.canvas.height * scale
        )
    }
}
