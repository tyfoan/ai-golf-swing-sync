//
//  CrashDiagnosticsReporter.swift
//  golf-sync-swing
//
//  Forwards MetricKit diagnostics — crashes, hangs, CPU and disk-write exceptions — into the
//  existing analytics seam, so production failure rates show up beside the funnel.
//
//  Why MetricKit and not Sentry/Crashlytics: MetricKit is a system framework, so this needs no
//  new SPM dependency. A third-party SDK would give real-time reports with symbolicated stacks
//  and is worth adding later; this gives coverage today with zero dependency risk.
//
//  IMPORTANT — delivery model. Diagnostic payloads are NOT real-time. iOS delivers them at
//  most once per ~24h, on a LATER launch, only from real devices, and only when the user's
//  diagnostics settings allow it. Expect nothing on the simulator and nothing the same day.
//  Xcode Organizer → Crashes remains the fastest route to symbolicated crash reports.
//
//  Stack traces are deliberately NOT sent: `callStackTree.jsonRepresentation()` is far too
//  large for Amplitude's string-valued event properties. Signal, exception type/code,
//  termination reason and hang duration are enough to see WHAT is failing and HOW OFTEN; the
//  stack lives in Organizer.
//

import Foundation
import MetricKit
import os

final class CrashDiagnosticsReporter: NSObject, MXMetricManagerSubscriber {

    private let analytics: AnalyticsTracking

    init(analytics: AnalyticsTracking = Analytics.shared) {
        self.analytics = analytics
        super.init()
    }

    /// Registers for diagnostics. Safe to call once at launch; the subscriber is retained for
    /// the process lifetime, matching how MetricKit expects to deliver on later launches.
    func start() {
        MXMetricManager.shared.add(self)
        AppLogger.general.info("CrashDiagnosticsReporter: subscribed to MetricKit diagnostics")
    }

    // MARK: - MXMetricManagerSubscriber

    // Swift maps both payload callbacks onto `didReceive(_:)`, overloaded by payload type.
    /// MetricKit invokes this on a private background queue, so it must stay `nonisolated`:
    /// payloads are reduced to `Sendable` reports off-main, and only the explicit hop below
    /// touches the main-actor-isolated analytics seam.
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let reports = payloads.flatMap(Self.reports(from:))
        guard !reports.isEmpty else { return }
        Task { @MainActor in
            reports.forEach { self.analytics.track($0.event) }
        }
    }

    // MARK: - Extraction (runs on MetricKit's background queue)

    /// A diagnostic reduced to `Sendable` values off-main. The `AnalyticsEvent` itself is
    /// built on the main actor, where its factories and the analytics seam are isolated.
    private nonisolated struct DiagnosticReport {
        enum Kind {
            case crash
            case hang
        }

        let kind: Kind
        let properties: [String: String]

        @MainActor var event: AnalyticsEvent {
            switch kind {
            case .crash: .crashDetected(properties: properties)
            case .hang: .hangDetected(properties: properties)
            }
        }
    }

    private nonisolated static func reports(from payload: MXDiagnosticPayload) -> [DiagnosticReport] {
        (payload.crashDiagnostics ?? []).map { report(for: $0) }
            + (payload.hangDiagnostics ?? []).map { report(for: $0) }
            + (payload.cpuExceptionDiagnostics ?? []).map { report(for: $0) }
            + (payload.diskWriteExceptionDiagnostics ?? []).map { report(for: $0) }
    }

    private nonisolated static func report(for crash: MXCrashDiagnostic) -> DiagnosticReport {
        var properties = baseProperties(for: crash)
        properties["signal"] = crash.signal.map { "\($0.intValue)" } ?? "unknown"
        properties["exception_type"] = crash.exceptionType.map { "\($0.intValue)" } ?? "unknown"
        properties["exception_code"] = crash.exceptionCode.map { "\($0.intValue)" } ?? "unknown"
        properties["termination_reason"] = crash.terminationReason ?? "unknown"

        AppLogger.general.error("MetricKit crash: signal=\(properties["signal"] ?? "?") reason=\(properties["termination_reason"] ?? "?")")
        return DiagnosticReport(kind: .crash, properties: properties)
    }

    private nonisolated static func report(for hang: MXHangDiagnostic) -> DiagnosticReport {
        var properties = baseProperties(for: hang)
        let seconds = hang.hangDuration.converted(to: .seconds).value
        properties["hang_seconds"] = String(format: "%.1f", seconds)
        properties["hang_bucket"] = durationBucket(seconds)

        AppLogger.general.error("MetricKit hang: \(String(format: "%.1f", seconds))s")
        return DiagnosticReport(kind: .hang, properties: properties)
    }

    private nonisolated static func report(for exception: MXCPUExceptionDiagnostic) -> DiagnosticReport {
        var properties = baseProperties(for: exception)
        properties["kind"] = "cpu_exception"
        properties["cpu_seconds"] = String(format: "%.1f", exception.totalCPUTime.converted(to: .seconds).value)
        return DiagnosticReport(kind: .crash, properties: properties)
    }

    private nonisolated static func report(for exception: MXDiskWriteExceptionDiagnostic) -> DiagnosticReport {
        var properties = baseProperties(for: exception)
        properties["kind"] = "disk_write_exception"
        properties["written_mb"] = String(
            format: "%.1f",
            exception.totalWritesCaused.converted(to: .megabytes).value
        )
        return DiagnosticReport(kind: .crash, properties: properties)
    }

    /// Fields every diagnostic shares. `applicationVersion` matters most: these arrive on a
    /// later launch, so the reported version is often NOT the version now installed.
    private nonisolated static func baseProperties(for diagnostic: MXDiagnostic) -> [String: String] {
        [
            "app_version": diagnostic.applicationVersion,
            "build": diagnostic.metaData.applicationBuildVersion,
            "os_version": diagnostic.metaData.osVersion,
            "device": diagnostic.metaData.deviceType
        ]
    }

    /// Buckets keep the property low-cardinality so Amplitude can group by it.
    private nonisolated static func durationBucket(_ seconds: Double) -> String {
        switch seconds {
        case ..<2: return "under_2s"
        case ..<5: return "2_5s"
        case ..<10: return "5_10s"
        case ..<30: return "10_30s"
        default: return "over_30s"
        }
    }
}
