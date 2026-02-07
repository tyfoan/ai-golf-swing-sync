//
//  DetectorFactory.swift
//  golf-sync-swing
//
//  Factory for creating swing detectors.
//  Centralizes detector instantiation instead of scattering init calls.
//

import Foundation

enum DetectorFactory {

    static func makeDetector(for model: AutoDetectModel) -> any RealTimeSwingDetector {
        switch model {
        case .actionClassifier:
            return ActionClassifierDetector()
        case .swingNet:
            return SwingNetDetector()
        }
    }

    static func makeActionClassifier() -> ActionClassifierDetector {
        ActionClassifierDetector()
    }

    static func makeSwingNet() -> SwingNetDetector {
        SwingNetDetector()
    }
}
