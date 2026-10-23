//
//  ExportCanvasColor.swift
//  golf-sync-swing
//
//  The colour of an export canvas wherever no swing covers it: the app's cream
//  (`Color.sandLight`), so a shared clip looks like the comparison screen it came from.
//  The editor paints the same colour behind its tiles.
//

import CoreImage
import SwiftUI

nonisolated enum ExportCanvasColor {
    static let red: CGFloat = 0.996
    static let green: CGFloat = 0.98
    static let blue: CGFloat = 0.878

    static var ciColor: CIColor {
        CIColor(red: red, green: green, blue: blue)
    }
}

extension Color {
    static let exportCanvas = Color(
        red: ExportCanvasColor.red, green: ExportCanvasColor.green, blue: ExportCanvasColor.blue
    )
}
