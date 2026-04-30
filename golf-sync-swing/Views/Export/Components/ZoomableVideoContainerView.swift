//
//  ZoomableVideoContainerView.swift
//  golf-sync-swing
//
//  UIKit container that renders a video via AVPlayerLayer and accepts
//  pinch-to-zoom + drag-to-pan gestures. Reports transform changes via
//  the `onChange` callback.
//
//  Storage convention: `transformState.offset` is the VISIBLE shift in
//  container points (1:1 with finger drag at any zoom level). The render
//  pipeline reads it the same way — no scale multiplication anywhere.
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

    private let contentView = UIView()
    private let playerLayer = AVPlayerLayer()

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    private var pinchStartScale: CGFloat = 1.0
    private var panStartOffset: CGPoint = .zero

    init(transform: VideoTransform = .identity) {
        self.transformState = transform
        super.init(frame: .zero)
        setupViews()
        setupGestures()
        clipsToBounds = true
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setupViews() {
        contentView.backgroundColor = .clear
        contentView.layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        addSubview(contentView)
    }

    private func setupGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 2
        addGestureRecognizer(pinch)
        addGestureRecognizer(pan)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.transform = .identity
        contentView.frame = bounds
        playerLayer.frame = contentView.bounds

        if transformState.containerSize != bounds.size {
            transformState.containerSize = bounds.size
            onChange?(transformState)
        }
        applyTransform()
    }

    /// scale-then-translate: visible point p' = scale × p + offset.
    /// At any zoom, a finger drag of N points produces N points of visible movement.
    private func applyTransform() {
        var t = CGAffineTransform.identity
        t = t.scaledBy(x: transformState.scale, y: transformState.scale)
        t.tx = transformState.offset.x
        t.ty = transformState.offset.y
        contentView.transform = t
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
            if transformState.scale <= 1.01 { animateReset() }
        default: break
        }
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        switch gr.state {
        case .began:
            panStartOffset = transformState.offset
        case .changed:
            let translation = gr.translation(in: self)
            let candidate = CGPoint(
                x: panStartOffset.x + translation.x,
                y: panStartOffset.y + translation.y
            )
            transformState.offset = clampedOffset(candidate, scale: transformState.scale)
            onChange?(transformState)
        default: break
        }
    }

    private func animateReset() {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            self.transformState.scale = 1.0
            self.transformState.offset = .zero
        }
    }

    /// Visible-unit clamp: at scale `s`, the content extends `(s-1)/2 × W` past
    /// each edge in either direction.
    private func clampedOffset(_ candidate: CGPoint, scale: CGFloat) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0, scale > 1.0 else { return .zero }
        let maxX = bounds.width  * (scale - 1) / 2
        let maxY = bounds.height * (scale - 1) / 2
        return CGPoint(
            x: min(max(candidate.x, -maxX), maxX),
            y: min(max(candidate.y, -maxY), maxY)
        )
    }
}

extension ZoomableVideoContainerView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
