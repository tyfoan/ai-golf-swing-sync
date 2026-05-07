#!/usr/bin/env swift

//
//  extract_snapshots.swift
//
//  Extracts pose frames from GolfDB test videos using Vision framework on macOS.
//  Writes SerializablePoseFrame JSON files for golden-snapshot validation.
//
//  Usage: swift extract_snapshots.swift
//

import AVFoundation
import Foundation
import Vision

// MARK: - Models (mirrors SerializablePoseFrame from test target)

struct JointPosition: Codable {
    let x: CGFloat
    let y: CGFloat
    let confidence: Float
}

struct SerializablePoseFrame: Codable {
    let timestamp: TimeInterval
    let joints: [String: JointPosition]
}

struct GroundTruth {
    let filename: String
    let bbox: CGRect
}

// MARK: - Configuration

let sampleRate: Double = 15
let minimumConfidence: Float = 0.1

let testVideos: [GroundTruth] = [
    GroundTruth(filename: "golfdb_f1BWA5F87Jc",
                bbox: CGRect(x: 0.098, y: 0.007, width: 0.405, height: 0.974)),
    GroundTruth(filename: "golfdb_iW323nsTGtU",
                bbox: CGRect(x: 0.293, y: 0.001, width: 0.422, height: 0.988)),
    GroundTruth(filename: "golfdb_4HzLO88ryCU",
                bbox: CGRect(x: 0.166, y: 0.001, width: 0.318, height: 0.986)),
    GroundTruth(filename: "golfdb_KR9Umr1GM-U",
                bbox: CGRect(x: 0.168, y: 0.001, width: 0.529, height: 0.983)),
    GroundTruth(filename: "golfdb_tpv8QUM0G0E",
                bbox: CGRect(x: 0.120, y: 0.001, width: 0.589, height: 0.996)),
]

let trackedJoints: [VNHumanBodyPoseObservation.JointName] = [
    .leftWrist, .rightWrist,
    .leftShoulder, .rightShoulder,
    .leftHip, .rightHip,
    .leftElbow, .rightElbow,
    .neck,
    .leftAnkle, .rightAnkle,
]

// MARK: - Extraction

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let outputDir = scriptDir.appendingPathComponent("snapshots", isDirectory: true)

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

for gt in testVideos {
    let videoURL = scriptDir.appendingPathComponent("\(gt.filename).mp4")
    guard FileManager.default.fileExists(atPath: videoURL.path) else {
        print("SKIP: \(gt.filename).mp4 not found")
        continue
    }

    let asset = AVURLAsset(url: videoURL)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.appliesPreferredTrackTransform = true

    let duration = CMTimeGetSeconds(asset.duration)
    let frameCount = Int(duration * sampleRate)

    var frames: [SerializablePoseFrame] = []
    var framesWithJoints = 0

    for i in 0..<frameCount {
        let timestamp = Double(i) / sampleRate
        let time = CMTimeMakeWithSeconds(timestamp, preferredTimescale: 600)

        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            frames.append(SerializablePoseFrame(timestamp: timestamp, joints: [:]))
            continue
        }

        let cropped = cropToBBox(cgImage, bbox: gt.bbox)
        let poseFrame = extractPose(from: cropped, at: timestamp)
        frames.append(poseFrame)

        if !poseFrame.joints.isEmpty {
            framesWithJoints += 1
        }
    }

    let snapshotName = gt.filename.replacingOccurrences(of: "golfdb_", with: "")
    let outputFile = outputDir.appendingPathComponent("\(snapshotName).json")
    let data = try encoder.encode(frames)
    try data.write(to: outputFile)

    print("OK: \(snapshotName).json — \(frames.count) frames, \(framesWithJoints) with joints")
}

print("\nSnapshots written to: \(outputDir.path)")

// MARK: - Helpers

func cropToBBox(_ image: CGImage, bbox: CGRect) -> CGImage {
    let w = CGFloat(image.width)
    let h = CGFloat(image.height)
    let cropRect = CGRect(
        x: bbox.origin.x * w,
        y: bbox.origin.y * h,
        width: bbox.size.width * w,
        height: bbox.size.height * h
    )
    return image.cropping(to: cropRect) ?? image
}

func extractPose(from cgImage: CGImage, at timestamp: TimeInterval) -> SerializablePoseFrame {
    let request = VNDetectHumanBodyPoseRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

    do {
        try handler.perform([request])
    } catch {
        return SerializablePoseFrame(timestamp: timestamp, joints: [:])
    }

    guard let observation = request.results?.first else {
        return SerializablePoseFrame(timestamp: timestamp, joints: [:])
    }

    var joints: [String: JointPosition] = [:]

    for jointName in trackedJoints {
        guard let point = try? observation.recognizedPoint(jointName),
              point.confidence > minimumConfidence else { continue }

        let key = jointName.rawValue.rawValue
        joints[key] = JointPosition(
            x: point.location.x,
            y: point.location.y,
            confidence: point.confidence
        )
    }

    return SerializablePoseFrame(timestamp: timestamp, joints: joints)
}
