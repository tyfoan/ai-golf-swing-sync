//
//  CountdownView.swift
//  golf-sync-swing
//
//  Countdown overlay before recording starts
//

import SwiftUI

struct CountdownView: View {
    let count: Int
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1.5
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Countdown number
            Text("\(count)")
                .font(.system(size: 200, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                .scaleEffect(scale)
                .opacity(opacity)

            // Cancel button at bottom
            VStack {
                Spacer()

                Button(action: onCancel) {
                    Text("CANCEL")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                }
                .padding(.bottom, 60)
            }
        }
        .onChange(of: count) { _, _ in
            animateCountdown()
        }
        .onAppear {
            animateCountdown()
        }
    }

    private func animateCountdown() {
        // Reset state
        scale = 1.5
        opacity = 0

        // Animate in
        withAnimation(.easeOut(duration: 0.3)) {
            scale = 1.0
            opacity = 1.0
        }

        // Animate out
        withAnimation(.easeIn(duration: 0.3).delay(0.5)) {
            scale = 0.8
            opacity = 0
        }
    }
}

#Preview {
    ZStack {
        Color.gray

        CountdownView(count: 3, onCancel: {})
    }
}
