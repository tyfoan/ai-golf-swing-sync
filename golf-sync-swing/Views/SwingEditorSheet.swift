//
//  SwingEditorSheet.swift
//  golf-sync-swing
//

import SwiftUI
import AVKit

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

                Spacer()

                // Video preview frame
                ZStack {
                    if let image = currentFrame {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if let thumbnailData = video.thumbnailData,
                              let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 200, height: 150)
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
                        Text("Start")
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
                        Text("Contact")
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
                        Text("End")
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
                            .background(Color.fairwayGreen)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }

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
            }
        }
    }

    private func setupPlayer() {
        player = AVPlayer(url: video.localURL)
        seekToTime(contactTime)
    }

    private func seekToTime(_ time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        generateFrame(at: time)
    }

    private func generateFrame(at time: TimeInterval) {
        let asset = AVURLAsset(url: video.localURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)

        Task {
            do {
                let (image, _) = try await generator.image(at: cmTime)
                await MainActor.run {
                    currentFrame = UIImage(cgImage: image)
                }
            } catch {
                print("Error generating frame: \(error)")
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }
}
