//
//  StageCard.swift
//  golf-sync-swing
//
//  How a video sits on the cream stage: clipped to a rounded card with a hairline edge,
//  on a dark card with a soft shadow. One modifier, so every swing on the stage is framed
//  the same way.
//

import SwiftUI

struct StageCard: ViewModifier {
    static let cornerRadius: CGFloat = 20

    /// False drops the dark card underneath: a blended front pane's card would hide the
    /// swing behind it.
    var raised = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        content
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.black.opacity(0.06)) }
            .background {
                if raised {
                    shape.fill(Color.charcoal)
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
                }
            }
    }
}

extension View {
    func stageCard(raised: Bool = true) -> some View {
        modifier(StageCard(raised: raised))
    }
}
