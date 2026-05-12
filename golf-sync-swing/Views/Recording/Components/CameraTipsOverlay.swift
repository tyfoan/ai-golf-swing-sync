//
//  CameraTipsOverlay.swift
//  golf-sync-swing
//
//  Swipeable tips overlay for the camera tab
//

import SwiftUI

struct CameraTipsOverlay: View {
    @State private var currentPage = 0
    @Binding var isVisible: Bool

    private let tips = [
        RecordingTip(
            number: 1,
            title: String(localized: "Camera Placement", comment: "Recording tip card title"),
            description: String(localized: "Make sure your camera is directly in front of you (facing your swing), or facing the direction the ball will go. Your phone can be on the ground or on a stand, just as long as it's propped up to capture your whole body for the entire swing.", comment: "Recording tip 1 body — full instructions overlay version"),
            systemIcon: "iphone.gen3"
        ),
        RecordingTip(
            number: 2,
            title: String(localized: "Lighting", comment: "Recording tip card title"),
            description: String(localized: "Record in well-lit conditions for best results. Natural daylight works best for pose detection. Avoid backlit situations where you appear as a silhouette.", comment: "Recording tip 2 body — full instructions overlay version"),
            systemIcon: "sun.max.fill"
        ),
        RecordingTip(
            number: 3,
            title: String(localized: "Distance", comment: "Recording tip card title (distance from camera to subject)"),
            description: String(localized: "Stand 8-12 feet from the camera for optimal pose tracking. Make sure your full body is visible throughout the entire swing motion.", comment: "Recording tip 3 body — full instructions overlay version"),
            systemIcon: "ruler.fill"
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Dismiss button
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Header
            Text("Best Practices")
                .font(.title2.bold())
                .padding(.top, 8)

            // Swipeable tips
            TabView(selection: $currentPage) {
                ForEach(Array(tips.enumerated()), id: \.element.id) { index, tip in
                    TipPageCard(tip: tip)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 260)

            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<tips.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.fairwayGreen : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: -5)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Tip Model

struct RecordingTip: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    let description: String
    let systemIcon: String
}

// MARK: - Tip Page Card

struct TipPageCard: View {
    let tip: RecordingTip

    var body: some View {
        VStack(spacing: 16) {
            // Tip card
            VStack(alignment: .leading, spacing: 12) {
                Text("Tip #\(tip.number) - \(tip.title)")
                    .font(.headline)

                Text(tip.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Icon illustration
                HStack {
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.fairwayGreen, lineWidth: 2)
                            .frame(width: 80, height: 120)

                        Image(systemName: tip.systemIcon)
                            .font(.system(size: 36))
                            .foregroundStyle(Color.fairwayGreen)
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(20)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            CameraTipsOverlay(isVisible: .constant(true))
        }
    }
}
