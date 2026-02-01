//
//  SwingRowView.swift
//  golf-sync-swing
//

import SwiftUI

struct SwingRowView: View {
    let swing: SwingMarker
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Swing number
            Text("\(index + 1)")
                .font(.headline)
                .frame(width: 30)
                .foregroundStyle(isSelected ? .white : .primary)

            // Time markers
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(formatTime(swing.startTime))
                        .font(.caption)
                        .monospacedDigit()

                    Text("→")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    Text(formatTime(swing.contactTime))
                        .font(.caption)
                        .monospacedDigit()

                    Text("→")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(formatTime(swing.endTime))
                        .font(.caption)
                        .monospacedDigit()
                }

                Text("Duration: \(formatDuration(swing.duration))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Edit button - separate hit target
            Button(action: onEdit) {
                Image(systemName: "pencil.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d.%02d", seconds, milliseconds)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        return String(format: "%.2fs", duration)
    }
}
