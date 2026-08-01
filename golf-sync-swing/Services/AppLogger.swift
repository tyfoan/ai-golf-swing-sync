//
//  AppLogger.swift
//  golf-sync-swing
//
//  Unified logging with os.Logger — debug/info stripped in Release builds.
//  Each subsystem category gets its own Logger instance.
//

import Foundation
import os

/// `nonisolated`: `Logger` is `Sendable` and loggers are called from camera/detection
/// queues and `@concurrent` code, so these statics must not be main-actor-isolated.
nonisolated enum AppLogger {

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.golfsyncswing"

    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let detection = Logger(subsystem: subsystem, category: "detection")
    static let general = Logger(subsystem: subsystem, category: "general")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let photos = Logger(subsystem: subsystem, category: "photos-save")
}
