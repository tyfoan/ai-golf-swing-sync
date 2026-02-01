//
//  CountdownManager.swift
//  golf-sync-swing
//
//  Manages countdown before recording starts
//

import Foundation

/// Manages the countdown sequence before recording
@MainActor
@Observable
final class CountdownManager {

    // MARK: - State

    private(set) var isCountingDown = false
    private(set) var countdownValue: Int = 0

    private var countdownTask: Task<Void, Never>?

    // MARK: - Callbacks

    var onCountdownComplete: (() -> Void)?
    var onCountdownCancelled: (() -> Void)?

    // MARK: - Public API

    /// Start a countdown from the given value
    /// - Parameter from: Starting value (e.g., 5 for 5-4-3-2-1)
    func startCountdown(from value: Int = 5) {
        guard !isCountingDown else { return }

        isCountingDown = true
        countdownValue = value

        countdownTask = Task { [weak self] in
            guard let self else { return }

            for i in stride(from: value, through: 1, by: -1) {
                // Check for cancellation
                if Task.isCancelled {
                    await MainActor.run {
                        self.reset()
                        self.onCountdownCancelled?()
                    }
                    return
                }

                await MainActor.run {
                    self.countdownValue = i
                }

                try? await Task.sleep(for: .seconds(1))
            }

            // Countdown complete
            await MainActor.run {
                self.isCountingDown = false
                self.countdownValue = 0
                self.onCountdownComplete?()
            }
        }
    }

    /// Cancel the current countdown
    func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
        reset()
        onCountdownCancelled?()
    }

    /// Reset state without triggering callbacks
    func reset() {
        isCountingDown = false
        countdownValue = 0
        countdownTask?.cancel()
        countdownTask = nil
    }
}
