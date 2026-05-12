//
//  ProSwingCatalog.swift
//  golf-sync-swing
//
//  Static catalog of bundled professional reference swings. Each entry knows
//  where the core swing and contact frame sit inside its clip. Public start/end
//  times include context before setup and after follow-through for comparison.
//

import Foundation

struct ProSwingDescriptor {
    static let defaultContextPadding: TimeInterval = 2.0

    let displayName: String
    let bundleFilename: String
    let club: String
    let duration: TimeInterval
    let coreStartTime: TimeInterval
    let contactTime: TimeInterval
    let coreEndTime: TimeInterval
    let contextPadding: TimeInterval

    var startTime: TimeInterval {
        max(0, coreStartTime - contextPadding)
    }

    var endTime: TimeInterval {
        min(duration, coreEndTime + contextPadding)
    }

    init(
        displayName: String,
        bundleFilename: String,
        club: String,
        duration: TimeInterval,
        coreStartTime: TimeInterval,
        contactTime: TimeInterval,
        coreEndTime: TimeInterval,
        contextPadding: TimeInterval = Self.defaultContextPadding
    ) {
        self.displayName = displayName
        self.bundleFilename = bundleFilename
        self.club = club
        self.duration = duration
        self.coreStartTime = coreStartTime
        self.contactTime = contactTime
        self.coreEndTime = coreEndTime
        self.contextPadding = contextPadding
    }
}

enum ProSwingCatalog {
    static let all: [ProSwingDescriptor] = [
        ProSwingDescriptor(displayName: "Tiger Woods", bundleFilename: "tiger-woods-driver", club: String(localized: "Driver", comment: "Golf club name"), duration: 5.61, coreStartTime: 2.00, contactTime: 2.97, coreEndTime: 3.60, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Tiger Woods", bundleFilename: "tiger-woods-wedge", club: String(localized: "Wedge", comment: "Golf club name"), duration: 5.57, coreStartTime: 2.00, contactTime: 3.00, coreEndTime: 3.57, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Rory McIlroy", bundleFilename: "rory-mcilroy-driver", club: String(localized: "Driver", comment: "Golf club name"), duration: 5.37, coreStartTime: 2.00, contactTime: 2.83, coreEndTime: 3.37, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Rickie Fowler", bundleFilename: "rickie-fowler-driver", club: String(localized: "Driver", comment: "Golf club name"), duration: 5.41, coreStartTime: 2.00, contactTime: 2.87, coreEndTime: 3.40, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Bryson DeChambeau", bundleFilename: "bryson-dechambeau-driver", club: String(localized: "Driver", comment: "Golf club name"), duration: 5.67, coreStartTime: 2.00, contactTime: 3.13, coreEndTime: 3.67, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Tony Finau", bundleFilename: "tony-finau-iron", club: String(localized: "Iron", comment: "Golf club name"), duration: 6.27, coreStartTime: 2.00, contactTime: 3.70, coreEndTime: 4.27, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Bubba Watson", bundleFilename: "bubba-watson-iron", club: String(localized: "Iron", comment: "Golf club name"), duration: 5.37, coreStartTime: 2.00, contactTime: 3.00, coreEndTime: 3.37, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Adam Scott", bundleFilename: "adam-scott-driver", club: String(localized: "Driver", comment: "Golf club name"), duration: 5.71, coreStartTime: 2.00, contactTime: 3.00, coreEndTime: 3.70, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Brooke Henderson", bundleFilename: "brooke-henderson-iron", club: String(localized: "Iron", comment: "Golf club name"), duration: 5.84, coreStartTime: 2.00, contactTime: 3.17, coreEndTime: 3.83, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Charley Hull", bundleFilename: "charley-hull-driver", club: String(localized: "Driver", comment: "Golf club name"), duration: 5.47, coreStartTime: 2.00, contactTime: 3.00, coreEndTime: 3.47, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Dustin Johnson", bundleFilename: "dustin-johnson-fairway", club: String(localized: "Fairway", comment: "Golf club name (fairway wood)"), duration: 5.91, coreStartTime: 2.00, contactTime: 3.23, coreEndTime: 3.90, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Hyo Joo Kim", bundleFilename: "hyo-joo-kim-driver", club: String(localized: "Driver", comment: "Golf club name"), duration: 6.81, coreStartTime: 2.00, contactTime: 4.57, coreEndTime: 4.80, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Inbee Park", bundleFilename: "inbee-park-driver", club: String(localized: "Driver", comment: "Golf club name"), duration: 7.11, coreStartTime: 2.00, contactTime: 3.97, coreEndTime: 5.10, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Justin Rose", bundleFilename: "justin-rose-driver", club: String(localized: "Driver", comment: "Golf club name"), duration: 6.11, coreStartTime: 2.00, contactTime: 3.43, coreEndTime: 4.10, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Lexi Thompson", bundleFilename: "lexi-thompson-driver", club: String(localized: "Driver", comment: "Golf club name"), duration: 6.27, coreStartTime: 2.00, contactTime: 3.27, coreEndTime: 4.27, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Lydia Ko", bundleFilename: "lydia-ko-driver", club: String(localized: "Driver", comment: "Golf club name"), duration: 6.47, coreStartTime: 2.00, contactTime: 3.63, coreEndTime: 4.47, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Michelle Wie", bundleFilename: "michelle-wie-driver", club: String(localized: "Driver", comment: "Golf club name"), duration: 5.67, coreStartTime: 2.00, contactTime: 3.00, coreEndTime: 3.67, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Minjee Lee", bundleFilename: "minjee-lee-driver", club: String(localized: "Driver", comment: "Golf club name"), duration: 6.21, coreStartTime: 2.00, contactTime: 3.53, coreEndTime: 4.20, contextPadding: 2.00),
        ProSwingDescriptor(displayName: "Phil Mickelson", bundleFilename: "phil-mickelson-wedge", club: String(localized: "Wedge", comment: "Golf club name"), duration: 5.57, coreStartTime: 2.00, contactTime: 3.10, coreEndTime: 3.57, contextPadding: 2.00),
    ]
}
