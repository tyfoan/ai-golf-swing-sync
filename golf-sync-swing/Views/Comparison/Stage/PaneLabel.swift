//
//  PaneLabel.swift
//  golf-sync-swing
//
//  Names the swing a pane shows: the pro and the club for a reference swing, "You" and
//  the day it was recorded for the user's own — so two of the user's swings still read
//  apart.
//

import Foundation

struct PaneLabel: Equatable {
    let title: String
    let detail: String

    init(video: SwingVideo) {
        guard let pro = video.proDescriptor else {
            title = String(localized: "You", comment: "Label on a comparison pane that shows the user's own swing")
            detail = video.createdAt.formatted(.dateTime.day().month(.abbreviated))
            return
        }
        title = pro.displayName
        detail = pro.club
    }

    /// Both parts on one line, for a control too narrow for the chip's two weights.
    var caption: String {
        "\(title) · \(detail)"
    }
}
