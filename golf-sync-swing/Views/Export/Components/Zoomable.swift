//
//  Zoomable.swift
//  golf-sync-swing
//
//  SwiftUI overlay that captures pinch + 1-finger pan + 2-finger pan and
//  writes scale + offset back into bindings. Ported from video-collage's
//  Zoomable.swift / ZoomGesture.
//
//  Storage convention: `offset` is PRE-scale (the gesture handler divides
//  the raw translation by the current scale). This pairs with
//  `.offset(x:y:).scaleEffect(s)` in SwiftUI, where the offset is applied
//  before the scaleEffect → visible movement = offset × scale.
//
//  The renderer (`ExportLayoutRenderer`) multiplies offset × scale × the
//  screen→export ratio so the export reproduces the same visible shift.
//

import SwiftUI
import UIKit

extension View {
    func zoomable(scale: Binding<CGFloat>, offset: Binding<CGPoint>, parentSize: CGSize) -> some View {
        ZoomableContext(scale: scale, offset: offset, parentSize: parentSize) { self }
    }
}

private struct ZoomableContext<Content: View>: View {
    @Binding var scale: CGFloat
    @Binding var offset: CGPoint
    let parentSize: CGSize
    let content: Content

    init(
        scale: Binding<CGFloat>,
        offset: Binding<CGPoint>,
        parentSize: CGSize,
        @ViewBuilder content: () -> Content
    ) {
        self._scale = scale
        self._offset = offset
        self.parentSize = parentSize
        self.content = content()
    }

    var body: some View {
        content.overlay(ZoomGesture(size: parentSize, scale: $scale, offset: $offset))
    }
}

private struct ZoomGesture: UIViewRepresentable {
    let size: CGSize
    @Binding var scale: CGFloat
    @Binding var offset: CGPoint

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator

        let twoFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.delegate = context.coordinator

        let oneFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        oneFingerPan.minimumNumberOfTouches = 1
        oneFingerPan.maximumNumberOfTouches = 1
        oneFingerPan.delegate = context.coordinator
        oneFingerPan.require(toFail: pinch)

        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(twoFingerPan)
        view.addGestureRecognizer(oneFingerPan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isValid = true
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.isValid = false
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ZoomGesture
        var isValid: Bool = true

        init(parent: ZoomGesture) { self.parent = parent }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        @objc func handlePan(_ sender: UIPanGestureRecognizer) {
            guard isValid, let view = sender.view,
                  parent.size.width > 0, parent.size.height > 0 else { return }

            let translation = sender.translation(in: view)
            let currentScale = parent.scale
            guard currentScale > 0 else { return }

            // Divide by scale because offset is applied BEFORE scaleEffect in SwiftUI,
            // so it gets multiplied by scale when rendered. This gives 1:1 finger tracking.
            let adjusted = CGPoint(x: translation.x / currentScale, y: translation.y / currentScale)
            let candidate = CGPoint(x: parent.offset.x + adjusted.x, y: parent.offset.y + adjusted.y)

            // Storage clamp: at scale S, max stored offset = parentSize × (S-1) / (2S)
            // because rendered visible offset is S × stored.
            let scaledSpan = CGSize(
                width: parent.size.width * (currentScale - 1),
                height: parent.size.height * (currentScale - 1)
            )
            let maxX = max(scaledSpan.width / (2 * currentScale), 0)
            let maxY = max(scaledSpan.height / (2 * currentScale), 0)
            let constrained = CGPoint(
                x: min(max(candidate.x, -maxX), maxX),
                y: min(max(candidate.y, -maxY), maxY)
            )

            guard isValid else { return }
            if sender.state == .ended {
                withAnimation(.easeOut(duration: 0.15)) { parent.offset = constrained }
            } else if sender.state == .began || sender.state == .changed {
                parent.offset = constrained
            }
            sender.setTranslation(.zero, in: view)
        }

        @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
            guard isValid, parent.size.width > 0, parent.size.height > 0 else { return }

            switch sender.state {
            case .changed:
                let currentScale = parent.scale
                guard currentScale > 0 else { return }
                let candidate = max(currentScale * sender.scale, 1.0)
                parent.scale = min(candidate, 5.0)
                sender.scale = 1.0
            case .ended:
                if parent.scale <= 1.01 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        parent.scale = 1.0
                        parent.offset = .zero
                    }
                }
            default: break
            }
        }
    }
}
