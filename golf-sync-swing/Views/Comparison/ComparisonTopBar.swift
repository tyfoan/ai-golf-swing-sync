//
//  ComparisonTopBar.swift
//  golf-sync-swing
//
//  Close, the mode switcher, and export, above the stage.
//

import SwiftUI

struct ComparisonTopBar: View {
    let mode: ComparisonMode
    let canExport: Bool
    let onClose: () -> Void
    let onSelectMode: (ComparisonMode) -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            StageIconButton(symbol: "xmark", label: "Close comparison", action: onClose)
            Spacer(minLength: 0)
            ComparisonModeSwitcher(selection: mode, onSelect: onSelectMode)
            Spacer(minLength: 0)
            StageIconButton(symbol: "square.and.arrow.up", label: "Export comparison", action: onExport)
                .disabled(!canExport)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}
