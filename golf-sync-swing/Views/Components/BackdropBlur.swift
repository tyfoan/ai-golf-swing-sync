//
//  BackdropBlur.swift
//  golf-sync-swing
//
//  The look of the bars around a fitted swing: the clip itself, cropped to cover,
//  blurred and dimmed under a dark material. Only the Stacked comparison pane uses it:
//  both swings must share one frame there, so the card cannot take a swing's shape.
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
