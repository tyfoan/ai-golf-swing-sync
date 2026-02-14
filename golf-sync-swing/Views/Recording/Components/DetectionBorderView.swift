//
//  DetectionBorderView.swift
//  golf-sync-swing
//
//  Animated "filling" border that traces around PiP when a swing is detected.
//  Uses RoundedRectangle.trim to animate a stroke from 0 → 1 → 0.
//

import SwiftUI

struct DetectionBorderView: View {
    let isActive: Bool
    let cornerRadius: CGFloat

    @State private var trimEnd: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .trim(from: 0, to: trimEnd)
            .stroke(Color.fairwayGreen, lineWidth: 3)
            .onChange(of: isActive) { _, active in
                animateBorder(active: active)
            }
    }

    private func animateBorder(active: Bool) {
        guard active else {
            withAnimation(.easeOut(duration: 0.4)) { trimEnd = 0 }
            return
        }
        withAnimation(.easeInOut(duration: 0.8)) { trimEnd = 1.0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.easeOut(duration: 0.4)) { trimEnd = 0 }
        }
    }
}
