//
//  CaptureGraphGate.swift
//  golf-sync-swing
//
//  Orders the main-thread half of capture-graph work against the session queue.
//

import Foundation
import os

/// Runs a main-thread capture-graph mutation — `previewLayer.session = …`,
/// `connection.videoRotationAngle = …`, `connection.automaticallyAdjustsVideoMirroring = …` —
/// at a moment when it cannot block.
///
/// **Every one of those assignments takes `AVCaptureSession`'s internal lock**: the same lock
/// `startRunning()`, `stopRunning()` and `beginConfiguration()` hold for their entire duration.
/// A cold bring-up holds it for seconds, so an assignment issued from the main thread while the
/// session queue is working parks the whole UI — the tab bar included — until it lets go. That is
/// a frozen app during "Preparing camera…", and tab taps that land nowhere.
///
/// **A bounce through the session queue does not prevent it.** The previous shape,
/// `sessionQueue.async { DispatchQueue.main.async { … } }`, orders the *enqueueing* of the
/// main-thread hop and nothing else: the outer block returns at once, the session queue advances
/// to whatever is behind it — on the cold path, the bring-up — and the assignment then runs
/// concurrently with exactly the work it was supposed to follow. It reads as a deferral and
/// behaves as a race.
///
/// So count the work instead. A mutation offered while the count is zero runs now; otherwise it
/// waits for the count to fall back to zero. `CameraService.enqueueSessionWork` is what keeps the
/// count honest, and is the only way session-queue work may be scheduled.
///
/// Main-actor throughout, so neither the count nor the waiting list needs a lock: every caller is
/// a view or a `CameraService` method, and both are main-actor. This is deliberately unlike the
/// frame-path state next door, which is lock-guarded because it is genuinely cross-queue.
final class CaptureGraphGate {

    /// A mutation and the name it reports under. Named rather than anonymous because a mutation
    /// that never runs is a black preview, and "which one is still waiting" is the first question
    /// asked of one.
    private struct Mutation {
        let name: String
        let run: () -> Void
    }

    private var workInFlight = 0
    private var waiting: [Mutation] = []

    /// Run `mutation` at the first moment the session queue is not holding the capture session's
    /// lock — immediately, when that moment is now.
    ///
    /// At most one mutation waits per name: a preview layer asked to reconfigure its connection
    /// four times during one bring-up owes the session lock one visit, not four. The last offer
    /// wins, since it carries the freshest state.
    func perform(_ name: String, _ mutation: @escaping () -> Void) {
        let offered = Mutation(name: name, run: mutation)
        guard workInFlight > 0 else {
            run(offered)
            return
        }
        waiting.removeAll { $0.name == name }
        waiting.append(offered)
        #if DEBUG
        DeviceProbe.event("graph_mutation_deferred", ["name": name, "work_in_flight": String(workInFlight)])
        #endif
    }

    /// Called on the main thread immediately before a block is enqueued onto the session queue.
    func workBegan() {
        workInFlight += 1
    }

    /// Called on the main thread once that block has finished. Never from the session queue
    /// itself: the count must not reach zero while a mutation could still collide with the tail
    /// of the block that is releasing it.
    func workEnded() {
        workInFlight = max(workInFlight - 1, 0)
        guard workInFlight == 0 else { return }
        let ready = waiting
        waiting = []
        ready.forEach(run)
    }

    /// Always measured. Keeping this cost off the main thread is the only reason this type
    /// exists, and a claim that it is now free is worth nothing next to the milliseconds it
    /// actually took. A healthy mutation is under a millisecond; anything in the hundreds means
    /// it took the session lock after all, and names the path that let it.
    private func run(_ mutation: Mutation) {
        let started = ProcessInfo.processInfo.systemUptime
        mutation.run()
        let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
        AppLogger.camera.info("CAMPERF graph.\(mutation.name) \(String(format: "%.0fms", milliseconds))")
        #if DEBUG
        DeviceProbe.event("graph_mutation", [
            "name": mutation.name,
            "ms": String(format: "%.0f", milliseconds)
        ])
        #endif
    }
}
