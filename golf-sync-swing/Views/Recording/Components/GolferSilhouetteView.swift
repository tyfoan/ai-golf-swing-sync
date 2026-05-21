//
//  GolferSilhouetteView.swift
//  golf-sync-swing
//
//  Positioning guide rendered behind the countdown digit. Composes a layered
//  golfer body silhouette in brand green, an optional club line, and a set of
//  pulsing keypoint dots that match the joints the swing-detection ML tracks.
//
//  Geometry lives in GolferStance.swift; this view is pure presentation.
//

import SwiftUI

struct GolferSilhouetteView: View {
    let stance: GolferStance

    private var layout: StanceLayout { stance.layout }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                silhouetteBody(in: size)
                if stance.assetName == nil {
                    if let club = layout.club { clubLine(club, in: size) }
                    keypointDots(in: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Body

    @ViewBuilder
    private func silhouetteBody(in size: CGSize) -> some View {
        if let assetName = stance.assetName {
            VectorSilhouette(assetName: assetName)
        } else {
            SilhouetteBodyFill(layout: layout, canvas: size)
                .compositingGroup()
                .foregroundStyle(Color.fairwayGreen.opacity(0.32))
                .overlay(SilhouetteBodyStroke(layout: layout, canvas: size))
                .shadow(color: Color.fairwayGreen.opacity(0.4), radius: 24)
        }
    }

    private func clubLine(_ club: LimbSegment, in size: CGSize) -> some View {
        Path { path in
            path.move(to: club.start.scaled(to: size))
            path.addLine(to: club.end.scaled(to: size))
        }
        .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    // MARK: - Keypoints

    private func keypointDots(in size: CGSize) -> some View {
        ForEach(Array(layout.keypoints.enumerated()), id: \.offset) { index, point in
            KeypointDot(delayStep: index)
                .position(point.scaled(to: size))
        }
    }
}

// MARK: - Body pieces

private struct VectorSilhouette: View {
    let assetName: String

    var body: some View {
        Image(assetName)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(Color.fairwayGreen.opacity(0.42))
            .shadow(color: Color.fairwayGreen.opacity(0.4), radius: 24)
    }
}

private struct SilhouetteBodyFill: View {
    let layout: StanceLayout
    let canvas: CGSize

    var body: some View {
        ZStack {
            ForEach(Array(layout.limbs.enumerated()), id: \.offset) { _, limb in
                LimbCapsule(limb: limb, canvas: canvas)
            }
            HeadFill(layout: layout, canvas: canvas)
        }
    }
}

private struct SilhouetteBodyStroke: View {
    let layout: StanceLayout
    let canvas: CGSize

    var body: some View {
        ZStack {
            ForEach(Array(layout.limbs.enumerated()), id: \.offset) { _, limb in
                LimbCapsuleStroke(limb: limb, canvas: canvas)
            }
            HeadStroke(layout: layout, canvas: canvas)
        }
    }
}

private struct HeadFill: View {
    let layout: StanceLayout
    let canvas: CGSize

    var body: some View {
        let diameter = layout.headRadius * 2 * canvas.width
        Circle()
            .frame(width: diameter, height: diameter)
            .position(layout.head.scaled(to: canvas))
    }
}

private struct HeadStroke: View {
    let layout: StanceLayout
    let canvas: CGSize

    var body: some View {
        let diameter = layout.headRadius * 2 * canvas.width
        Circle()
            .strokeBorder(Color.fairwayGreen.opacity(0.9), lineWidth: 2)
            .frame(width: diameter, height: diameter)
            .position(layout.head.scaled(to: canvas))
    }
}

// MARK: - Limb pieces

private struct LimbCapsule: View {
    let limb: LimbSegment
    let canvas: CGSize

    var body: some View {
        let geom = limb.geometry(in: canvas)
        Capsule()
            .frame(width: geom.thickness, height: geom.length)
            .rotationEffect(.radians(geom.angle))
            .position(geom.center)
    }
}

private struct LimbCapsuleStroke: View {
    let limb: LimbSegment
    let canvas: CGSize

    var body: some View {
        let geom = limb.geometry(in: canvas)
        Capsule()
            .stroke(Color.fairwayGreen.opacity(0.85), lineWidth: 2)
            .frame(width: geom.thickness, height: geom.length)
            .rotationEffect(.radians(geom.angle))
            .position(geom.center)
    }
}

private struct KeypointDot: View {
    let delayStep: Int

    @State private var on: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: on ? 22 : 16, height: on ? 22 : 16)
            Circle()
                .fill(Color.fairwayGreen)
                .frame(width: 9, height: 9)
                .shadow(color: Color.fairwayGreen.opacity(0.95), radius: on ? 9 : 4)
            Circle()
                .stroke(Color.white.opacity(0.95), lineWidth: 1.4)
                .frame(width: 9, height: 9)
        }
        .opacity(on ? 1.0 : 0.85)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.6)
                .repeatForever(autoreverses: true)
                .delay(Double(delayStep) * 0.08)
            ) {
                on = true
            }
        }
    }
}

// MARK: - Geometry helpers

private extension CGPoint {
    func scaled(to size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }
}

private extension LimbSegment {
    struct Geometry {
        let center: CGPoint
        let length: CGFloat
        let thickness: CGFloat
        let angle: CGFloat
    }

    func geometry(in canvas: CGSize) -> Geometry {
        let s = start.scaled(to: canvas)
        let e = end.scaled(to: canvas)
        let dx = e.x - s.x
        let dy = e.y - s.y
        let length = max(sqrt(dx * dx + dy * dy), thickness * canvas.width)
        return Geometry(
            center: CGPoint(x: (s.x + e.x) / 2, y: (s.y + e.y) / 2),
            length: length,
            thickness: thickness * canvas.width,
            angle: atan2(dy, dx) - .pi / 2
        )
    }
}

#Preview("Face-On") {
    ZStack {
        Color.black.opacity(0.7)
        GolferSilhouetteView(stance: .faceOn)
            .frame(width: 240, height: 480)
    }
}

#Preview("Down the Line") {
    ZStack {
        Color.black.opacity(0.7)
        GolferSilhouetteView(stance: .downTheLine)
            .frame(width: 240, height: 480)
    }
}
