//
//  SkeletonOverlayView.swift
//  golf-sync-swing
//
//  Draws body pose skeleton (joints + connection lines) using SwiftUI Canvas.
//  Renders efficiently without view hierarchy churn.
//  Passes touches through via .allowsHitTesting(false).
//

import SwiftUI
import Vision

struct SkeletonOverlayView: View {
    let jointMap: BodyJointMap?
    let isMirrored: Bool

    private let jointRadius: CGFloat = 4
    private let lineWidth: CGFloat = 2.5
    private let minimumConfidence: Float = 0.1

    var body: some View {
        Canvas { context, size in
            guard let jointMap else { return }
            drawConnections(context: context, size: size, jointMap: jointMap)
            drawJoints(context: context, size: size, jointMap: jointMap)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drawing

    private func drawConnections(context: GraphicsContext, size: CGSize, jointMap: BodyJointMap) {
        for (startName, endName) in BodyJointMap.connections {
            guard let startJoint = jointMap.joints[startName],
                  let endJoint = jointMap.joints[endName],
                  startJoint.confidence >= minimumConfidence,
                  endJoint.confidence >= minimumConfidence else { continue }

            let startPoint = scaledPoint(startJoint.position, in: size)
            let endPoint = scaledPoint(endJoint.position, in: size)
            let avgConfidence = (startJoint.confidence + endJoint.confidence) / 2

            var path = Path()
            path.move(to: startPoint)
            path.addLine(to: endPoint)

            context.stroke(
                path,
                with: .color(Color.fairwayGreen.opacity(Double(avgConfidence))),
                lineWidth: lineWidth
            )
        }
    }

    private func drawJoints(context: GraphicsContext, size: CGSize, jointMap: BodyJointMap) {
        for (_, joint) in jointMap.joints {
            guard joint.confidence >= minimumConfidence else { continue }

            let point = scaledPoint(joint.position, in: size)
            let rect = CGRect(
                x: point.x - jointRadius,
                y: point.y - jointRadius,
                width: jointRadius * 2,
                height: jointRadius * 2
            )

            context.fill(
                Path(ellipseIn: rect),
                with: .color(Color.sand.opacity(Double(joint.confidence)))
            )
        }
    }

    // MARK: - Coordinate Mapping

    private func scaledPoint(_ normalizedPoint: CGPoint, in size: CGSize) -> CGPoint {
        let x = isMirrored ? (1 - normalizedPoint.x) : normalizedPoint.x
        return CGPoint(x: x * size.width, y: normalizedPoint.y * size.height)
    }
}
