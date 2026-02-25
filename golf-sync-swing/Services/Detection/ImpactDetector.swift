//
//  ImpactDetector.swift
//  golf-sync-swing
//
//  Finds the impact frame within a detected swing by searching for the
//  frame where the lead wrist reaches its lowest y-position.
//

import Foundation
import Vision

protocol ImpactDetecting: Sendable {
    func findImpactTime(in frames: [PoseFrame]) -> TimeInterval?
}

struct ImpactDetector: ImpactDetecting {

    private let minimumConfidence: Float = 0.3

    func findImpactTime(in frames: [PoseFrame]) -> TimeInterval? {
        var bestTime: TimeInterval?
        var lowestY: CGFloat = .greatestFiniteMagnitude

        for frame in frames {
            guard let wristY = lowestWristY(in: frame) else { continue }

            if wristY < lowestY {
                lowestY = wristY
                bestTime = frame.timestamp
            }
        }

        return bestTime
    }

    private func lowestWristY(in frame: PoseFrame) -> CGFloat? {
        let wristNames: [VNHumanBodyPoseObservation.JointName] = [.leftWrist, .rightWrist]

        let yValues = wristNames.compactMap { name -> CGFloat? in
            guard let joint = frame.joint(name),
                  joint.confidence > minimumConfidence else { return nil }
            return joint.y
        }

        return yValues.min()
    }
}
