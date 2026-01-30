//
//  PoseOverlayView.swift
//  golf-sync-swing
//
//  Draws body pose skeleton overlay on camera preview
//

import SwiftUI
import Vision

struct PoseOverlayView: View {
    let pose: BodyPose?

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard let pose = pose else { return }

                // Draw skeleton connections
                for (from, to) in BodyPose.skeletonConnections {
                    guard let fromPoint = pose.joints[from.rawValue.rawValue],
                          let toPoint = pose.joints[to.rawValue.rawValue] else {
                        continue
                    }

                    let start = convertPoint(fromPoint, to: size)
                    let end = convertPoint(toPoint, to: size)

                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)

                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.9)),
                        lineWidth: 3
                    )
                }

                // Draw joint dots
                for (_, point) in pose.joints {
                    let center = convertPoint(point, to: size)
                    let dotSize: CGFloat = 8

                    let circle = Path(ellipseIn: CGRect(
                        x: center.x - dotSize / 2,
                        y: center.y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    ))

                    context.fill(circle, with: .color(.white))
                }
            }
        }
    }

    /// Convert Vision coordinates (origin bottom-left, 0-1) to view coordinates
    private func convertPoint(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(
            x: point.x * size.width,
            y: (1 - point.y) * size.height
        )
    }
}

#Preview {
    ZStack {
        Color.black

        PoseOverlayView(pose: nil)
    }
    .ignoresSafeArea()
}
