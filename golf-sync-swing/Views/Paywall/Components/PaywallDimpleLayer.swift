//
//  PaywallDimpleLayer.swift
//  golf-sync-swing
//
//  Subtle hex-grid golf-ball dimples drawn over the paywall background,
//  mirroring the texture used in the app icon (DimpleLayer in
//  scripts/generate_app_icon.swift). Lower opacity + smaller spacing so
//  it reads as decorative texture, not noise.
//

import SwiftUI

struct PaywallDimpleLayer: View {

    private let dimpleDiameter: CGFloat = 26
    private let spacing: CGFloat = 38
    private let darkerColor = Color(red: 0.024, green: 0.094, blue: 0.071).opacity(0.55)
    private let lighterColor = Color(red: 0.102, green: 0.271, blue: 0.212).opacity(0.40)

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / spacing) + 3
            let rows = Int(size.height / spacing) + 3
            for row in -1..<rows {
                for col in -1..<cols {
                    let xOffset: CGFloat = (row % 2 == 0) ? 0 : spacing / 2
                    let cx = CGFloat(col) * spacing + xOffset
                    let cy = CGFloat(row) * spacing
                    let rect = CGRect(
                        x: cx - dimpleDiameter / 2,
                        y: cy - dimpleDiameter / 2,
                        width: dimpleDiameter,
                        height: dimpleDiameter
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(darkerColor))

                    let highlightRect = rect.insetBy(dx: 2.5, dy: 2.5)
                        .offsetBy(dx: -1.5, dy: -1.5)
                    context.stroke(
                        Path(ellipseIn: highlightRect),
                        with: .color(lighterColor),
                        lineWidth: 0.8
                    )
                }
            }
        }
        .blendMode(.multiply)
        .allowsHitTesting(false)
    }
}
