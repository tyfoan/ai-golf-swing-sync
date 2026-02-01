//
//  SpeedButton.swift
//  golf-sync-swing
//
//  Playback speed indicator button for recording view
//

import SwiftUI

struct SpeedButton: View {
    let speed: Float

    var body: some View {
        Button(action: {}) {
            Text(String(format: "%.1fx", speed))
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Color.gray.opacity(0.5))
                .clipShape(Circle())
        }
    }
}

#Preview {
    HStack {
        SpeedButton(speed: 0.5)
        SpeedButton(speed: 1.0)
        SpeedButton(speed: 2.0)
    }
    .padding()
    .background(Color.black)
}
