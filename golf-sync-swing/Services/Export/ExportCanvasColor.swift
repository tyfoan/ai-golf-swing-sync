//
//  ExportCanvasColor.swift
//  golf-sync-swing
//
//  The colour of an export canvas wherever no swing covers it — the seam between split
//  cells: the brand's near-black green instead of flat black. The editor paints the
//  same colour behind its tiles.
//

import CoreImage
import SwiftUI

nonisolated enum ExportCanvasColor {
    static let red: CGFloat = 0.055
    static let green: CGFloat = 0.078
    static let blue: CGFloat = 0.067

    static var ciColor: CIColor {
        CIColor(red: red, green: green, blue: blue)
    }
}

extension Color {
    static let exportCanvas = Color(
        red: ExportCanvasColor.red, green: ExportCanvasColor.green, blue: ExportCanvasColor.blue
    )
}
