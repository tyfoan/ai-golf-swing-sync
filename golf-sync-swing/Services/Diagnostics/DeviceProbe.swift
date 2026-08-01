//
//  DeviceProbe.swift
//  golf-sync-swing
//
//  DEBUG-ONLY on-device diagnostics recorder. The whole file sits inside `#if DEBUG`, so a
//  Release build compiles it to nothing, and every call site is `#if DEBUG` too. Even in a
//  Debug build it stays inert unless the app is launched with `GSS_PROBE=1`.
//
//  WHY THIS EXISTS
//  ---------------
//  The developer runs on a physical iPhone and can only describe symptoms in prose. "The
//  screen is black" has two completely different causes — the preview layer was never
//  attached, or the capture session is delivering no frames — and nothing in the app
//  distinguished them. Three rounds of guessing were lost to that one ambiguity. This
//  recorder makes the distinction mechanical.
//
//  OUTPUT
//  ------
//    <app Documents>/diagnostics/<runId>/          runId = "yyyyMMdd-HHmmss", local time
//      timeline.jsonl    one JSON object per line, appended immediately
//      ui-<NNN>.png      UI-chrome snapshot
//      frame-<NNN>.jpg   camera frame, encoded straight off the capture callback
//
//  A line is:
//    {"t": 12.345, "event": "session_running", "props": {...}, "ui": "ui-002.png", "frame": "frame-002.jpg"}
//  `t` is seconds since probe start (`ProcessInfo.systemUptime`, monotonic). `ui`/`frame`
//  name the artifacts belonging to THAT event and are omitted when none was requested; the
//  NNN is the event's own sequence number, so a line and its artifacts always share it.
//
//  ** A UI SNAPSHOT CANNOT SEE THE CAMERA. **
//  `AVCaptureVideoPreviewLayer` draws into a hardware surface owned by the render server.
//  `drawHierarchy` renders the app's own layer tree and composites that surface as EMPTY —
//  so ui-*.png comes out black over the preview whether the camera is working perfectly or
//  not running at all. A UI snapshot is evidence about CHROME ONLY: which screen is up,
//  whether the countdown/overlays/buttons are there. It is never, in any circumstance,
//  evidence about the camera. Every event that carries one also carries
//  `"ui_excludes": "camera_preview"` in its props so the timeline says this out loud and a
//  host script can assert on it rather than relying on someone remembering.
//
//  HOW TO ACTUALLY ANSWER "WHY IS THE SCREEN BLACK"
//  -----------------------------------------------
//  Every event carries `frames_seen` and `last_frame_age_s`, so `timeline.jsonl` alone
//  settles it — the artifacts are corroboration, not the proof:
//
//    frames_seen == 0 AND                       the capture pipeline is genuinely dead. Look
//      video_data_output == true                at the configure_phase / camperf lines above.
//    frames_seen == 0 AND                       NOT a camera fault. The probe only counts
//      video_data_output == false               frames from the video-data output, and this
//                                               session never got one — the preview and the
//                                               movie output may be working perfectly. Read
//                                               `frames_seen` here as "not measured".
//    frames_seen climbing, no preview_attach_*  frames are fine, the layer never landed.
//    preview_attach_requested with no _landed   sessionQueue is wedged; the attach never ran.
//    attach landed, bounds 0x0                  attached correctly to a zero-sized layer —
//                                               black for a third, unrelated reason.
//    frames climbing + attach landed + black    a rotation/geometry or gravity problem.
//    frame_capture_timeout in the timeline      a frame artifact was requested and NO frame
//                                               arrived to satisfy it — a positive assertion
//                                               of "no frames", not a missing file to guess at.
//    no `record_tapped` after the user tapped   the Button never ran its action. It is
//                                               `.disabled(!isCameraReady)`, so check
//                                               `session_running` — or suspect hit-testing,
//                                               which no scenario here can exercise.
//
//  THE FRAME LATCH
//  ---------------
//  Retaining a `CVPixelBuffer` past `captureOutput` starves the capture pool and collapses
//  the pipeline — a real hazard here, and it would corrupt the very measurement we came for.
//  So no buffer is ever held: `requestFrameCapture` sets a flag, and the next `noteFrame`
//  sees it, encodes THAT buffer to JPEG inline, and clears it. The cost is a single encode
//  hitch on the video queue, paid only for a latched frame.
//

#if DEBUG

// Explicit, module by module: the target builds with
// `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`, so a member is only visible when the
// module declaring it is imported directly — re-exports do not count.
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import UIKit

/// `nonisolated` because the target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`:
/// an unannotated class would be implicitly `@MainActor` and therefore unreachable from
/// `videoOutputQueue` and `sessionQueue`, which is where the interesting evidence lives.
/// State is guarded by NSLock, matching the convention used across the capture path.
nonisolated final class DeviceProbe: @unchecked Sendable {

    // MARK: - Gate

    /// Read once from the environment. Call sites check this BEFORE `shared` is touched, so
    /// a disabled probe costs exactly one static bool read: no run directory, no file
    /// handle, no CIContext, no lock ever taken.
    static let isEnabled = ProcessInfo.processInfo.environment["GSS_PROBE"] == "1"

    static let shared = DeviceProbe()

    // MARK: - Call-Site Entry Points

    /// The gate every instrumented site goes through. Static so that `shared` — which
    /// creates the run directory and opens the timeline — is never materialised when the
    /// probe is off.
    static func event(_ name: String, _ props: [String: String] = [:], ui: Bool = false, frame: Bool = false) {
        guard isEnabled else { return }
        shared.event(name, props, ui: ui, frame: frame)
    }

    /// The 30 fps path. One bool read when disabled.
    static func noteFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isEnabled else { return }
        shared.noteFrame(pixelBuffer)
    }

    /// Stable per-object label, for telling two instances of the same type apart in the
    /// timeline — which is how the throwaway-view-model bug becomes visible mechanically
    /// rather than by inference.
    static func identity(_ object: AnyObject) -> String {
        String(UInt(bitPattern: ObjectIdentifier(object)), radix: 16)
    }

    // MARK: - Configuration

    /// How long a requested frame artifact waits for a frame before the timeline is told,
    /// in so many words, that none arrived.
    private static let frameCaptureTimeout: TimeInterval = 3

    // MARK: - State

    private let start = ProcessInfo.processInfo.systemUptime
    private let run = DiagnosticsRun()
    private let frames = FrameLatch()
    private let sequenceLock = NSLock()
    private var sequence = 0

    private init() {}

    // MARK: - Recording

    /// Callable from any thread or actor. Synchronous and `nonisolated` on purpose: an
    /// `async` variant would, under NonisolatedNonsendingByDefault, run on the caller's
    /// actor, and a `Task` hop off the frame path is exactly the cost this must not have.
    /// Only the file write is deferred, to `DiagnosticsRun`'s serial queue.
    func event(_ name: String, _ props: [String: String] = [:], ui: Bool = false, frame: Bool = false) {
        guard Self.isEnabled else { return }
        // Read at the call site, before the queue hop: taken inside the write it would
        // record when the line was flushed, not when the thing happened.
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let index = nextSequence()
        let uiArtifact = ui ? Self.artifact("ui", index, "png") : nil
        let frameArtifact = frame ? Self.artifact("frame", index, "jpg") : nil

        run.appendLine(line(elapsed, name, annotate(props, ui: uiArtifact), uiArtifact, frameArtifact))

        if let uiArtifact { captureUISnapshot(uiArtifact) }
        if let frameArtifact { requestFrameCapture(frameArtifact) }
    }

    /// Invoked from `CameraService.captureOutput(_:didOutput:from:)` on the video queue.
    /// Counting is unconditional and cheap; encoding happens only for a latched frame.
    func noteFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let artifact = frames.note() else { return }
        guard let data = frames.encode(pixelBuffer) else {
            event("frame_encode_failed", ["artifact": artifact])
            return
        }
        run.writeArtifact(data, named: artifact)
    }

    // MARK: - Line Assembly

    /// Frame stats ride on EVERY event, not just the ones that ask for an artifact. Two
    /// reads under one lock, and it is what lets `timeline.jsonl` answer the founding
    /// question without the artifacts being pulled at all. Call-site props win a collision,
    /// so an event can always override.
    private func annotate(_ props: [String: String], ui: String?) -> [String: String] {
        var annotated = props.merging(frames.stats()) { callSite, _ in callSite }
        guard ui != nil else { return annotated }
        annotated["ui_excludes"] = "camera_preview"
        return annotated
    }

    /// `JSONSerialization` stays authoritative for escaping — props carry free text (camperf
    /// messages, error descriptions) that can contain quotes, newlines and unicode. Only the
    /// timestamp is written by hand, spliced in right after the opening brace: serialized as
    /// a `Double` it comes out as "0.033000000000000002", which is valid JSON but defeats a
    /// timeline meant to be skimmed. Splicing is safe because the object is never empty — it
    /// always carries `event` and `props` — so there is always a key to put a comma before.
    private func line(_ elapsed: Double, _ name: String, _ props: [String: String], _ ui: String?, _ frame: String?) -> Data {
        var object: [String: Any] = ["event": name, "props": props]
        if let ui { object["ui"] = ui }
        if let frame { object["frame"] = frame }
        guard let body = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              body.count > 2, body.first == UInt8(ascii: "{") else { return Data() }

        var line = Data(#"{"t":"#.utf8)
        line.append(Data(String(format: "%.3f", elapsed).utf8))
        line.append(UInt8(ascii: ","))
        line.append(body.dropFirst())
        line.append(UInt8(ascii: "\n"))
        return line
    }

    private func nextSequence() -> Int {
        sequenceLock.lock()
        defer { sequenceLock.unlock() }
        sequence += 1
        return sequence
    }

    private static func artifact(_ prefix: String, _ index: Int, _ suffix: String) -> String {
        "\(prefix)-\(String(format: "%03d", index)).\(suffix)"
    }

    // MARK: - Artifacts

    /// Main-actor only — UIKit's contract, and `drawHierarchy` is meaningless anywhere else.
    /// Deliberately `afterScreenUpdates: false`: `true` forces a synchronous layout+commit
    /// that is expensive and can deadlock when called during layout, which is precisely when
    /// a freeze harness is most likely to fire.
    private func captureUISnapshot(_ name: String) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let data = UISnapshot.render() else {
                    self.event("ui_snapshot_failed", ["artifact": name, "reason": "no_foreground_key_window"])
                    return
                }
                self.run.writeArtifact(data, named: name)
            }
        }
    }

    /// Latch the request, then hold it to a deadline. Without the deadline a frame that
    /// never arrives shows up only as a file missing from the pull — something a reader has
    /// to notice and interpret. The timeout event states it instead.
    private func requestFrameCapture(_ name: String) {
        if let displaced = frames.request(name) {
            event("frame_capture_superseded", ["artifact": displaced, "superseded_by": name])
        }
        run.after(Self.frameCaptureTimeout) { [weak self] in
            guard let self, self.frames.withdraw(name) else { return }
            self.event("frame_capture_timeout", [
                "artifact": name,
                "waited_s": String(format: "%.1f", Self.frameCaptureTimeout),
                "meaning": "no camera frame was delivered — the capture pipeline is not producing"
            ])
        }
    }
}

// MARK: - Run Directory

/// Owns one run's directory, its timeline handle and its serial write queue.
/// `nonisolated` for the same reason as `DeviceProbe`: it is written to from the capture
/// queues, and the default MainActor isolation would otherwise put it out of their reach.
private nonisolated final class DiagnosticsRun: @unchecked Sendable {

    private let directory: URL
    private let handle: FileHandle?
    private let queue = DispatchQueue(label: "com.golfsync.diagnostics.io", qos: .utility)

    init() {
        let root = URL.documentsDirectory.appending(path: "diagnostics", directoryHint: .isDirectory)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        directory = root.appending(path: stamp.string(from: Date()), directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let timeline = directory.appending(path: "timeline.jsonl")
        FileManager.default.createFile(atPath: timeline.path(percentEncoded: false), contents: nil)
        handle = try? FileHandle(forWritingTo: timeline)

        // stdout, which `devicectl device process launch --console` captures — the same
        // reason CAMPERF prints. It tells the host the probe armed and which run to pull,
        // and if the handle failed to open it says so HERE, because a probe that cannot
        // write cannot report its own failure through the timeline.
        print("GSSPROBE run=\(directory.lastPathComponent) timeline=\(handle == nil ? "FAILED TO OPEN" : "open")")
    }

    /// One unbuffered `write(2)` per line, never batched and never fsync'd. This harness
    /// investigates freezes and watchdog kills, so a line must be in the kernel's page cache
    /// — which outlives the process — the moment it is produced; buffering would lose
    /// exactly the last few lines, the ones describing the failure. An fsync per line would
    /// stall this queue on flash I/O for no extra safety against anything but power loss.
    func appendLine(_ data: Data) {
        queue.async { [handle] in
            try? handle?.write(contentsOf: data)
        }
    }

    func writeArtifact(_ data: Data, named name: String) {
        let url = directory.appending(path: name)
        queue.async { try? data.write(to: url) }
    }

    func after(_ delay: TimeInterval, _ work: @escaping @Sendable () -> Void) {
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

// MARK: - Frame Latch

/// The always-on frame counter and the request/latch that turns one frame into a JPEG
/// without ever retaining a buffer.
/// `nonisolated`: `note()` and `encode()` run on `videoOutputQueue`, inside the capture
/// callback itself.
private nonisolated final class FrameLatch: @unchecked Sendable {

    /// Downscale target. Small keeps the inline encode and the write short, and 640px is
    /// ample for "is there a person in frame, is it upside down, is it the front camera".
    private static let maximumEdge: CGFloat = 640

    private let lock = NSLock()
    private var count = 0
    private var lastFrameUptime: Double = 0
    private var pending: String?

    /// Built once. A per-encode `CIContext()` allocates a Metal context and compiles
    /// shaders — hundreds of milliseconds, inside a capture callback.
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    /// The 30 fps path: one lock, two writes, one optional read. Returns the artifact name
    /// if this frame is the one that was asked for.
    func note() -> String? {
        lock.lock()
        count += 1
        lastFrameUptime = ProcessInfo.processInfo.systemUptime
        let requested = pending
        pending = nil
        lock.unlock()
        return requested
    }

    /// Returns the request this one displaced, if any. Only one frame can be latched at a
    /// time, so a second request arriving before the first is satisfied cancels it — and an
    /// artifact that is neither written nor accounted for is exactly the kind of silent gap
    /// this harness exists to remove.
    func request(_ name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let displaced = pending
        pending = name
        return displaced
    }

    /// Cancels a still-outstanding request, reporting whether it was still outstanding —
    /// i.e. whether no frame ever came to satisfy it.
    func withdraw(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard pending == name else { return false }
        pending = nil
        return true
    }

    func stats() -> [String: String] {
        lock.lock()
        let seen = count
        let last = lastFrameUptime
        lock.unlock()
        guard seen > 0 else { return ["frames_seen": "0", "last_frame_age_s": "never"] }
        let age = ProcessInfo.processInfo.systemUptime - last
        return ["frames_seen": String(seen), "last_frame_age_s": String(format: "%.3f", age)]
    }

    /// Encodes the buffer handed in and returns before the callback does. The buffer is
    /// borrowed for the duration of this call and never stored.
    func encode(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let longestEdge = max(image.extent.width, image.extent.height)
        guard longestEdge > 0 else { return nil }
        let scale = min(1, Self.maximumEdge / longestEdge)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.jpegRepresentation(of: scaled, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:])
    }
}

// MARK: - UI Snapshot

/// Renders the app's own layer tree. See the file header: this can never show the camera.
private enum UISnapshot {

    @MainActor
    static func render() -> Data? {
        guard let window = keyWindow() else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return image.pngData()
    }

    @MainActor
    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }
    }
}

#endif
