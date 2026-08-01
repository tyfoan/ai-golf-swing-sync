//
//  PoseOverlayGeometry.swift
//  golf-sync-swing
//
//  Maps Vision's normalized pose coordinates onto the on-screen rect of an
//  AVCaptureVideoPreviewLayer configured with `.resizeAspectFill`.
//
//  Deliberately a pure value type with no AVFoundation or SwiftUI dependency: pose
//  alignment cannot be verified on the simulator (VNDetectHumanBodyPoseRequest cannot even
//  be set up there), so the whole mapping is isolated here — one function to correct if the
//  skeleton sits off the body on device, and one thing to unit-test.
//
//  Three independent transforms, every one of which must be right:
//    1. Vision's origin is bottom-left with Y increasing upward; SwiftUI's Canvas origin is
//       top-left with Y increasing downward.
//    2. `.resizeAspectFill` scales the source to COVER the view and centre-crops the
//       overflow, so normalized coordinates do not map linearly onto the view's rect.
//    3. The front camera's preview is mirrored.
//

import CoreGraphics

struct PoseOverlayGeometry: Equatable {

    /// Width / height of the source image **after** the capture connection's rotation has
    /// been applied. A 16:9 sensor delivered through a 90° rotated connection is 9:16 here —
    /// passing the raw sensor ratio yields a stretched, offset skeleton.
    let sourceAspectRatio: CGFloat

    /// True when the on-screen preview shows the analyzed buffer mirrored — the parity (XOR)
    /// of the preview layer's mirroring and the video-data connection's `isVideoMirrored`.
    /// Neither flag alone is authoritative: the preview auto-mirrors the front camera while
    /// the data output is forced unmirrored, and a wrong value looks plausible on a symmetric
    /// pose while being horizontally flipped mid-swing.
    let isMirrored: Bool

    /// Converts one normalized Vision point into view coordinates.
    func point(for normalized: CGPoint, in viewSize: CGSize) -> CGPoint {
        let displayed = displayedSize(in: viewSize)
        let originX = (viewSize.width - displayed.width) / 2
        let originY = (viewSize.height - displayed.height) / 2

        let x = isMirrored ? (1 - normalized.x) : normalized.x
        let y = 1 - normalized.y

        return CGPoint(
            x: originX + x * displayed.width,
            y: originY + y * displayed.height
        )
    }

    /// Size the source occupies once scaled to COVER `viewSize`. At least one dimension
    /// overflows the view; the origin offsets are therefore zero or negative.
    func displayedSize(in viewSize: CGSize) -> CGSize {
        guard sourceAspectRatio > 0, viewSize.width > 0, viewSize.height > 0 else {
            return viewSize
        }

        let viewAspectRatio = viewSize.width / viewSize.height

        guard sourceAspectRatio > viewAspectRatio else {
            // Source is relatively taller — width fills, height overflows.
            return CGSize(width: viewSize.width, height: viewSize.width / sourceAspectRatio)
        }
        // Source is relatively wider — height fills, width overflows.
        return CGSize(width: viewSize.height * sourceAspectRatio, height: viewSize.height)
    }
}
