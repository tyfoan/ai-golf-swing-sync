//
//  GolferStance.swift
//  golf-sync-swing
//
//  Identity (label, icon, asset name) for a camera stance used by the
//  countdown positioning guide. Only `downTheLine` is rendered in the
//  current UI; `faceOn` is kept so re-enabling it later needs no asset
//  wiring work.
//

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

    /// Asset-catalog image name for the silhouette rendered behind the
    /// countdown digit.
    var assetName: String? {
        switch self {
        case .faceOn: return "golfer-face-on"
        case .downTheLine: return "golfer-down-the-line"
        }
    }
}
