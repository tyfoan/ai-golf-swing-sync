//
//  DebugScenario.swift
//  golf-sync-swing
//
//  DEBUG-ONLY self-driving scenarios. The whole file is inside `#if DEBUG` and nothing runs
//  unless `GSS_SCENARIO=<name>` is set, so a Release build compiles this to nothing and an
//  ordinary Debug launch never notices it.
//
//  ** WHAT THIS CAN AND CANNOT CATCH **
//  A scenario drives the app through the SAME public entry points the UI uses — the router's
//  tab selection, and the live `RecordingViewModel`'s own methods — so it exercises the
//  view-model and service code paths for real: the camera bring-up, the countdown, the
//  recording, detection, finalize, and the save/review outcome.
//
//  It does NOT touch the SwiftUI gesture layer. Nothing here taps a `Button`, so a bug that
//  lives purely in a button's action closure, in a disabled/`allowsHitTesting` state, in a
//  z-order that puts an invisible view over a control, or anywhere else in hit-testing WILL
//  NOT BE CAUGHT by it. A scenario that runs clean is evidence the machinery underneath
//  works; it is not evidence that the user can reach it. When a scenario passes and the
//  developer still cannot record by hand, the gesture layer is exactly where to look next —
//  and that is a genuinely useful thing to have narrowed down.
//
//  The view model is reached by registration rather than construction: `RecordingViewModel`
//  hands itself over from `activate()`, which is the one moment SwiftUI's installed instance
//  claims the shared camera. Throwaway instances — SwiftUI builds one on every tab switch
//  and discards all but one — never reach `activate()`, so they never register. The
//  registration event carries the instance identity, so two live identities would show up in
//  the timeline as a fact rather than an inference.
//

#if DEBUG

import AVFoundation
import Foundation

// MARK: - Runner

protocol DebugScenarioRunner {
    var name: String { get }
    /// Returns the outcome recorded on `scenario_finished`.
    func run(in context: DebugScenarioContext) async -> String
}

// MARK: - Coordinator

/// Not `@Observable`: nothing in SwiftUI watches the harness, and the view-model reference
/// is deliberately `weak` — a stored property the macro would rewrite for no benefit.
final class DebugScenario {

    static let shared = DebugScenario()

    /// Read once. Absent means no scenario, ever.
    static let requested = ProcessInfo.processInfo.environment["GSS_SCENARIO"]

    /// Adding a scenario is one entry in this array — no call site changes.
    private static let runners: [String: DebugScenarioRunner] = {
        let all: [DebugScenarioRunner] = [CaptureFlowScenario()]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
    }()

    /// Weak: the harness must never be the reason a view model outlives its view, and a
    /// scenario driving a discarded instance would be worse than no scenario at all.
    private(set) weak var recordingViewModel: RecordingViewModel?
    private var hasBegun = false

    private init() {}

    /// Called from `RecordingViewModel.activate()`. Last writer wins deliberately: the
    /// installed instance is whichever one most recently claimed the shared camera, and
    /// pinning the first would hand the scenario a stale view model.
    func attach(_ viewModel: RecordingViewModel) {
        recordingViewModel = viewModel
        DeviceProbe.event("scenario_view_model_attached", ["instance": DeviceProbe.identity(viewModel)])
    }

    /// Wired from the app's root view. Idempotent — `.task` can re-run.
    func begin(router: AppRouter) {
        guard let name = Self.requested, !hasBegun else { return }
        hasBegun = true
        Task { await start(named: name, router: router) }
    }

    private func start(named name: String, router: AppRouter) async {
        guard let runner = Self.runners[name] else {
            DeviceProbe.event("scenario_unknown", ["scenario": name, "known": Self.runners.keys.sorted().joined(separator: ",")])
            return
        }
        DeviceProbe.event("scenario_started", environmentProps(runner), ui: true)
        let outcome = await runner.run(in: DebugScenarioContext(router: router, scenario: self))
        DeviceProbe.event("scenario_finished", ["scenario": runner.name, "outcome": outcome], ui: true, frame: true)
    }

    /// The three silent dead ends a scenario can hit on a fresh device — onboarding still
    /// up, camera permission not granted, no view model yet — recorded before anything is
    /// attempted, so a timeout later is self-explaining rather than the start of another
    /// round of guessing.
    private func environmentProps(_ runner: DebugScenarioRunner) -> [String: String] {
        [
            "scenario": runner.name,
            "onboarding_completed": String(OnboardingService.shared.hasCompletedOnboarding),
            "video_authorization": Self.authorizationLabels[AVCaptureDevice.authorizationStatus(for: .video)] ?? "unknown",
            "view_model_attached": String(recordingViewModel != nil)
        ]
    }

    private static let authorizationLabels: [AVAuthorizationStatus: String] = [
        .notDetermined: "notDetermined",
        .restricted: "restricted",
        .denied: "denied",
        .authorized: "authorized"
    ]
}

// MARK: - Context

/// What a runner is allowed to touch, and the one primitive it needs: a bounded wait.
final class DebugScenarioContext {

    let router: AppRouter
    private let scenario: DebugScenario

    /// How often a wait re-checks. Short enough to keep `waited_s` meaningful, long enough
    /// not to spin the main actor while the camera is busy coming up.
    private static let pollInterval: Duration = .milliseconds(100)

    init(router: AppRouter, scenario: DebugScenario) {
        self.router = router
        self.scenario = scenario
    }

    var viewModel: RecordingViewModel? { scenario.recordingViewModel }

    /// Polls until `condition` holds or the deadline passes. A timeout records
    /// `scenario_timeout` and returns false — a scenario must never hang the app it is
    /// meant to be diagnosing, and a wait that ends in silence teaches nobody anything.
    @discardableResult
    func waitUntil(_ label: String, timeout: TimeInterval, condition: () -> Bool) async -> Bool {
        let start = ProcessInfo.processInfo.systemUptime
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            guard !condition() else {
                DeviceProbe.event("scenario_await", ["awaited": label, "waited_s": elapsed(since: start)])
                return true
            }
            try? await Task.sleep(for: Self.pollInterval)
        }
        DeviceProbe.event("scenario_timeout", [
            "awaited": label,
            "timeout_s": String(format: "%.1f", timeout),
            "state": viewModel?.state.probeLabel ?? "no_view_model"
        ], ui: true, frame: true)
        return false
    }

    /// Idles for `duration`, emitting a heartbeat every `interval`. The heartbeats carry the
    /// probe's always-on frame stats, which is how "the pipeline died mid-take" becomes
    /// visible instead of being inferred from a bad result at the end.
    func idle(_ duration: TimeInterval, interval: TimeInterval, label: String) async {
        let ticks = max(1, Int((duration / interval).rounded()))
        for tick in 1...ticks {
            try? await Task.sleep(for: .seconds(interval))
            DeviceProbe.event(label, ["tick": String(tick), "of": String(ticks)])
        }
    }

    private func elapsed(since start: Double) -> String {
        String(format: "%.2f", ProcessInfo.processInfo.systemUptime - start)
    }
}

// MARK: - capture-flow

/// Camera tab → session up → Start Recording → countdown → ~10 s take → Stop → outcome.
///
/// Every wait is bounded by what this app has actually been measured doing on device: a cold
/// bring-up has taken 22 s, the countdown is 5 s, and the finalize watchdog recovers at 20 s.
/// The timeouts sit above those, so a timeout here means something is genuinely wrong rather
/// than merely slow.
struct CaptureFlowScenario: DebugScenarioRunner {

    let name = "capture-flow"

    private let takeDuration: TimeInterval = 10
    private let heartbeatInterval: TimeInterval = 2

    func run(in context: DebugScenarioContext) async -> String {
        context.router.selectedTab = .camera
        DeviceProbe.event("scenario_selected_camera_tab")

        guard await context.waitUntil("view_model_attached", timeout: 20, condition: { context.viewModel != nil }),
              let viewModel = context.viewModel else {
            return "no_view_model"
        }
        return await record(with: viewModel, in: context)
    }

    private func record(with viewModel: RecordingViewModel, in context: DebugScenarioContext) async -> String {
        guard await context.waitUntil("session_running", timeout: 30, condition: { viewModel.cameraService.isSessionRunning }) else {
            return "session_never_ran"
        }
        // `startRecording()` is a no-op unless the screen is idle, so this is a precondition,
        // not a courtesy — without it the scenario would "tap record" into silence.
        guard await context.waitUntil("state_idle", timeout: 15, condition: { viewModel.state == .idle }) else {
            return "never_idle_state_\(viewModel.state.probeLabel)"
        }

        DeviceProbe.event("scenario_tapped_record", ui: true, frame: true)
        viewModel.startRecording()

        guard await context.waitUntil("state_recording", timeout: 25, condition: { viewModel.isRecording }) else {
            return "never_started_recording_state_\(viewModel.state.probeLabel)"
        }
        return await finish(with: viewModel, in: context)
    }

    private func finish(with viewModel: RecordingViewModel, in context: DebugScenarioContext) async -> String {
        await context.idle(takeDuration, interval: heartbeatInterval, label: "scenario_recording_heartbeat")

        DeviceProbe.event("scenario_tapped_stop", ["swings": String(viewModel.swingCount)], ui: true, frame: true)
        viewModel.stopRecording()

        // `.saved` is transient — the view dismisses it straight back to `.idle` — so the
        // scenario waits for the take to stop being in flight rather than for one state.
        let settled = await context.waitUntil("take_settled", timeout: 45, condition: { viewModel.state.isSettled })
        DeviceProbe.event("scenario_outcome", [
            "state": viewModel.state.probeLabel,
            "swings": String(viewModel.swingCount),
            "settled": String(settled),
            "review_notice": viewModel.reviewNotice.map { $0.title } ?? "none"
        ], ui: true, frame: true)
        return settled ? "settled_\(viewModel.state.probeLabel)" : "stuck_\(viewModel.state.probeLabel)"
    }
}

// MARK: - State Labels

extension RecordingState {

    /// Timeline-friendly name. Kept here rather than on the model: it exists only for the
    /// probe and must not survive into a Release build.
    var probeLabel: String {
        switch self {
        case .idle: return "idle"
        case .countdown(let remaining): return "countdown_\(remaining)"
        case .recording: return "recording"
        case .finalizingVideo: return "finalizingVideo"
        case .saving: return "saving"
        case .saved: return "saved"
        case .reviewing: return "reviewing"
        }
    }

    /// No work in flight: the take has reached a state a person could act on.
    var isSettled: Bool {
        switch self {
        case .idle, .reviewing: return true
        case .countdown, .recording, .finalizingVideo, .saving, .saved: return false
        }
    }
}

extension CaptureDisplayMode {

    /// Timeline-friendly name, kept beside `RecordingState.probeLabel` and for the same
    /// reason: it exists only for the probe and must not survive into a Release build.
    ///
    /// Read it in two places. `swing_replay` carries the mode a detected swing landed in, and
    /// `pip_swapped` carries every change the user made afterwards — together they say which
    /// surface held the camera at any point in the run, which no UI snapshot can establish on
    /// its own because a snapshot cannot see the preview layer at all.
    var probeLabel: String {
        switch self {
        case .swingOnMain:  return "swing_on_main"
        case .cameraOnMain: return "camera_on_main"
        }
    }
}

#endif
