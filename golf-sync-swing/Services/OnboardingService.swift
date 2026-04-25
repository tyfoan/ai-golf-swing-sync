//
//  OnboardingService.swift
//  golf-sync-swing
//
//  Manages first-launch detection and onboarding completion state.
//  Single source of truth for whether the user has seen onboarding.
//

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingService {

    static let shared = OnboardingService()

    private(set) var hasCompletedOnboarding: Bool

    private static let completedKey = "hasCompletedOnboarding"

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Self.completedKey)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Self.completedKey)
    }

    #if DEBUG
    func resetOnboarding() {
        hasCompletedOnboarding = false
        defaults.removeObject(forKey: Self.completedKey)
    }
    #endif
}
