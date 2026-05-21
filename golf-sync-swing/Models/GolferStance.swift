//
//  GolferStance.swift
//  golf-sync-swing
//
//  Normalised (0-1) joint and limb coordinates used by GolferSilhouetteView
//  to draw a stylised golfer body for the countdown positioning guide.
//  Coordinates assume a vertical canvas: (0,0) top-left, (1,1) bottom-right.
//

import CoreGraphics
import Foundation

enum GolferStance: String, CaseIterable, Identifiable, Hashable {
    case faceOn
    case downTheLine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .faceOn: return String(localized: "Face-On", comment: "Golf stance label: face-on camera view (golfer looks toward the camera)")
        case .downTheLine: return String(localized: "Down the Line", comment: "Golf stance label: down-the-line camera view (camera looks along ball flight, golfer in profile)")
        }
    }

    var iconSystemName: String {
        switch self {
        case .faceOn: return "person.fill"
        case .downTheLine: return "figure.golf"
        }
    }

    /// Asset-catalog image name when a vector silhouette exists for this stance.
    /// `nil` falls back to the procedural capsule layout in `GolferSilhouetteView`.
    var assetName: String? {
        switch self {
        case .faceOn: return "golfer-face-on"
        case .downTheLine: return "golfer-down-the-line"
        }
    }

    var layout: StanceLayout {
        switch self {
        case .faceOn: return .faceOn
        case .downTheLine: return .downTheLine
        }
    }
}

/// Capsule-shaped limb between two normalised points with a given thickness.
struct LimbSegment: Hashable {
    let start: CGPoint
    let end: CGPoint
    let thickness: CGFloat
}

/// All geometry needed to render one stance. Capsules union naturally into a
/// silhouette when stacked with the same fill, head is drawn separately, and
/// keypoints sit on top with a breathing pulse.
struct StanceLayout {
    let head: CGPoint
    let headRadius: CGFloat
    let limbs: [LimbSegment]
    let club: LimbSegment?
    let keypoints: [CGPoint]
}

extension StanceLayout {
    static let faceOn = StanceLayout(
        head: CGPoint(x: 0.50, y: 0.11),
        headRadius: 0.072,
        limbs: [
            LimbSegment(start: CGPoint(x: 0.50, y: 0.22), end: CGPoint(x: 0.50, y: 0.56), thickness: 0.18),
            LimbSegment(start: CGPoint(x: 0.42, y: 0.24), end: CGPoint(x: 0.48, y: 0.54), thickness: 0.06),
            LimbSegment(start: CGPoint(x: 0.58, y: 0.24), end: CGPoint(x: 0.52, y: 0.54), thickness: 0.06),
            LimbSegment(start: CGPoint(x: 0.46, y: 0.56), end: CGPoint(x: 0.44, y: 0.94), thickness: 0.075),
            LimbSegment(start: CGPoint(x: 0.54, y: 0.56), end: CGPoint(x: 0.56, y: 0.94), thickness: 0.075)
        ],
        club: LimbSegment(
            start: CGPoint(x: 0.50, y: 0.56),
            end: CGPoint(x: 0.62, y: 0.93),
            thickness: 0.012
        ),
        keypoints: [
            CGPoint(x: 0.42, y: 0.24),
            CGPoint(x: 0.58, y: 0.24),
            CGPoint(x: 0.40, y: 0.40),
            CGPoint(x: 0.60, y: 0.40),
            CGPoint(x: 0.50, y: 0.55),
            CGPoint(x: 0.46, y: 0.56),
            CGPoint(x: 0.54, y: 0.56),
            CGPoint(x: 0.44, y: 0.76),
            CGPoint(x: 0.56, y: 0.76)
        ]
    )

    static let downTheLine = StanceLayout(
        head: CGPoint(x: 0.46, y: 0.13),
        headRadius: 0.072,
        limbs: [
            LimbSegment(start: CGPoint(x: 0.46, y: 0.24), end: CGPoint(x: 0.50, y: 0.55), thickness: 0.16),
            LimbSegment(start: CGPoint(x: 0.46, y: 0.26), end: CGPoint(x: 0.60, y: 0.55), thickness: 0.07),
            LimbSegment(start: CGPoint(x: 0.48, y: 0.56), end: CGPoint(x: 0.46, y: 0.93), thickness: 0.08),
            LimbSegment(start: CGPoint(x: 0.52, y: 0.56), end: CGPoint(x: 0.56, y: 0.93), thickness: 0.08)
        ],
        club: LimbSegment(
            start: CGPoint(x: 0.60, y: 0.55),
            end: CGPoint(x: 0.78, y: 0.93),
            thickness: 0.012
        ),
        keypoints: [
            CGPoint(x: 0.46, y: 0.26),
            CGPoint(x: 0.52, y: 0.42),
            CGPoint(x: 0.60, y: 0.55),
            CGPoint(x: 0.50, y: 0.56),
            CGPoint(x: 0.52, y: 0.74),
            CGPoint(x: 0.46, y: 0.74)
        ]
    )
}
