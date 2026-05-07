//
//  ProSwingCatalog.swift
//  golf-sync-swing
//
//  Static catalog of bundled professional reference swings. Each entry knows
//  exactly where the swing's start, contact, and end frames sit inside its clip
//  so premium auto-sync can align them with user swings without re-detection.
//

import Foundation

struct ProSwingDescriptor {
    let displayName: String
    let bundleFilename: String
    let club: String
    let duration: TimeInterval
    let startTime: TimeInterval
    let contactTime: TimeInterval
    let endTime: TimeInterval
}

enum ProSwingCatalog {
    static let all: [ProSwingDescriptor] = [
        ProSwingDescriptor(displayName: "Tiger Woods",       bundleFilename: "tiger-woods-driver",       club: "Driver", duration: 5.60, startTime: 2.00, contactTime: 2.97, endTime: 3.60),
        ProSwingDescriptor(displayName: "Tiger Woods",       bundleFilename: "tiger-woods-wedge",        club: "Wedge",  duration: 5.57, startTime: 2.00, contactTime: 3.00, endTime: 3.57),
        ProSwingDescriptor(displayName: "Rory McIlroy",      bundleFilename: "rory-mcilroy-driver",      club: "Driver", duration: 5.37, startTime: 2.00, contactTime: 2.83, endTime: 3.37),
        ProSwingDescriptor(displayName: "Rickie Fowler",     bundleFilename: "rickie-fowler-driver",     club: "Driver", duration: 5.40, startTime: 2.00, contactTime: 2.87, endTime: 3.40),
        ProSwingDescriptor(displayName: "Bryson DeChambeau", bundleFilename: "bryson-dechambeau-driver", club: "Driver", duration: 5.67, startTime: 2.00, contactTime: 3.13, endTime: 3.67),
        ProSwingDescriptor(displayName: "Tony Finau",        bundleFilename: "tony-finau-iron",          club: "Iron",   duration: 6.27, startTime: 2.00, contactTime: 3.70, endTime: 4.27),
        ProSwingDescriptor(displayName: "Bubba Watson",      bundleFilename: "bubba-watson-iron",        club: "Iron",   duration: 5.37, startTime: 2.00, contactTime: 3.00, endTime: 3.37),
    ]
}
