#!/usr/bin/env swift

//
//  extract_youtube_snapshots.swift
//
//  Extracts pose frames from 50 youtube-tests videos using Vision framework.
//  Reads ground_truth.json + GolfDB bboxes, writes snapshot JSON + manifest.
//
//  Usage: swift extract_youtube_snapshots.swift
//

import AVFoundation
import Foundation
import Vision

// MARK: - Models

struct JointPosition: Codable {
    let x: CGFloat
    let y: CGFloat
    let confidence: Float
}

struct SerializablePoseFrame: Codable {
    let timestamp: TimeInterval
    let joints: [String: JointPosition]
}

struct GroundTruthEntry: Codable {
    let filename: String
    let youtube_id: String
    let golfdb_index: Int
    let player: String
    let club: String
    let view: String
    let fps: Int
    let impact_time_sec: Double
}

struct ManifestEntry: Codable {
    let file: String
    let type: String
    let impactTime: Double
    let player: String
    let club: String
    let angle: String
}

// MARK: - Configuration

let sampleRate: Double = 15
let minimumConfidence: Float = 0.1

let trackedJoints: [VNHumanBodyPoseObservation.JointName] = [
    .leftWrist, .rightWrist,
    .leftShoulder, .rightShoulder,
    .leftHip, .rightHip,
    .leftElbow, .rightElbow,
    .neck,
    .leftAnkle, .rightAnkle,
]

// MARK: - Bounding Boxes (from GolfDB)

let bboxes: [String: [Double]] = {
    let json = """
    {
      "ra887418NaA": [0.1578125, 0.3208333, 0.3476563, 0.6430556],
      "YqsCyYTKpZg": [0.0851563, 0.0006944, 0.5976563, 0.9951389],
      "1dSKw-krBIU": [0.3945313, 0.0006944, 0.35, 0.98125],
      "ZQjY2Ie4V50": [0.0890625, 0.0006944, 0.5195313, 1.0],
      "04d08bM6-6U": [0.2125, 0.05, 0.6, 0.9208333],
      "7dI2HeBChks": [0.2765625, 0.1847222, 0.3796875, 0.6861111],
      "n1r99BGuW8k": [0.1132813, 0.0006944, 0.6765625, 1.0],
      "3wru0WH0buk": [0.128125, 0.0006944, 0.8304688, 0.9895833],
      "3YZJYaJIJR4": [0.0398438, 0.0180556, 0.4960938, 0.9305556],
      "bj4Gc7jm5hY": [0.0757813, 0.0006944, 0.7710938, 0.9743056],
      "bwAvpekt8xY": [0.1242188, 0.0006944, 0.76875, 0.9159722],
      "wIiLM8ufWVI": [0.1125, 0.0347222, 0.4632813, 0.9291667],
      "D4uV1bZxaek": [0.0335938, 0.0006944, 0.5703125, 1.0],
      "ZivMJ6nSS-E": [0.25625, 0.0006944, 0.3601563, 0.9493056],
      "vaoD7yodCF4": [0.1945313, 0.0006944, 0.4625, 0.94375],
      "2Tj5jJ1Kh_Q": [0.159375, 0.0006944, 0.7054688, 0.9520833],
      "blonNcv1yas": [0.1140625, 0.0006944, 0.6726563, 0.9798611],
      "hoq35-zbmVk": [0.1523438, 0.0458333, 0.7164063, 0.9166667],
      "U2iNjzyTIJE": [0.2453125, 0.1291667, 0.34375, 0.8236111],
      "xS9NnBGgtjg": [0.059375, 0.0006944, 0.5796875, 0.9993056],
      "_MnmzCJCZRo": [0.0003906, 0.0006944, 0.5949219, 0.9701389],
      "_rFatlaZhEQ": [0.0578125, 0.0006944, 0.8328125, 1.0],
      "WPap6OmEyuE": [0.08125, 0.0006944, 0.5765625, 0.9895833],
      "eQEdf5KMyzM": [0.1296875, 0.0006944, 0.5640625, 0.9548611],
      "-x6fBaulaWU": [0.096875, 0.0006944, 0.79375, 0.9965278],
      "RiEUPJNPY_Y": [0.4367188, 0.0006944, 0.40625, 0.9590278],
      "8HJXWpyYWVE": [0.5054688, 0.0006944, 0.4949219, 0.99375],
      "dodETKV2Xpg": [0.0765625, 0.0006944, 0.8296875, 0.9923611],
      "9pp7eRBOCso": [0.0640625, 0.0006944, 0.5257813, 0.9951389],
      "RibG0A13urY": [0.1523438, 0.0006944, 0.4890625, 0.9923611],
      "CuAL_6U7_aQ": [0.2015625, 0.0006944, 0.684375, 0.9604167],
      "HHPJ-KlWmWg": [0.2148438, 0.0006944, 0.3117188, 0.90625],
      "4H2k5sHRqUU": [0.5015625, 0.0006944, 0.4382813, 0.9770833],
      "iMmoQ6xPY_U": [0.1070313, 0.0006944, 0.4414063, 0.9965278],
      "lJTm53jHTiY": [0.1390625, 0.0347222, 0.6257813, 0.9388889],
      "D12euvW55Ns": [0.1039063, 0.0006944, 0.7851563, 0.9840278],
      "gdoWMR-tauc": [0.0835938, 0.0006944, 0.7890625, 0.9826389],
      "shmXjle1rR0": [0.1523438, 0.0916667, 0.43125, 0.8736111],
      "wrvEURqD-GI": [0.378125, 0.0006944, 0.4664063, 0.9868056],
      "H9MWcs3YS-I": [0.19375, 0.0006944, 0.709375, 0.9520833],
      "7DR3pFxkPVg": [0.1648438, 0.0006944, 0.46875, 1.0],
      "IVRbQrq2JHo": [0.1734375, 0.0708333, 0.5984375, 0.9277778],
      "C4Vt3X8P6xs": [0.1875, 0.0006944, 0.340625, 0.9215278],
      "07lqNiTJVqc": [0.0804688, 0.0006944, 0.5382813, 0.9618056],
      "SVM8DLYNeK0": [0.1875, 0.0006944, 0.6429688, 0.94375],
      "bOcZP5_fPxo": [0.0609375, 0.0006944, 0.6054688, 0.9979167],
      "qqF9qeNzqTA": [0.1914063, 0.0006944, 0.60625, 0.99375],
      "KkB9KbBTb4c": [0.0828125, 0.0006944, 0.8195313, 0.9854167],
      "yfCt0Hkwues": [0.1273438, 0.0006944, 0.4507813, 0.9715278],
      "GXn3A0IuWsE": [0.1257813, 0.0958333, 0.6601563, 0.8861111]
    }
    """
    return try! JSONDecoder().decode([String: [Double]].self, from: json.data(using: .utf8)!)
}()

// MARK: - Paths

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let videosDir = projectRoot.appendingPathComponent("golf-sync-swingTests/youtube-tests")
let outputDir = videosDir.appendingPathComponent("snapshots")

// MARK: - Main

func main() throws {
    let gtURL = videosDir.appendingPathComponent("youtube_ground_truth.json")
    let gtData = try Data(contentsOf: gtURL)
    let entries = try JSONDecoder().decode([GroundTruthEntry].self, from: gtData)

    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    var manifest: [ManifestEntry] = []
    var successCount = 0

    for (i, entry) in entries.enumerated() {
        let videoURL = videosDir.appendingPathComponent(entry.filename)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("[\(i+1)/\(entries.count)] SKIP: \(entry.filename) not found")
            continue
        }

        let bbox = bboxes[entry.youtube_id]
        let bboxRect: CGRect
        if let b = bbox {
            bboxRect = CGRect(x: b[0], y: b[1], width: b[2], height: b[3])
        } else {
            bboxRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        print("[\(i+1)/\(entries.count)] \(entry.player) (\(entry.club), \(entry.view))...", terminator: " ")
        fflush(stdout)

        let frames = extractFrames(from: videoURL, bbox: bboxRect)

        let snapshotName = "\(entry.youtube_id).json"
        let outputFile = outputDir.appendingPathComponent(snapshotName)
        let data = try encoder.encode(frames)
        try data.write(to: outputFile)

        let withJoints = frames.filter { !$0.joints.isEmpty }.count
        print("\(frames.count) frames, \(withJoints) with joints")

        manifest.append(ManifestEntry(
            file: snapshotName,
            type: "swing",
            impactTime: entry.impact_time_sec,
            player: entry.player,
            club: entry.club,
            angle: entry.view
        ))
        successCount += 1
    }

    let manifestURL = outputDir.appendingPathComponent("youtube_manifest.json")
    let manifestData = try encoder.encode(manifest)
    try manifestData.write(to: manifestURL)

    print("\nDone: \(successCount)/\(entries.count) videos extracted")
    print("Snapshots: \(outputDir.path)")
    print("Manifest:  \(manifestURL.path)")
}

// MARK: - Extraction

func extractFrames(from videoURL: URL, bbox: CGRect) -> [SerializablePoseFrame] {
    let asset = AVURLAsset(url: videoURL)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.appliesPreferredTrackTransform = true

    let duration = CMTimeGetSeconds(asset.duration)
    let frameCount = Int(duration * sampleRate)
    var frames: [SerializablePoseFrame] = []

    for i in 0..<frameCount {
        let timestamp = Double(i) / sampleRate
        let time = CMTimeMakeWithSeconds(timestamp, preferredTimescale: 600)

        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            frames.append(SerializablePoseFrame(timestamp: timestamp, joints: [:]))
            continue
        }

        let cropped = cropToBBox(cgImage, bbox: bbox)
        frames.append(extractPose(from: cropped, at: timestamp))
    }

    return frames
}

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

        joints[jointName.rawValue.rawValue] = JointPosition(
            x: point.location.x,
            y: point.location.y,
            confidence: point.confidence
        )
    }

    return SerializablePoseFrame(timestamp: timestamp, joints: joints)
}

// MARK: - Run

try main()
