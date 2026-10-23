//
//  StageBackdrop.swift
//  golf-sync-swing
//
//  Behind the comparison stage and the export editor: the warm cream of Recordings and
//  Compare, so opening a comparison stays inside the app's own look. The swings keep
//  dark cards of their own (ComparisonPane, EditorCanvas), which is what makes them the
//  brightest-contrast thing on screen.
//

import SwiftUI

struct StageBackdrop: View {
    var body: some View {
        Color.sandLight.ignoresSafeArea()
    }
}
