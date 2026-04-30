//
//  EditorVideoPlayerView.swift
//  golf-sync-swing
//
//  Minimal SwiftUI bridge for an AVPlayer rendered via AVPlayerLayer.
//  No transforms here — pan/zoom are applied via SwiftUI .offset()/.scaleEffect()
//  on the wrapper. Ported from video-collage's CellVideoPlayerView.
//

import SwiftUI
import AVFoundation

struct EditorVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> EditorPlayerContainerView {
        let view = EditorPlayerContainerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: EditorPlayerContainerView, context: Context) {
        uiView.player = player
    }
}

final class EditorPlayerContainerView: UIView {
    private var playerLayer: AVPlayerLayer?

    var player: AVPlayer? {
        didSet {
            if playerLayer == nil {
                let layer = AVPlayerLayer()
                layer.videoGravity = .resizeAspect
                self.layer.addSublayer(layer)
                playerLayer = layer
            }
            playerLayer?.player = player
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}
