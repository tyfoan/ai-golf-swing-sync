//
//  ReviewPromptService.swift
//  golf-sync-swing
//
//  Manages App Store review prompt timing.
//  Asks for review after meaningful engagement milestones.
//

import Foundation
import StoreKit
import os

@MainActor
@Observable
final class ReviewPromptService {

    static let shared = ReviewPromptService()

    private static let swingCountKey = "reviewPrompt.swingCount"
    private static let lastPromptVersionKey = "reviewPrompt.lastVersion"
    private static let promptThreshold = 3

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Call after each successful swing detection.
    func recordSwingDetected() {
        let count = defaults.integer(forKey: Self.swingCountKey) + 1
        defaults.set(count, forKey: Self.swingCountKey)

        guard count >= Self.promptThreshold else { return }
        guard !hasPromptedThisVersion else { return }

        requestReview()
    }

    private func requestReview() {
        guard let scene = currentWindowScene else { return }
        AppStore.requestReview(in: scene)
        defaults.set(appVersion, forKey: Self.lastPromptVersionKey)
        AppLogger.general.info("ReviewPromptService: requested review")
    }

    private var hasPromptedThisVersion: Bool {
        defaults.string(forKey: Self.lastPromptVersionKey) == appVersion
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var currentWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
    }
}
