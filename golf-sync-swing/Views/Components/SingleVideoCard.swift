//
//  SingleVideoCard.swift
//  golf-sync-swing
//
//  The single-video player's swing on the cream stage: a dark card cut to the video's
//  own shape, so the swing fills it edge to edge with no bands beside it, and the
//  floating actions in its bottom corner.
//

import AVFoundation
import SwiftUI

struct SingleVideoCard<Actions: View>: View {
    let player: AVPlayer
    /// The video's width over height. Nothing is drawn until it is known, so the card
    /// never shows in a wrong shape first.
    let aspectRatio: CGFloat?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        if let aspectRatio {
            ZStack(alignment: .bottomTrailing) {
                // Fill, not fit: the card already has the video's shape, and fill keeps a
                // rounding hair from showing as a sliver of card.
                PlayerLayerView(player: player, gravity: .resizeAspectFill)
                actions()
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .stageCard()
        }
    }
}
