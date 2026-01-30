//
//  VideoPlayerView.swift
//  golf-sync-swing
//

import SwiftUI
import AVKit

struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = videoGravity
        controller.allowsVideoFrameAnalysis = false
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        uiViewController.videoGravity = videoGravity
    }
}
