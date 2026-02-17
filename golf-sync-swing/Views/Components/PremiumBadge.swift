//
//  PremiumBadge.swift
//  golf-sync-swing
//
//  A small "PRO" badge overlay for locked features.
//

import SwiftUI

struct PremiumBadge: View {

    var body: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.sand, in: Capsule())
    }
}
