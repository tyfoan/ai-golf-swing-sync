//
//  AutoDetectModel.swift
//  golf-sync-swing
//
//  Model selection for swing detection (live recording + offline sync)
//

import Foundation

enum AutoDetectModel: String, CaseIterable, Identifiable, Sendable {
    case actionClassifier = "Action Classifier"
    case swingNet = "SwingNet (GolfDB)"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .actionClassifier: return "Classifier"
        case .swingNet: return "SwingNet"
        }
    }

    var description: String {
        switch self {
        case .actionClassifier: return "Pose-based swing classifier (any angle)"
        case .swingNet: return "GolfDB SwingNet video event detector"
        }
    }
}
