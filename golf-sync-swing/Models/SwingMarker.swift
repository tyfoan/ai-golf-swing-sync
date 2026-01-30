//
//  SwingMarker.swift
//  golf-sync-swing
//

import Foundation
import SwiftData

@Model
final class SwingMarker {
    var id: UUID = UUID()
    var startTime: TimeInterval  // Green - swing start
    var contactTime: TimeInterval  // Red - ball contact
    var endTime: TimeInterval  // Green - swing end
    var createdAt: Date = Date()

    @Relationship(inverse: \SwingVideo.swings) var video: SwingVideo?

    init(startTime: TimeInterval, contactTime: TimeInterval, endTime: TimeInterval) {
        self.startTime = startTime
        self.contactTime = contactTime
        self.endTime = endTime
    }

    var duration: TimeInterval {
        endTime - startTime
    }
}
