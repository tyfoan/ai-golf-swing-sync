//
//  SwingEditorSheet.swift
//  golf-sync-swing
//

import SwiftUI
import AVKit
import os

struct SwingEditorSheet: View {
    let video: SwingVideo
    let existingSwing: SwingMarker?
    let onSave: (TimeInterval, TimeInterval, TimeInterval) -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?

    @State private var startTime: TimeInterval
    @State private var contactTime: TimeInterval
    @State private var endTime: TimeInterval
    @State private var player: AVPlayer?
    @State private var currentFrame: UIImage?

    /// One generator for the whole sheet. `onSeek` fires on every drag tick, and building a fresh
    /// AVURLAsset + AVAssetImageGenerator per tick meant dozens of concurrent exact-frame decodes.
    @State private var frameGenerator: AVAssetImageGenerator?

    /// In-flight preview decode. Cancelled before each new one so a slow earlier request cannot
    /// land after a newer one and jerk the preview backwards.
    @State private var frameTask: Task<Void, Never>?

    init(video: SwingVideo, existingSwing: SwingMarker? = nil, onSave: @escaping (TimeInterval, TimeInterval, TimeInterval) -> Void, onCancel: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.video = video
        self.existingSwing = existingSwing
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete

        // Initialize with existing swing or default positions
        if let swing = existingSwing {
            _startTime = State(initialValue: swing.startTime)
            _contactTime = State(initialValue: swing.contactTime)
            _endTime = State(initialValue: swing.endTime)
        } else {
            // Default: spread markers across the video
            let duration = video.duration
            _startTime = State(initialValue: duration * 0.25)
            _contactTime = State(initialValue: duration * 0.5)
            _endTime = State(initialValue: duration * 0.75)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Edit Recording")
                    .font(.title)
                    .fontWeight(.bold)

                // Video preview frame
                ZStack {
                    if let image = currentFrame {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if let thumbnailData = video.thumbnailData,
                              let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .aspectRatio(16/9, contentMode: .fit)
                    }

                    // Current time overlay
                    VStack {
                        Spacer()
                        Text(formatTime(contactTime))
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .foregroundStyle(.white)
                            .cornerRadius(4)
                            .padding(8)
                    }
                }
                .padding(.horizontal)

                Text("Drag the sliders to align with the Start, Contact, and End of the swing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Marker slider
                SwingMarkerSlider(
                    startTime: $startTime,
                    contactTime: $contactTime,
                    endTime: $endTime,
                    duration: video.duration,
                    onSeek: seekToTime
                )
                .padding(.horizontal)

                // Time labels
                HStack {
                    VStack {
                        Circle()
                            .fill(Color.fairwayGreen)
                            .frame(width: 10, height: 10)
                        Text("Start", comment: "Label for the swing-start marker on the editor timeline (the moment club movement begins, not a Start button)")
                            .font(.caption2)
                        Text(formatTime(startTime))
                            .font(.caption)
                            .monospacedDigit()
                    }

                    Spacer()

                    VStack {
                        Circle()
                            .fill(Color.sand)
                            .frame(width: 10, height: 10)
                        Text("Contact", comment: "Label for the ball-contact marker on the editor timeline (the impact frame when club meets ball — NOT 'contact us' or a phone contact)")
                            .font(.caption2)
                        Text(formatTime(contactTime))
                            .font(.caption)
                            .monospacedDigit()
                    }

                    Spacer()

                    VStack {
                        Circle()
                            .fill(Color.fairwayGreen)
                            .frame(width: 10, height: 10)
                        Text("End", comment: "Label for the swing-end marker on the editor timeline (follow-through completion, not an End/Stop button)")
                            .font(.caption2)
                        Text(formatTime(endTime))
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 40)

                Spacer()

                // Buttons
                HStack(spacing: 16) {
                    Button {
                        onSave(startTime, contactTime, endTime)
                    } label: {
                        Text(existingSwing == nil ? "Add Swing" : "Save")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isValidTimeOrder ? Color.fairwayGreen : Color.gray)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .disabled(!isValidTimeOrder)

                    Button {
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal)

                if let onDelete = onDelete, existingSwing != nil {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Text("Delete Swing")
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .onAppear {
                setupPlayer()
            }
            .onDisappear {
                player?.pause()
                player?.replaceCurrentItem(with: nil)
                player = nil
                // Don't leave a decode running against a sheet that is gone.
                frameTask?.cancel()
                frameTask = nil
                frameGenerator?.cancelAllCGImageGeneration()
                frameGenerator = nil
            }
        }
    }

    private func setupPlayer() {
        guard video.fileExists else {
            AppLogger.ui.error("SwingEditorSheet: video file missing at \(video.localURL.path)")
            return
        }
        player = AVPlayer(url: video.localURL)
        seekToTime(contactTime)
    }

    private func seekToTime(_ time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        generateFrame(at: time)
    }

    private func generateFrame(at time: TimeInterval) {
        let generator = frameGenerator ?? makeFrameGenerator()
        if frameGenerator == nil { frameGenerator = generator }

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)

        // Supersede the previous request. Without this every drag tick raced to assign
        // `currentFrame`, and whichever decode happened to finish last won — which is how the
        // preview ended up jumping backwards mid-drag.
        frameTask?.cancel()
        frameTask = Task {
            do {
                let (image, _) = try await generator.image(at: cmTime)
                guard !Task.isCancelled else { return }
                await MainActor.run { currentFrame = UIImage(cgImage: image) }
            } catch is CancellationError {
                // Expected: a newer seek superseded this one.
            } catch {
                guard !Task.isCancelled else { return }
                AppLogger.ui.error("Error generating frame: \(error.localizedDescription)")
            }
        }
    }

    private func makeFrameGenerator() -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video.localURL))
        generator.appliesPreferredTrackTransform = true
        // Exact-frame accuracy is the point of this editor — the user is picking the impact
        // frame — so tolerance stays zero. Cost is controlled by reuse + cancellation instead.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return generator
    }

    private var isValidTimeOrder: Bool {
        startTime < contactTime && contactTime < endTime
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }
}
