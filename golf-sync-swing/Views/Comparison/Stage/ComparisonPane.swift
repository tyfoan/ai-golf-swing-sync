//
//  ComparisonPane.swift
//  golf-sync-swing
//
//  One swing on the stage, with a chip naming whose swing it is. Usually the card is cut
//  to the swing's own shape and centred in the pane, so the clip fills it with no bands
//  beside it. Overlaid panes share one frame instead: the back one fills it, the clip
//  whole over a blurred copy of itself.
//

import AVFoundation
import SwiftUI

struct ComparisonPane: View {
    let player: AVPlayer
    let cutout: SlotCutout
    let label: PaneLabel
    var style = PaneStyle()

    var body: some View {
        if style.hugsSwing {
            swing(gravity: .fill)
                .aspectRatio(cutout.slot.size, contentMode: .fit)
                .stageCard()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                backdrop
                swing(gravity: .fit)
            }
            .stageCard(raised: style.showsBackdrop)
        }
    }

    private func swing(gravity: SlotGravity) -> some View {
        ZStack(alignment: style.chipAlignment) {
            CompositionSlotView(player: player, cutout: cutout, gravity: gravity)
                .opacity(style.videoOpacity)
            PaneLabelChip(label: label)
                .padding(10)
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if style.showsBackdrop {
            CompositionSlotView(player: player, cutout: cutout, gravity: .fill)
                .backdropBlurred()
        } else {
            Color.clear
        }
    }
}
