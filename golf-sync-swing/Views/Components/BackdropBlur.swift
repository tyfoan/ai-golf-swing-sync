//
//  BackdropBlur.swift
//  golf-sync-swing
//
//  The look of the bars around a fitted swing: the clip itself, cropped to cover,
//  blurred and dimmed under a dark material. Shared by the comparison panes and the
//  export editor's tiles, and matched by CellBackdrop in exported files.
//

import SwiftUI

extension View {
    func backdropBlurred() -> some View {
        overlay(Rectangle().fill(.thinMaterial))
            .overlay(Color.black.opacity(0.22))
            .environment(\.colorScheme, .dark)
            .accessibilityHidden(true)
    }
}
