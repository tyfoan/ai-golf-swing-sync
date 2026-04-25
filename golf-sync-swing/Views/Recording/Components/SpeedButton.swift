//
//  SpeedButton.swift
//  golf-sync-swing
//
//  Playback speed indicator button for recording view
//

import SwiftUI

struct SpeedButton: View {
    let speed: Float
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(String(format: "%.2gx", speed))
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
        SpeedButton(speed: 0.25) {}
        SpeedButton(speed: 0.5) {}
        SpeedButton(speed: 1.0) {}
    }
    .padding()
    .background(Color.black)
}
