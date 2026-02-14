//
//  SkeletonToggleButton.swift
//  golf-sync-swing
//
//  Floating toggle button for enabling/disabling skeleton overlay.
//  Uses figure.stand SF Symbol, green tint when active.
//

import SwiftUI

struct SkeletonToggleButton: View {
    @Binding var isActive: Bool

    var body: some View {
        Button { isActive.toggle() } label: {
            Image(systemName: "figure.stand")
                .font(.body)
                .foregroundStyle(isActive ? Color.fairwayGreen : .white.opacity(0.6))
                .frame(width: 40, height: 40)
                .background(isActive ? Color.fairwayGreen.opacity(0.2) : Color.white.opacity(0.1))
                .clipShape(Circle())
        }
    }
}
