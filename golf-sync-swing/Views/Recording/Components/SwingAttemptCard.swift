//
//  SwingAttemptCard.swift
//  golf-sync-swing
//
//  Card view for displaying a detected swing attempt during recording
//

import SwiftUI

struct SwingAttemptCard: View {
    let swingNumber: Int
    let confidence: Double
    let isFavorite: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.fairwayGreen : Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)

                VStack(spacing: 2) {
                    Text("#\(swingNumber)")
                        .font(.headline.bold())
                        .foregroundStyle(.white)

                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
            }

            // Confidence indicator
            HStack(spacing: 2) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(confidence > Double(i) * 0.33 ? Color.fairwayGreen : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .contentShape(Rectangle()) // Ensure entire card is tappable
    }
}

#Preview {
    HStack {
        SwingAttemptCard(swingNumber: 1, confidence: 0.9, isFavorite: false, isSelected: false)
        SwingAttemptCard(swingNumber: 2, confidence: 0.6, isFavorite: true, isSelected: true)
        SwingAttemptCard(swingNumber: 3, confidence: 0.3, isFavorite: false, isSelected: false)
    }
    .padding()
    .background(Color.black)
}
