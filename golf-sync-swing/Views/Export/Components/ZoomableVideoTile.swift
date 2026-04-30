//
//  ZoomableVideoTile.swift
//  golf-sync-swing
//
//  SwiftUI bridge over ZoomableVideoContainerView. Binds VideoTransform
//  and the AVPlayer to the underlying UIKit container.
//

import SwiftUI
import AVFoundation

struct ZoomableVideoTile: UIViewRepresentable {
    let player: AVPlayer
    @Binding var transform: VideoTransform

    func makeUIView(context: Context) -> ZoomableVideoContainerView {
        let view = ZoomableVideoContainerView(transform: transform)
        view.player = player
        view.onChange = { newTransform in
            DispatchQueue.main.async {
                if transform != newTransform { transform = newTransform }
            }
        }
        return view
    }

    func updateUIView(_ uiView: ZoomableVideoContainerView, context: Context) {
        uiView.player = player
        if uiView.transformState != transform {
            uiView.transformState = transform
        }
    }
}
