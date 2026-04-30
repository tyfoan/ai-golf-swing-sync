//
//  ZoomableVideoContainerView.swift
//  golf-sync-swing
//
//  UIKit container that renders a video via AVPlayerLayer and accepts
//  pinch-to-zoom + drag-to-pan gestures. Reports transform changes via
//  the `onChange` callback.
//
//  Gesture clamping logic ported from video-collage's Zoomable.swift.
//

import UIKit
import AVFoundation

final class ZoomableVideoContainerView: UIView {

    var player: AVPlayer? {
        didSet { playerLayer.player = player }
    }

    var transformState: VideoTransform {
        didSet { applyTransform() }
    }

    var onChange: ((VideoTransform) -> Void)?

    private let playerLayer = AVPlayerLayer()
    private let videoLayer = CALayer()

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    private var pinchStartScale: CGFloat = 1.0
    private var panStartOffset: CGPoint = .zero

    init(transform: VideoTransform = .identity) {
        self.transformState = transform
        super.init(frame: .zero)
        setupLayers()
        setupGestures()
        clipsToBounds = true
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setupLayers() {
        videoLayer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(videoLayer)
    }

    private func setupGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let panOne = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panOne.minimumNumberOfTouches = 1
        panOne.maximumNumberOfTouches = 1
        panOne.require(toFail: pinch)
        let panTwo = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panTwo.minimumNumberOfTouches = 2
        panTwo.maximumNumberOfTouches = 2

        addGestureRecognizer(pinch)
        addGestureRecognizer(panOne)
        addGestureRecognizer(panTwo)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoLayer.frame = bounds
        playerLayer.frame = bounds
        if transformState.containerSize != bounds.size {
            transformState.containerSize = bounds.size
            onChange?(transformState)
        }
        applyTransform()
    }

    private func applyTransform() {
        let scaleT = CGAffineTransform(scaleX: transformState.scale, y: transformState.scale)
        let translateT = CGAffineTransform(translationX: transformState.offset.x, y: transformState.offset.y)
        videoLayer.setAffineTransform(translateT.concatenating(scaleT))
    }

    @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
        switch gr.state {
        case .began:
            pinchStartScale = transformState.scale
        case .changed:
            let candidate = pinchStartScale * gr.scale
            transformState.scale = min(max(candidate, minScale), maxScale)
            transformState.offset = clampedOffset(transformState.offset, scale: transformState.scale)
            onChange?(transformState)
        case .ended, .cancelled:
            if transformState.scale <= 1.01 {
                UIView.animate(withDuration: 0.2) {
                    self.transformState.scale = 1.0
                    self.transformState.offset = .zero
                    self.applyTransform()
                }
                onChange?(transformState)
            }
        default: break
        }
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        switch gr.state {
        case .began:
            panStartOffset = transformState.offset
        case .changed:
            let translation = gr.translation(in: self)
            let scale = max(transformState.scale, 0.001)
            let candidate = CGPoint(
                x: panStartOffset.x + translation.x / scale,
                y: panStartOffset.y + translation.y / scale
            )
            transformState.offset = clampedOffset(candidate, scale: transformState.scale)
            onChange?(transformState)
        default: break
        }
    }

    private func clampedOffset(_ candidate: CGPoint, scale: CGFloat) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0, scale > 1.0 else { return .zero }
        let maxX = (bounds.width  * (scale - 1)) / (2 * scale)
        let maxY = (bounds.height * (scale - 1)) / (2 * scale)
        return CGPoint(
            x: min(max(candidate.x, -maxX), maxX),
            y: min(max(candidate.y, -maxY), maxY)
        )
    }
}
