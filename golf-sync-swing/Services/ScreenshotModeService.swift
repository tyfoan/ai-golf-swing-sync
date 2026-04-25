//
//  ScreenshotModeService.swift
//  golf-sync-swing
//
//  Toggles screenshot mode for App Store screenshot capture.
//  When enabled, all premium features are unlocked without a subscription.
//  DEBUG-only — stripped from release builds.
//

import Foundation

#if DEBUG
@Observable
final class ScreenshotModeService {
    static let shared = ScreenshotModeService()

    private(set) var isEnabled: Bool

    private static let enabledKey = "screenshotModeEnabled"
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    func toggle() {
        isEnabled.toggle()
        defaults.set(isEnabled, forKey: Self.enabledKey)
    }

    func enable() {
        isEnabled = true
        defaults.set(true, forKey: Self.enabledKey)
    }

    func disable() {
        isEnabled = false
        defaults.set(false, forKey: Self.enabledKey)
    }
}
#endif
