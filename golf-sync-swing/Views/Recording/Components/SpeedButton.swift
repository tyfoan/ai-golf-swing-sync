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
            Text("\(formattedSpeed)x")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Color.gray.opacity(0.5))
                .clipShape(Circle())
        }
    }

    // Drop trailing zeros so 1.0 renders as "1" and 0.25 as "0.25" — same
    // visual contract as the old "%.2g" format, but locale-aware (e.g. "0,25"
    // in de-DE rather than "0.25").
    private var formattedSpeed: String {
        Double(speed).formatted(.number.precision(.fractionLength(0...2)))
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
