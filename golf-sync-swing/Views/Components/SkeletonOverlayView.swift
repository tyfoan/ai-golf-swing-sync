//
//  SkeletonOverlayView.swift
//  golf-sync-swing
//
//  Draws body pose skeleton (joints + connection lines) using SwiftUI Canvas.
//  Renders efficiently without view hierarchy churn.
//  Passes touches through via .allowsHitTesting(false).
//
//  Four passes, back to front, over two paths built once per frame: two white haloes, a dark
//  rim, then the white core. The order is the point — every dark stroke is laid down before
//  any white one, so the rim can never nick the limb it exists to separate from the
//  background. Without that rim a white skeleton disappears into a bright sky or a white
//  wall; with it, the same skeleton reads on an overexposed frame.
//
//  The halo is stacked translucent strokes rather than `GraphicsContext.addFilter(.shadow:)`.
//  This canvas is redrawn on every pose frame — 30 a second, while the capture pipeline is
//  already busy — and a shadow filter buys its soft falloff with an offscreen Gaussian pass
//  over the skeleton's whole bounding box. Two hard-edged haloes approximate the falloff for
//  the price of two more vector strokes and no offscreen at all.
//

import SwiftUI
import Vision

struct SkeletonOverlayView: View {
    let jointMap: BodyJointMap?

    /// Owns the Y-flip, aspect-fill crop and mirroring. See `PoseOverlayGeometry`.
    let geometry: PoseOverlayGeometry

    /// Drawing's own gate, deliberately not the detector's `minimumConfidence` and deliberately
    /// parked at the same permissive floor. The detector extracts every joint above 0.1 and
    /// leaves its consumers to re-filter — `PoseHeuristics` and `ImpactDetector` decide on
    /// wrists above 0.3 — so drawing already gates lower than detection decides, which is the
    /// right way round: a knee Vision is only half sure of still belongs on screen, while a
    /// swing must not be called on one.
    ///
    /// Raising this is how the legs vanish again. 0.1–0.2 is exactly where a knee at the bottom
    /// of the frame lives, and because a bone needs both of its ends, one borderline knee
    /// erases an entire leg. Pose cannot be exercised on the simulator, so move this number
    /// only with a device in hand.
    private let minimumDrawingConfidence: Float = 0.1

    var body: some View {
        Canvas { context, size in
            guard let jointMap else { return }
            let metrics = SkeletonMetrics(viewSize: size)
            let paths = SkeletonPaths(
                points: drawablePoints(in: jointMap, size: size),
                jointRadius: metrics.jointRadius
            )
            draw(paths, metrics: metrics, in: context)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drawing

    /// Back to front. Nothing here loops over joints, so the whole skeleton costs eight
    /// vector operations no matter how many of them Vision returned.
    private func draw(_ paths: SkeletonPaths, metrics: SkeletonMetrics, in context: GraphicsContext) {
        stroke(paths, layer: metrics.outerHalo, in: context)
        stroke(paths, layer: metrics.innerHalo, in: context)
        stroke(paths, layer: metrics.rim, in: context)
        context.stroke(paths.bones, with: .color(.white), style: Self.strokeStyle(width: metrics.boneWidth))
        context.fill(paths.joints, with: .color(.white))
    }

    private func stroke(_ paths: SkeletonPaths, layer: SkeletonLayer, in context: GraphicsContext) {
        let shading = GraphicsContext.Shading.color(layer.color)
        context.stroke(paths.bones, with: shading, style: Self.strokeStyle(width: layer.boneWidth))
        context.stroke(paths.joints, with: shading, style: Self.strokeStyle(width: layer.jointWidth))
    }

    private static func strokeStyle(width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    // MARK: - Coordinate Mapping

    /// Resolves every joint the frame carries, once. Both paths want the same answers, and
    /// `geometry.point(for:in:)` runs 30 times a second alongside a busy capture pipeline.
    ///
    /// The gates every drawn point passes live here. A joint Vision is unsure of is dropped
    /// rather than dimmed, and so is a coordinate that came back non-finite: a glow smeared
    /// across a garbage point is worse than a missing limb, and one bad point in a shared path
    /// takes the whole skeleton with it, where the old path-per-segment drawing only lost the
    /// segment.
    private func drawablePoints(
        in jointMap: BodyJointMap,
        size: CGSize
    ) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        var points: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        points.reserveCapacity(jointMap.joints.count)

        for (name, joint) in jointMap.joints where joint.confidence >= minimumDrawingConfidence {
            let mapped = geometry.point(for: joint.position, in: size)
            guard mapped.x.isFinite, mapped.y.isFinite else { continue }
            points[name] = mapped
        }

        return points
    }
}

// MARK: - Paths

/// The two paths every pass strokes, built together and built once — batching is what makes
/// four passes over a live preview affordable.
///
/// A bone is drawn only where both of its ends resolved, and a dot only where a bone landed on
/// it. That second rule is the fix for a skeleton that "draws badly": previously every joint
/// above the confidence floor drew its own dot, so an ankle whose knee Vision missed left a
/// haloed white spot floating in the grass, and a barely-detected golfer was a scatter of
/// unconnected dots. Dots without limbs read as a broken overlay, so a frame that yields no
/// complete bone now draws nothing at all.
private struct SkeletonPaths {
    let bones: Path
    let joints: Path

    init(points: [VNHumanBodyPoseObservation.JointName: CGPoint], jointRadius: CGFloat) {
        var bones = Path()
        var connected: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

        for (start, end) in BodyJointMap.connections {
            guard let from = points[start], let to = points[end] else { continue }
            bones.move(to: from)
            bones.addLine(to: to)
            connected[start] = from
            connected[end] = to
        }

        self.bones = bones
        self.joints = Self.dots(at: connected.values, radius: jointRadius)
    }

    /// Keyed by joint name above, so the shoulder that carries three bones is still one dot:
    /// the same ellipse added three times is three times the vector work for no extra pixels.
    private static func dots(at centers: some Collection<CGPoint>, radius: CGFloat) -> Path {
        var path = Path()
        for center in centers {
            path.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
        return path
    }
}

// MARK: - Style

/// One back-to-front pass: the same two paths, one colour, one width each.
private struct SkeletonLayer {
    let color: Color
    let boneWidth: CGFloat
    let jointWidth: CGFloat
}

/// Every dimension is authored in points against a 390pt-wide canvas and scaled from there,
/// so the skeleton keeps its proportions if it is ever drawn somewhere smaller than the
/// full-screen preview instead of collapsing into a white blob.
private struct SkeletonMetrics {
    private static let baselineWidth: CGFloat = 390

    let boneWidth: CGFloat
    let jointRadius: CGFloat
    private let scale: CGFloat

    init(viewSize: CGSize) {
        let shortEdge = min(viewSize.width, viewSize.height)
        scale = min(max(shortEdge / Self.baselineWidth, 0.5), 2)
        boneWidth = 4 * scale
        jointRadius = 6 * scale
    }

    var outerHalo: SkeletonLayer { layer(.white.opacity(0.10), reaching: 8 * scale) }

    var innerHalo: SkeletonLayer { layer(.white.opacity(0.22), reaching: 3 * scale) }

    /// The hairline of dark that keeps a white skeleton off a white background. Opaque enough
    /// to still read as an edge at 1pt: the frame this exists for is an overexposed one, and
    /// a rim that only half commits renders as mid-grey on white and disappears anyway.
    var rim: SkeletonLayer { layer(.black.opacity(0.7), reaching: scale) }

    /// `extent` is how far past the white core each pass reaches, and both widths are derived
    /// so that it means the same thing for a line and for a circle. A stroke straddles its
    /// path: a bone therefore grows by `extent` on each side of its centre line, while a
    /// joint's ring is `extent * 2` wide — centred ON the circle, so it reaches exactly
    /// `extent` beyond the dot's edge. Widening it to fill in to the middle instead would
    /// put the rim's outer edge at `jointRadius + extent` MORE than intended, hanging a dark
    /// blob off every joint. The hollow middle never shows: the white core fills it last.
    private func layer(_ color: Color, reaching extent: CGFloat) -> SkeletonLayer {
        SkeletonLayer(
            color: color,
            boneWidth: boneWidth + extent * 2,
            jointWidth: extent * 2
        )
    }
}
