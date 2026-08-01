//
//  MemoryPressureMonitor.swift
//  golf-sync-swing
//
//  The system's opinion of how much memory is left, delivered as an event.
//
//  WHY THIS EXISTS AT ALL
//  ----------------------
//  `SwingFrameBuffer` holds a few seconds of the take as full-resolution JPEGs — tens of
//  megabytes — WHILE AVFoundation is encoding the movie file. Those two are not equals: losing a
//  replay is a disappointment, losing the recording is losing the thing the golfer came for. So
//  the ring needs a way to be told "give it back now", and the only authority worth listening to
//  on that question is the kernel, not this app's own accounting: a byte ceiling guesses at what
//  the device can spare, while a pressure event states it.
//
//  `DispatchSource.makeMemoryPressureSource` rather than
//  `UIApplication.didReceiveMemoryWarningNotification`, for two reasons: it reports `.warning` and
//  `.critical` separately — which is the difference between shedding and standing down — and it
//  arrives on a queue of our choosing rather than on the main actor, where the ring is not
//  reachable anyway.
//
//  `nonisolated` + `@unchecked Sendable`, matching the rest of the capture path: the target builds
//  with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and an implicitly `@MainActor` type could not
//  be reached from the source's queue.
//

// Explicit, module by module: the target builds with
// `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`, so re-exports do not count.
import Dispatch
import Foundation
// Required for `Logger`'s string interpolation.
import os

nonisolated final class MemoryPressureMonitor: @unchecked Sendable {

    /// The two answers worth acting on differently. `.normal` — which the source also reports — is
    /// deliberately absent: there is nothing for a listener to do when memory is fine, and an
    /// event that means "carry on" would invite a listener to treat recovery as a signal.
    enum Level: String {
        case warning
        case critical
    }

    /// Written ONCE, by the owner, before `start()` — which is what makes it safe without a lock,
    /// the same rule `CapturedFrameRelay`'s collaborators follow.
    var onPressure: ((Level) -> Void)?

    /// `.utility`: this fires while the device is short of memory, and it has no business
    /// preempting the capture queue or the encode workers to say so. Its own queue rather than a
    /// global one so a slow listener cannot be blamed on someone else's work.
    private let source: DispatchSourceMemoryPressure

    init(label: String = "com.golfsync.memoryPressure") {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue(label: label, qos: .utility)
        )
    }

    deinit {
        source.cancel()
    }

    /// Handler first, then activate: a `DispatchSource` will not accept a handler once it is
    /// running. Idempotent in effect — the source can only be activated once, and a second call
    /// replaces a handler that is identical.
    func start() {
        source.setEventHandler { [weak self] in self?.report() }
        source.activate()
    }

    /// Logged at `warning` and NOT behind `#if DEBUG`, deliberately: this is a production event
    /// that explains a missing replay, and one that no probe run will ever reproduce on demand.
    private func report() {
        guard let level = Self.level(of: source.data) else { return }
        AppLogger.camera.warning("MemoryPressureMonitor: the system reports \(level.rawValue, privacy: .public) memory pressure")
        onPressure?(level)
    }

    /// Critical wins when both bits are set, because the response to critical is a superset of the
    /// response to warning.
    private static func level(of event: DispatchSource.MemoryPressureEvent) -> Level? {
        guard !event.contains(.critical) else { return .critical }
        guard event.contains(.warning) else { return nil }
        return .warning
    }
}
