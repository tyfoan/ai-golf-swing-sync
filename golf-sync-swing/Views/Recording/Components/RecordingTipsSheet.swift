//
//  RecordingTipsSheet.swift
//  golf-sync-swing
//
//  Tips sheet for optimal recording setup
//

import SwiftUI

struct RecordingTipsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TipCard(
                        number: 1,
                        title: "Camera Placement",
                        description: "Place your phone on a tripod or stable surface, facing your swing. Ensure your full body is visible."
                    )

                    TipCard(
                        number: 2,
                        title: "Lighting",
                        description: "Record in well-lit conditions. Natural daylight works best for pose detection."
                    )

                    TipCard(
                        number: 3,
                        title: "Distance",
                        description: "Stand 8-12 feet from the camera for optimal pose tracking."
                    )
                }
                .padding()
            }
            .navigationTitle("Recording Tips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct TipCard: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.fairwayGreen)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    RecordingTipsSheet()
}
