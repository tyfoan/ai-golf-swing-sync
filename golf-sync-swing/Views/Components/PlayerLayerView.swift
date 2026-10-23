//
//  PlayerLayerView.swift
//  golf-sync-swing
//
//  A bare AVPlayerLayer for SwiftUI: no controls, no touch handling — the single-video
//  card's counterpart of the comparison stage's CompositionSlotView.
//

import AVFoundation
import SwiftUI
import UIKit

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerLayerHostView {
        PlayerLayerHostView()
    }

    func updateUIView(_ view: PlayerLayerHostView, context: Context) {
        view.show(player, gravity: gravity)
    }

    /// Detached on the way out, so a layer that is gone never keeps a claim on the
    /// player's output.
    static func dismantleUIView(_ view: PlayerLayerHostView, coordinator: ()) {
        view.detach()
    }
}

/// UIKit side of PlayerLayerView: a view whose own layer is the player layer, so it always
/// matches the view's bounds.
final class PlayerLayerHostView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ player: AVPlayer, gravity: AVLayerVideoGravity) {
        if playerLayer.player !== player { playerLayer.player = player }
        playerLayer.videoGravity = gravity
    }

    func detach() {
        playerLayer.player = nil
    }
}
