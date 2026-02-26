#!/usr/bin/env swift
//
// train_classifier.swift
//
// Trains a Create ML Action Classifier for binary swing detection.
// Input: training_data_binary/ (swing/ + not_swing/ folders with 15-frame clips)
// Output: GolfSwingClassifier.mlmodel
//
// Usage: cd ml-training && swift train_classifier.swift
//

import Foundation
import CreateML

let trainingDir = URL(fileURLWithPath: "training_data_binary")
let outputPath = URL(fileURLWithPath: "GolfSwingClassifier.mlmodel")

print("Training Create ML Action Classifier (STGCN)")
print("  Source: \(trainingDir.path)")
print("  Output: \(outputPath.path)")
print("")

// Configure training parameters
// STGCN = Spatio-Temporal Graph Convolutional Network (pose-based)
let parameters = MLActionClassifier.ModelParameters(
    batchSize: 32,
    maximumIterations: 500,
    predictionWindowSize: 15,
    augmentationOptions: .horizontalFlip,
    targetFrameRate: 30
)

print("Parameters:")
print("  algorithm: STGCN (pose-based, 18 joints)")
print("  predictionWindowSize: 15 (0.5s at 30fps)")
print("  targetFrameRate: 30")
print("  maximumIterations: 500")
print("  augmentations: horizontalFlip")
print("")

do {
    print("Loading training data...")
    let trainingData = MLActionClassifier.DataSource.labeledDirectories(at: trainingDir)

    print("Training started (this may take 30-60 minutes)...")
    print("  Extracting body poses from 2,966 video clips...")
    print("")

    let classifier = try MLActionClassifier(
        trainingData: trainingData,
        parameters: parameters
    )

    // Print metrics
    print("\nTraining complete!")
    print("Training error: \(classifier.trainingMetrics.classificationError)")
    print("Validation error: \(classifier.validationMetrics.classificationError)")

    // Save model
    try classifier.write(to: outputPath)
    print("\nModel saved to: \(outputPath.path)")

    // Print file size
    let attrs = try FileManager.default.attributesOfItem(atPath: outputPath.path)
    let size = attrs[.size] as? Int64 ?? 0
    print("Model size: \(size / 1024)KB (\(size / 1024 / 1024)MB)")

} catch {
    print("ERROR: \(error)")
    exit(1)
}
