//
//  AutoDetectModel.swift
//  golf-sync-swing
//
//  Model selection for offline swing analysis (AUTO-DETECT / Auto-Sync)
//  Simplified to SwingNet-only implementation
//

import Foundation

enum AutoDetectModel: String, CaseIterable, Identifiable, Sendable {
    case swingNet = "SwingNet (GolfDB)"

    var id: String { rawValue }

    var shortName: String {
        return "SwingNet"
    }

    var description: String {
        return "GolfDB SwingNet video event detector"
    }
}


 
