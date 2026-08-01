//
//  SwingFrameBuffer.swift
//  golf-sync-swing
//
//  A few seconds of the take, JPEG-encoded at the camera's own resolution, held in memory so a
//  swing can be replayed while the recording is still running. It backs BOTH capture surfaces: the
//  full-screen replay and the live tile beside it draw the same JPEGs at different sizes — which is
//  why `RingFrameDecoder` exists, and why the tile does not pay for a full-size bitmap.
//
//  Two prohibitions shape everything below, and both were paid for on device:
//
//    * The recording file MUST NOT be read while it is being written. Opening the in-progress
//      .mov with `AVURLAsset` makes iOS terminate the capture, so the replay cannot come from
//      the file. It cannot come from a second `AVCaptureVideoPreviewLayer` either — attaching
//      one to the running session is what turned the main preview black. It comes from here.
//    * A `CVPixelBuffer` MUST NOT outlive its capture callback. Retaining buffers starves the
//      capture pool and collapses the pipeline, so the callback COPIES the frame's bytes into a
//      buffer the app owns (`CapturedFrameRelay`) and releases the capture buffer with the
//      callback. Only the resulting `Data` is kept here.
//
//  WHERE THE WORK HAPPENS, AND WHY IT MOVED
//  ----------------------------------------
//  The scale and the JPEG encode used to run INLINE on the video queue, which capped the
//  replay's resolution at whatever fitted inside one frame period — `alwaysDiscardsLateVideoFrames`
//  turns an overrunning callback into a DROPPED frame, and a dropped frame is one the DETECTOR
//  wanted. They now run on `CapturedFrameRelay`'s own workers, below the video queue's
//  priority, on a copy. The capture callback's share of a sampled frame is a `memcpy`.
//
//  The consequence the rest of the app has to know about: a frame is in the ring some
//  milliseconds AFTER it was captured, so a just-detected swing's tail may not be encoded yet.
//  `hasFrames(through:)` is how a caller waits for it, and `RecordingViewModel` is what waits.
//
//  WHAT LIMITS IT NOW IS MEMORY, NOT THE FRAME PERIOD
//  -------------------------------------------------
//  Storing frames at 1080x1920 costs ~250–400KB each (ESTIMATED), so the window's length is a
//  megabyte-a-tenth-of-a-second decision. Three consequences are load-bearing and are documented
//  where they are paid: the bound that actually binds is counted in BYTES
//  (`maximumHeldBytes`), because a frame count promises nothing about cost, which is what lets the
//  time window be as wide as a late pull needs (`retainedDuration`); and the whole ring is
//  surrendered on a system memory-pressure event (`shed(under:)`), because it is held while
//  AVFoundation is writing a movie file and losing the RECORDING is not an acceptable way to keep a
//  replay.
//
//  That last one does not stop at the ring, and it cannot. `frames(from:to:)` hands out the SAME
//  refcounted `Data` values the ring holds, so a replay on screen keeps its share of them alive
//  through a shed — which is why the event is fanned out past this object as well
//  (`onShed`) rather than merely emptying `samples`.
//
//  `nonisolated` + `NSLock`, matching `DeviceProbe` and the rest of the capture path: the
//  target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and an implicitly
//  `@MainActor` type would be unreachable from `videoOutputQueue` — the only place frames
//  exist.
//

// Explicit, module by module: the target builds with
// `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`, so re-exports do not count.
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO
// Required for `Logger`'s string interpolation: the target enables MemberImportVisibility,
// so `AppLogger.camera.error("…\(value)…")` does not compile without `os` imported here.
import os

nonisolated final class SwingFrameBuffer: @unchecked Sendable {

    /// One stored frame. `timestamp` is recording-relative — the same timeline
    /// `SwingClip.startTime`/`endTime` carry — so a detected swing's range can be handed
    /// straight to `frames(from:to:)`.
    private struct Sample {
        let timestamp: TimeInterval
        let jpeg: Data
    }

    /// What the ring is holding right now. Diagnostics only: it is what turns "the tile
    /// didn't appear" into a number instead of a guess.
    struct Coverage {
        let count: Int
        let oldest: TimeInterval?
        let newest: TimeInterval?
        /// MEASURED — the sum of the JPEGs actually held, not a figure reasoned from the frame
        /// count. It is the number that says whether the memory budget this ring was sized against
        /// survives contact with a real driving range.
        let bytes: Int
        /// How many times the system's memory pressure has made this ring give everything back
        /// since the process started. Any non-zero value is the interesting one.
        let sheds: Int
    }

    /// The newest frame in the ring, tagged with a number that only ever grows.
    ///
    /// This is the LIVE camera feed for the picture-in-picture tile when the replay has taken
    /// over the main screen — the tile cannot mount a second preview layer, so it draws these
    /// instead. `sequence` is what lets it skip a JPEG decode when it polls faster than
    /// frames arrive, which it deliberately does.
    struct LatestFrame {
        let sequence: UInt64
        let jpeg: Data
    }

    // MARK: - Configuration

    /// Long-edge target in pixels, and the one number that sets what every replay costs.
    ///
    /// **This is the ceiling. There is nothing above it**: 1920 is the long edge of the buffer the
    /// camera delivers, so a stored frame now holds every pixel the sensor gave us and the scale
    /// step is gone rather than merely gentle. Raised from 1280 because the owner asked for more
    /// quality twice and accepted a longer wait for it, and because the two rounds before this one
    /// were spending pixels the pipeline already had.
    ///
    /// **Every figure below marked ESTIMATED is reasoned from pixel counts or plane arithmetic, not
    /// timed on a device.** `ring_encode`, emitted by `noteEncodeCost`, is there so the next person
    /// replaces them with measurements instead of re-deriving them.
    ///
    ///   * READABILITY, WHICH IS THE POINT. The replay is drawn FULL SCREEN. `.fit` of a 9:16 frame
    ///     into a 393pt-wide screen is WIDTH-limited, so at 3x it is drawn 1179×2096px whatever the
    ///     cover's vertical insets are. Upscale is now 2096/1920 = **1.09x** — effectively @3x
    ///     pixel-native on this screen — against 1.64x at 1280, 3.3x at 640 and 8.7x at the
    ///     original 240. What limits the picture from here is not this file: it is a 1080p sensor
    ///     and the motion blur on a club head that crosses the frame inside one 30fps exposure.
    ///   * PIXEL-NATIVE IN GEOMETRY, NOT IN COLOUR. The frame still makes a YCbCr → RGB → 4:2:0
    ///     round trip through `jpegRepresentation`, so chroma is resampled even though luma is not.
    ///     Nothing here can recover that without leaving CoreImage.
    ///   * THE SCALE PASS DOES NOT DISAPPEAR AT NATIVE — it never was its own pass. CoreImage folds
    ///     an affine transform into the single render `jpegRepresentation` performs, so what native
    ///     removes is `highQualityDownsample`'s extra filtering, NOT a whole pass. Native therefore
    ///     costs MORE per frame than 1280 did, not less: the render's write, the readback and the
    ///     JPEG all scale with output pixels, and 1080×1920 is 2.07M against 0.92M. ESTIMATED
    ///     ~36–65ms on this A17 and ~60–110ms on the A13-class device iOS 26 still admits, against
    ///     a 66.7ms sampled-frame period — which is why `CapturedFrameRelay` now encodes on TWO
    ///     workers and why the budget is 133ms rather than 66.7ms. Overrunning even that costs a
    ///     pending frame, never a frame the detector wanted.
    ///   * SOURCE GEOMETRY. `CaptureSessionConfigurator` targets 1080p, which arrives 1080×1920
    ///     after rotation. Both dimensions are even and divisible by 8, which is what a JPEG
    ///     encoder's 4:2:0 chroma planes and DCT blocks want, and 1920 halves exactly three times —
    ///     which is what lets `RingFrameDecoder` decode the picture-in-picture tile at 1/4 scale
    ///     straight out of the DCT blocks.
    ///   * MEMORY, WHICH IS THE BINDING CONSTRAINT. ~250–400KB per frame at q0.75 (ESTIMATED, 5–6x
    ///     the 45–70KB MEASURED at 640 for 9x the pixels — JPEG size grows sub-linearly), so the
    ///     90-frame ring a 6s window holds at 15fps is ~22–36MB and `maximumHeldBytes` caps it at
    ///     28MB — which is to say the ring costs 28MB on an expensive scene and less on a cheap one,
    ///     whatever `retainedDuration` says. The rest of the footprint is stated where it is paid:
    ///     `CapturedFrameRelay.defaultCapacity` and `maximumPoolBytes` for the pool (~12.5MB) and
    ///     `SwingReplayPlayerView.bitmapBudget` for the decoded bitmaps (~25MB, which is what two
    ///     full-size bitmaps plus one being decoded already cost).
    ///   * THE STEP DOWN, if a device run says this is too much, is 960 — half the pixels of every
    ///     figure above, at 2.18x upscale. Turn it before `compressionQuality`: quantisation noise
    ///     is the artifact this pass exists to remove.
    private static let maximumEdge: CGFloat = 1920

    /// What a stored frame's long edge IS, for the surfaces that draw them. `RingFrameDecoder`
    /// quantises against it: decoding larger than this only upsamples a JPEG, and decoding at
    /// exactly this is the one size that needs no resampling at all.
    static var storedLongEdge: Int { Int(maximumEdge) }

    /// Every other frame — 15 fps out of the 30 fps the app configures. A looping replay reads
    /// fine at 15, and halving the rate halves the memory the ring holds, the copies the capture
    /// callback makes, and the encoder's duty cycle all at once.
    ///
    /// Held at 2 through two rounds of raising `maximumEdge`, and that is deliberate. Stride 3
    /// (10 fps) would buy back a third of every cost above — but a downswing lasts ~0.25s, so
    /// 10 fps puts two or three frames across the fastest and most-watched part of the swing and
    /// can miss the strike entirely. Resolution is what the user reported; frame rate is what
    /// makes a replay legible at all.
    ///
    /// It is also what sets the encoder's arrival period: one SAMPLED frame, 66.7ms. With
    /// `CapturedFrameRelay.defaultWorkers` encoding at once the budget PER FRAME is that times the
    /// worker count — 133ms — which is the whole reason native resolution is affordable. What this
    /// number no longer sets is anything the detector pays: the capture callback's share is a
    /// `memcpy` whatever it is.
    private static let sampleStride = 2

    /// The rate a pulled range plays back at, published so `SwingReplayPlayerView` times its
    /// loop off the ring that filled it instead of repeating the number and drifting from it.
    /// The 30 is the frame rate `RecordingView.warmUpCamera` asks the session for.
    ///
    /// Integer, and therefore only exact while `sampleStride` divides 30 — it does at 2 (15) and
    /// at 3 (10). A stride of 4 would truncate 7.5 to 7 and play every replay ~7% slow, so a
    /// stride that does not divide the capture rate has to make this a `Double`. A capture-rate
    /// change has to be brought here by hand either way.
    static let sampledFrameRate = 30 / sampleStride

    /// How much of the take is kept. **Back at 6s, and the paragraph under this one is what has to be
    /// read before it is trimmed again.**
    ///
    /// It was cut to 4s on frame-count arithmetic — 60 frames at 15fps, ~15–24MB — and that
    /// arithmetic was answering a question `maximumHeldBytes` had already been added to answer.
    /// The two bounds are not alternatives: `evict` applies BOTH, so the window is whichever binds
    /// first, and the byte ceiling is the one denominated in the thing that costs anything. What
    /// this number decides on its own is only how long a window a CHEAP scene may keep.
    ///
    ///   * A clip spans `impact - 1.5 ... impact + 1.0` (`DetectionOrchestrator`: `impactTime - 1.0
    ///     - clipPaddingBefore` to `impactTime + 0.5 + clipPaddingAfter`), so the RANGE itself is
    ///     2.5s wide and that is the floor.
    ///   * The range is pulled once the ring has reached `clip.endTime`, so what has to fit is the
    ///     2.5s span plus however far past `endTime` the newest frame has got by then: the report
    ///     lag between a frame being captured and detection naming it (a Vision pass, 100–300ms,
    ///     plus a main-queue hop) and the encoder's own latency. 4.0s left **1.5s** for both; 6.0s
    ///     leaves **3.5s**.
    ///   * **And it is the difference between a partial replay and none at all**, which is what the
    ///     trim's own justification got backwards. `frames(from:to:)` filters by timestamp, so a
    ///     range whose LEAD-IN has aged out yields a partial clip — but a range whose END is older
    ///     than `newest - retainedDuration` yields NOTHING, and at 4.0s a pull that landed even 1.5s
    ///     late was over that line. The failure mode of a wide window is a replay that starts a
    ///     little late (the least-watched half-second of address); the failure mode of a narrow one
    ///     is a golfer told a swing was detected and shown no swing.
    ///
    /// What the extra 2s costs, in bytes rather than frames: 6.0s at 15fps is 90 frames, which is
    /// 22.5MB at the 250KB end of the per-frame estimate and 36MB at the 400KB end. So a cheap scene
    /// keeps the whole 6s inside the 28MB ceiling, and an expensive one is trimmed BY THAT CEILING to
    /// ~70 frames (4.7s) — still a wider window than the 4.0s trim gave, and not one byte more
    /// memory than `maximumHeldBytes` already promised. Raising this cannot raise what the ring
    /// costs. That is the whole point of measuring the bound in bytes.
    private static let retainedDuration: TimeInterval = 6

    /// The memory backstop, in the unit that actually binds — **and therefore the reason
    /// `retainedDuration` does not have to be the thing that keeps the ring small.** Replaces a frame
    /// count, and the change is not cosmetic: JPEG size varies with how much detail is in the scene,
    /// so a fixed frame count bounds the ring's LENGTH while promising nothing about its cost, which
    /// is the one thing this ring has to promise now that a frame is 2.25x the pixels.
    ///
    /// 28MB is ~60 frames at ~470KB apiece. Read against a 6s/90-frame time window that means THIS
    /// is what decides the ring's length on an expensive scene (a busy background, a driving-range
    /// net, a 60fps format) while the time window decides it on a cheap one — and either way the
    /// cost is bounded here. **So trimming the time window to save memory saves nothing this has not
    /// already promised**; it only shortens the window a cheap scene is allowed to keep, and a
    /// shorter window is what turns a late pull from partial into empty.
    ///
    /// It cannot cut below the clip span while binding: even at a pathological 700KB a frame, 28MB is
    /// 40 frames — 2.7s at 15fps, still wider than the 2.5s a clip asks for.
    private static let maximumHeldBytes = 28 * 1024 * 1024

    /// Chosen for the upscale, not for the file. At 1.09x the 8×8 blocking that q0.6 leaves along a
    /// club shaft is drawn 8.7px wide, and the club's line is most of what a golfer is looking for.
    /// 0.75 is where those artifacts stop being visible; past it the bytes climb and the picture does
    /// not.
    ///
    /// Deliberately NOT lowered to pay for `maximumEdge`, in either round. Trading quantisation
    /// noise for pixels would put back, in a different form, exactly the softness the resolution was
    /// raised to remove. It is the SECOND knob to turn if a device run says the ring is too big —
    /// 0.7 saves ~10–15% of the bytes (ESTIMATED) and, at this upscale, has less to give away than
    /// it did at 1.64x — but `maximumEdge`'s step down to 960 comes first, because it halves the
    /// decoded bitmaps too and this does not touch them.
    private static let compressionQuality = 0.75

    private static let qualityOption = CIImageRepresentationOption(
        rawValue: kCGImageDestinationLossyCompressionQuality as String
    )

    // MARK: - State

    private let lock = NSLock()
    private var samples: [Sample] = []
    private var isCollecting = false

    /// What `samples` costs, kept in step with it rather than summed on demand: the probe reads it
    /// once per report and `evict` reads it once per frame, and a 60-element reduce on the encode
    /// path to answer a question the array already knows would be a poor trade. Every path that
    /// changes `samples` — `append`, `drop`, `dropEverything` — maintains it, and those are the only
    /// three.
    private var heldBytes = 0

    /// Where a frame goes when the capture callback is done with it: a bounded pool of buffers
    /// the app owns, and the workers the encode runs on. It is the whole reason `maximumEdge` could
    /// be raised — and the whole reason `hasFrames(through:)` exists.
    private let relay = CapturedFrameRelay(label: "com.golfsync.camera.ringEncode")

    /// The safety valve. Holding tens of megabytes of JPEGs WHILE AVFoundation writes a movie file
    /// is a bet, and this is what settles it in the recording's favour: under system memory pressure
    /// the ring is thrown away rather than the app being killed with the take unfinalised.
    private let pressure = MemoryPressureMonitor()

    /// Fired once a pressure event has emptied the ring, on the pressure source's queue.
    ///
    /// **The valve does not work without it.** `frames(from:to:)` hands out the SAME refcounted
    /// `Data` values this object holds, and `RecordingViewModel.swingReplay` retains them for as long
    /// as a replay is on screen — so emptying `samples` frees the frames NOBODY is looking at and
    /// leaves the ones being replayed exactly where they were. Under real pressure, which is the only
    /// time this runs, that is most of what there was to give back. This is how the event reaches the
    /// object actually holding them.
    ///
    /// Lock-guarded, which is a departure from the `relay.encode` / `pressure.onPressure` rule that a
    /// collaborator's handler is written once before anything can reach it. Those two are written by
    /// the object that BUILDS the collaborator; this one's listener is `RecordingViewModel`, which
    /// claims it in `activate()` and drops it in `deactivate()` — main-actor writes that can land
    /// while a take, and therefore a pressure event, is in flight.
    var onShed: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return shedHandler }
        set { lock.lock(); defer { lock.unlock() }; shedHandler = newValue }
    }

    private var shedHandler: (() -> Void)?

    /// Frames to admit nothing for, counted down in `admit`. Set by a CRITICAL pressure event, and
    /// counted in frames rather than seconds deliberately: the pressure source has no access to the
    /// capture clock, and the only clock this path can trust is the one delivering the frames.
    private var suppressedFrames = 0

    /// How many times pressure has emptied the ring. Not reset by `start()`: a device that sheds
    /// once a take is telling us something about the whole session, not about one take.
    private var sheds = 0

    /// Bumped by every `start()`. An admitted frame carries the generation it belongs to, so
    /// one still being encoded across a `stop()`/`start()` pair is dropped rather than
    /// appended to the next take with the previous take's time origin. Same device
    /// `DetectionOrchestrator` uses for its own frames.
    private var generation: UInt64 = 0

    /// Host-clock time of the take's first frame. Everything stored is relative to it.
    private var base: TimeInterval?
    private var admitted = 0

    /// Every frame the ring has ever admitted, counted once. Monotonic for the life of the
    /// process and deliberately NOT reset by `start()`: the live tile compares this against
    /// what it last drew, and a counter that restarted at zero would make it treat a new
    /// take's frames as already-drawn until the count caught up with the previous take's.
    private var sequence: UInt64 = 0

    /// Built on first use — on a relay worker, inside the first encode — and then reused for the
    /// life of the process. A `CIContext` allocates a Metal device and compiles shaders, so building
    /// one per frame is out of the question; building one eagerly instead would put that cost on app
    /// launch, where `CameraService.shared` is created and where this app has already lost a cold
    /// start once.
    ///
    /// **Locked, and that is what the second encode worker cost.** One `CIContext` shared across
    /// workers is fine — Apple documents contexts and images as safe to use from several threads —
    /// but the lazy CREATION is not, so the two workers that could race to build it take a lock the
    /// ring's own does not have to wait behind. Uncontended, once a take is under way, that is a
    /// handful of nanoseconds against a ~50ms encode.
    private let contextLock = NSLock()
    private var context: CIContext?

    /// The take whose uprightness the canary below has already checked. A generation rather
    /// than a bool because the connection's rotation is re-applied by every
    /// `CameraService.configureSession` — a camera flip included — so a once-per-process check
    /// would go quiet on exactly the path a future change is most likely to break.
    ///
    /// The one piece of state here that is still deliberately unlocked, and it can be because it
    /// never left the video queue: `reportIfLandscape` is its sole reader and sole writer and runs
    /// inside `ingest`, which is serial by AVFoundation's own contract. `context` used to say the
    /// same about the relay's queue and no longer can — that is what the second worker changed.
    private var lastCheckedGeneration: UInt64?

    // MARK: - Init

    /// The relay's collaborators are handed over here rather than through its own initializer,
    /// because they are methods of this object. Written once, before any capture callback can reach
    /// the relay, which is what makes them safe to leave unlocked.
    ///
    /// The two halves are separate for one reason: `encode` may run on several workers at once,
    /// while `append` must see frames in the order they were captured — `hasFrames(through:)` is a
    /// claim about everything BEFORE a timestamp, and it would be a lie if a frame could arrive
    /// after a later one. The relay is what turns parallel work back into an ordered sequence.
    init() {
        relay.encode = { [weak self] frame in self?.encodeMeasuringCost(frame.pixelBuffer) }
        relay.deliver = { [weak self] encoded in self?.append(encoded) }
        pressure.onPressure = { [weak self] level in self?.shed(under: level) }
        pressure.start()
    }

    // MARK: - Warm-Up

    /// Pays the encoder's one-off costs BEFORE a take, and it is the relay's queue depth that
    /// makes this necessary rather than merely tidy.
    ///
    /// `encodingContext()` builds a `CIContext` on first use, and the first `jpegRepresentation` at
    /// a given output size specializes kernels on top of that. Spent on the take's first sampled
    /// frame, those milliseconds are the pool filling and then dropping its oldest pending frame
    /// once per frame until the context is up — so every FIRST take would open with a non-zero
    /// `dropped` in `ring_encode`, which is the one number that is supposed to mean the resolution
    /// is too much for the device. Warmed here, that number means what it says.
    ///
    /// Called from `RecordingViewModel.startRecording()`, alongside `SwingClassifier.warmUp()` and
    /// for exactly the same reason: a five-second countdown runs before the first frame is
    /// sampled, and that is the last quiet moment. Idempotent in effect — the context is built
    /// once, and a second call encodes another frame nobody keeps.
    ///
    /// Returns immediately: the relay does the whole thing on its own queue, because the caller is the
    /// main actor and the work is a pair of ~3.1MB buffers and a `memcpy` between them. Nothing reads
    /// the result, so there is nothing to wait for.
    func warmUp() {
        relay.warmUp(width: Self.warmUpWidth, height: Self.warmUpHeight, format: Self.warmUpFormat)
    }

    /// What the take's frames are going to be: `CaptureSessionConfigurator` targets 1080p and asks
    /// the video data output for full-range bi-planar YCbCr, and the connection's rotation makes
    /// that arrive portrait. A device that negotiates something else still gets the Metal device
    /// and the base kernels warmed, and loses only the size-specific specialization — so a drift
    /// between these three numbers and the configurator's costs performance, never correctness.
    private static let warmUpWidth = 1080
    private static let warmUpHeight = 1920
    private static let warmUpFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange

    // MARK: - Lifecycle

    /// Arms collection for one take. Called from `CameraService.startRecording()`, so an idle
    /// preview costs one bool read per frame and nothing else.
    func start() {
        lock.lock()
        isCollecting = true
        generation &+= 1
        base = nil
        admitted = 0
        // A pressure event between takes must not silence the one that is starting.
        suppressedFrames = 0
        dropEverything(keepingCapacity: true)
        lock.unlock()
        // Outside the lock, and after the generation bump: a frame copied for the PREVIOUS take
        // and still waiting to be encoded would be discarded by `append`'s generation check
        // anyway, but there is no reason to spend an encode finding that out.
        relay.discard()
    }

    /// Disarms and drops the ring. Idempotent, and called from every route a recording can
    /// end by: the Stop control, a discarded take, and the movie output's own delegate —
    /// which is the only funnel a spontaneous stop (interruption, disk full) passes through.
    func stop() {
        lock.lock()
        isCollecting = false
        base = nil
        dropEverything(keepingCapacity: false)
        lock.unlock()
        // The pool goes with the ring: an idle app holds neither. A slot the encoder is still
        // working on is released when it finishes with it.
        relay.discard()
    }

    // MARK: - Memory Pressure

    /// **The one place this file gives a replay up on purpose, and it is the right trade.** A replay
    /// is a courtesy; the recording is what the golfer came for, and an app jetsammed mid-take loses
    /// the movie file unfinalised. So when the system says memory is short, everything held here goes
    /// back immediately — up to 28MB of ring plus ~12.5MB of pool — rather than being defended.
    ///
    /// **And everything held ELSEWHERE on the strength of it**, which is the part that makes the
    /// valve real rather than nominal: `onShed` releases the replay that is retaining a share of the
    /// very `Data` values this method just dropped, and with it the decoded bitmaps the surface
    /// drawing them was holding (`SwingReplayPlayerView.bitmapBudget`, up to ~25MB). Dropping the
    /// ring alone would have freed only the frames nothing was looking at.
    ///
    /// The two levels differ in what happens NEXT, which is the only interesting part. A warning
    /// sheds and keeps collecting: the ring refills over the following seconds and the next swing
    /// still gets a replay. A critical event sheds and then admits nothing for `suppressedFrames`,
    /// because refilling straight back into a device that is about to kill something is how the valve
    /// becomes a leak. The take keeps recording either way, `hasFrames(through:)` simply stops
    /// advancing, and a replay still inside its wait falls through its own deadline to an empty pull —
    /// which `RecordingViewModel.adopt` handles by taking that swing's loading surface down and
    /// uncovering the live camera.
    ///
    /// `relay.discard()` OUTSIDE the ring's lock, matching `start()` and `stop()`: this arrives on
    /// the pressure source's queue while a worker may be inside the relay, and the two locks must
    /// never be taken in both orders.
    private func shed(under level: MemoryPressureMonitor.Level) {
        lock.lock()
        let shedBytes = heldBytes
        let shedFrames = samples.count
        dropEverything(keepingCapacity: false)
        // `max`, not assignment: a warning arriving inside a critical event's cooldown must not
        // shorten it. Pressure only ever extends the silence.
        suppressedFrames = max(suppressedFrames, Self.suppression(after: level))
        sheds += 1
        // Read from the stored property and NOT through `onShed`, whose getter takes this same lock —
        // `NSLock` is not reentrant, and that would be a deadlock on the pressure queue. Called below,
        // after the unlock: nothing in this file calls out from under the lock.
        let notify = shedHandler
        lock.unlock()
        relay.discard()
        notify?()
        AppLogger.camera.warning(
            "SwingFrameBuffer: shed \(shedFrames) replay frames (\(shedBytes / 1024)KB) under \(level.rawValue, privacy: .public) memory pressure — the recording continues"
        )
    }

    /// ~5s at the 30fps the app configures, and only for a critical event. Long enough that the
    /// device is past whatever needed the memory, short enough that a long take still gets replays
    /// afterwards.
    private static func suppression(after level: MemoryPressureMonitor.Level) -> Int {
        switch level {
        case .warning: return 0
        case .critical: return 150
        }
    }

    // MARK: - Capture Path

    /// Video-queue only, inside `captureOutput`. The buffer is borrowed for the duration of this
    /// call and never stored: its bytes are COPIED into a buffer the app owns and it is released
    /// with the callback.
    ///
    /// What this costs the detector is the copy — a `memcpy` of two planes, sub-millisecond
    /// (estimate) — and nothing else. The encode happens on the relay's workers.
    func ingest(_ pixelBuffer: CVPixelBuffer, at hostTime: TimeInterval) {
        guard let admission = admit(hostTime) else { return }
        reportIfLandscape(pixelBuffer, in: admission.generation)
        relay.submit(pixelBuffer, generation: admission.generation, timestamp: admission.timestamp)
    }

    private struct Admission {
        let generation: UInt64
        let timestamp: TimeInterval
    }

    /// The sampling gate, and the only thing that runs for every frame while idle.
    ///
    /// Latches the take's time origin on the first frame it sees. `DetectionOrchestrator`
    /// latches its own a few main-actor statements later, so the two can disagree by however
    /// many frames land in between — an unmeasured number, but a signed one: this origin is
    /// never LATER than the detector's, so a pulled range can only shift toward the lead-in,
    /// never off the end of the follow-through.
    private func admit(_ hostTime: TimeInterval) -> Admission? {
        lock.lock()
        defer { lock.unlock() }
        guard isCollecting, !isSuppressed() else { return nil }
        if base == nil { base = hostTime }
        admitted += 1
        guard admitted % Self.sampleStride == 0 else { return nil }
        return Admission(generation: generation, timestamp: hostTime - (base ?? hostTime))
    }

    /// Lock held. Counts down what a critical pressure event bought back. Before the time origin is
    /// latched, so a suppressed stretch neither moves the timeline nor shifts the sampling phase —
    /// the frames simply are not there, exactly as if the detector had dropped them.
    private func isSuppressed() -> Bool {
        guard suppressedFrames > 0 else { return false }
        suppressedFrames -= 1
        return true
    }

    /// The relay's `deliver`, and therefore **already in capture order however many workers encoded
    /// the frames** — `CapturedFrameRelay` holds a frame that finished early behind the ones in front
    /// of it. Everything below depends on that: `samples` is sorted by construction, which is what
    /// makes a range pull a filter and `hasFrames(through:)` a single comparison.
    private func append(_ encoded: CapturedFrameRelay.Encoded) {
        append(Sample(timestamp: encoded.timestamp, jpeg: encoded.data), in: encoded.generation)
    }

    private func append(_ sample: Sample, in generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        // stop(), or a whole stop()/start() pair, can land between the copy and the encode —
        // and now that they are on different queues, that window is wider than it was.
        guard isCollecting, generation == self.generation else { return }
        samples.append(sample)
        heldBytes += sample.jpeg.count
        // One increment under the lock that was already taken. Nothing else about ingest
        // changes: no extra lock, no extra allocation, and still nothing retained.
        sequence &+= 1
        evict(olderThan: sample.timestamp - Self.retainedDuration)
    }

    /// Time first, then the byte ceiling. Both measured from the front, because the ring only
    /// ever grows at the back.
    private func evict(olderThan cutoff: TimeInterval) {
        drop(samples.prefix { $0.timestamp < cutoff }.count)
        drop(overflowing())
    }

    /// How many of the oldest samples `maximumHeldBytes` wants gone. Never the last one: a ring that
    /// evicted the frame it just took would hold nothing at all, and the live tile draws that frame.
    private func overflowing() -> Int {
        var excess = heldBytes - Self.maximumHeldBytes
        var count = 0
        while excess > 0, count < samples.count - 1 {
            excess -= samples[count].jpeg.count
            count += 1
        }
        return count
    }

    /// Lock held, and the ONLY way samples leave the front — so `heldBytes` cannot drift from what
    /// the array actually holds.
    private func drop(_ count: Int) {
        guard count > 0 else { return }
        heldBytes -= samples.prefix(count).reduce(0) { $0 + $1.jpeg.count }
        samples.removeFirst(count)
    }

    /// Lock held, and the only way the ring is emptied: a take starting, a take ending, or memory
    /// pressure. Three callers, one accounting.
    private func dropEverything(keepingCapacity: Bool) {
        samples.removeAll(keepingCapacity: keepingCapacity)
        heldBytes = 0
    }

    /// The canary for the uprightness dependency `encode` documents: two integer reads and one
    /// comparison, on the first sampled frame of each take, and nothing at all thereafter.
    ///
    /// A log line and not a trap. A sideways replay is cosmetic, while an `assertionFailure`
    /// raised inside `captureOutput` would present it as a capture-pipeline crash — pointing
    /// the next investigation at the session rather than at the rotation that actually moved.
    ///
    /// Reads the pixel buffer's own dimensions rather than the `CIImage` extent so `encode`
    /// stays free of diagnostics, and so this runs before the encode rather than inside it.
    private func reportIfLandscape(_ pixelBuffer: CVPixelBuffer, in generation: UInt64) {
        guard lastCheckedGeneration != generation else { return }
        lastCheckedGeneration = generation
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > height else { return }
        AppLogger.camera.error(
            "SwingFrameBuffer: frames arrive landscape (\(width)x\(height)) — the video data output's connection lost its rotation angle, so every replay will play sideways"
        )
    }

    // MARK: - Replay

    /// The JPEGs covering a detected swing, oldest first, in the recording-relative timeline
    /// `SwingClip` carries. Empty when the range aged out before it was asked for — the
    /// caller shows no tile at all rather than an empty one.
    ///
    /// **A FILTER, which degrades in one direction only.** A range whose LEAD-IN has aged out yields
    /// the part that survives, so a window a little short costs the address position at the head of a
    /// replay rather than the replay. A range whose END has aged out yields nothing at all — see
    /// `retainedDuration`, which is sized so that the second case takes a pathological delay to reach.
    ///
    /// **What leaves here is a retain, not a copy.** `Data` is refcounted, so the caller and the ring
    /// share these bytes, and a caller that keeps them keeps them alive through an eviction — or a
    /// shed. That is exactly why `onShed` exists.
    ///
    /// This answers with whatever is ENCODED, which since the encode moved off the capture queue
    /// is not necessarily everything that was captured. Ask `hasFrames(through:)` first if a
    /// complete range matters, which it does for the tail of a swing.
    func frames(from start: TimeInterval, to end: TimeInterval) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return samples.filter { $0.timestamp >= start && $0.timestamp <= end }.map(\.jpeg)
    }

    /// Whether the ring has caught up to `end` — the readiness a caller waits on before pulling
    /// a range, and the thing the capture screen's progress bar is reporting.
    ///
    /// The newest sample is the only question worth asking, and **that rests entirely on the
    /// relay's delivery barrier**: frames are ENCODED by two workers and may finish in either order,
    /// but they are DELIVERED in capture order, so a ring whose newest sample is at or past `end`
    /// holds everything up to `end` that it is ever going to hold. Take the barrier away and this
    /// method becomes a lie that shows up as a missing frame in the follow-through — the part of the
    /// swing the pull happens during.
    ///
    /// False after `stop()`, when the ring is dropped, and false after a critical memory-pressure
    /// shed for as long as the ring stays empty: a caller waiting on frames that cannot arrive is
    /// bounded by its own deadline in both cases.
    func hasFrames(through end: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let newest = samples.last?.timestamp else { return false }
        return newest >= end
    }

    /// The newest frame the ring holds, or nil while it is disarmed or still empty.
    ///
    /// Nil is not "show nothing". The ring is armed by `CameraService.startRecording()` and
    /// dropped by `stopRecording()`, and a spontaneous stop — interruption, disk full — drops
    /// it from the movie output's delegate one main-queue hop BEFORE the screen learns the
    /// take is over. The caller keeps drawing what it last decoded across that window rather
    /// than blinking to black for a frame or two.
    ///
    /// A `Data` is refcounted, so what leaves here is a retain, not a copy of the JPEG.
    func latest() -> LatestFrame? {
        lock.lock()
        defer { lock.unlock() }
        guard let sample = samples.last else { return nil }
        return LatestFrame(sequence: sequence, jpeg: sample.jpeg)
    }

    func coverage() -> Coverage {
        lock.lock()
        defer { lock.unlock() }
        return Coverage(
            count: samples.count,
            oldest: samples.first?.timestamp,
            newest: samples.last?.timestamp,
            bytes: heldBytes,
            sheds: sheds
        )
    }

    // MARK: - Encoding

    /// Renders and compresses the frame handed in. Relay-queue only, and the buffer is one of
    /// the relay's own — the capture callback that produced its bytes has already returned.
    /// Nothing derived from it survives this call.
    ///
    /// **NO ROTATION IS APPLIED HERE, AND THAT IS A DEPENDENCY RATHER THAN AN OVERSIGHT.**
    /// The buffer arrives upright already: `CameraService.rebuildCaptureRotation()` — the last
    /// thing `configureSession` does, and therefore always before `startRecording()` arms this
    /// ring — hands the video data output's connection to
    /// `CaptureRotationSubject.register(captureConnection:)`, which sets
    /// `videoRotationAngleForHorizonLevelCapture` on it, and AVFoundation rotates the
    /// delivered sample buffers to match. A landscape sensor therefore arrives portrait.
    /// `CameraService.rebuildPoseOverlayGeometry` states the same dependency from the other
    /// side, and every `VNImageRequestHandler` in `Services/Detection` leans on it too — none
    /// of them passes an orientation, so all of them assume `.up`.
    ///
    /// Stop registering that connection, or move the registration after the ring is armed, and
    /// every replay plays sideways on a full screen. The ring cannot repair that by itself: a
    /// connection reports only the angle it DID apply, never the angle it should have applied,
    /// so there is no residual to compute here and any correction would be a guess at the
    /// direction. It says so instead — see `reportIfLandscape`.
    ///
    /// Mirroring is NOT handled here either. The configurator forces this connection
    /// unmirrored and the surfaces flip by `poseOverlayGeometry.isMirrored` at draw time;
    /// baking a flip into the JPEG would double-apply it.
    ///
    /// **Reentrant, because two workers run it at once.** The only state it touches is the shared
    /// `CIContext`, which Apple documents as safe to use from several threads and whose lazy creation
    /// is behind `contextLock`. Everything else is a local.
    private func encode(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard max(image.extent.width, image.extent.height) > 0 else { return nil }
        return encodingContext().jpegRepresentation(
            of: fitted(image),
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [Self.qualityOption: Self.compressionQuality]
        )
    }

    /// The frame at the size the ring stores, which at `maximumEdge == 1920` is **the frame
    /// untouched**: the buffer the camera delivers is already 1080×1920, so there is no scale to
    /// apply and the guard below returns the image as it arrived.
    ///
    /// That is worth one paragraph, because the tempting version of this story is wrong. Removing the
    /// scale does NOT remove a pass — CoreImage folds an affine transform into the single render
    /// `jpegRepresentation` performs, so what a native output saves is `highQualityDownsample`'s
    /// extra filtering and NOTHING else, while the render's write, the readback and the JPEG all grow
    /// with the output. Native costs more per frame than 1280 did. `CapturedFrameRelay`'s second
    /// worker is what pays for it.
    ///
    /// **`highQualityDownsample` therefore only matters on the other branch** — a device that
    /// negotiates a format larger than `maximumEdge`, or a future step down to 960. There it is a
    /// quality decision and the most expensive token in this file: a reduction sampled the default
    /// way discards most of every source box, which aliases precisely the features a golfer is
    /// reading (the club shaft, the ball, the top of the arc) and makes them shimmer frame to frame in
    /// a loop. Passed per operation rather than as a context option
    /// (`CIContextOption.highQualityDownsample`) because it belongs to this one scale, and because the
    /// argument overrides the context — so the two must not both be set.
    private func fitted(_ image: CIImage) -> CIImage {
        let scale = Self.maximumEdge / max(image.extent.width, image.extent.height)
        guard scale < 1 else { return image }
        return image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale),
            highQualityDownsample: true
        )
    }

    /// `encode`, timed — the measurement `maximumEdge`'s doc asks the next person to take
    /// before moving it, taken by the app itself instead of by hand.
    ///
    /// Release builds compile straight through to `encode`, and a DEBUG build with the probe
    /// switched off (`DeviceProbe.isEnabled` reads `GSS_PROBE`, which is unset in normal use)
    /// pays one static bool read and not even a clock call. Written as a wrapper so the relay's
    /// `encode` handler stays one line and `encode` stays free of instrumentation.
    private func encodeMeasuringCost(_ pixelBuffer: CVPixelBuffer) -> Data? {
        #if DEBUG
        guard DeviceProbe.isEnabled else { return encode(pixelBuffer) }
        let started = ProcessInfo.processInfo.systemUptime
        let jpeg = encode(pixelBuffer)
        noteEncodeCost(seconds: ProcessInfo.processInfo.systemUptime - started, bytes: jpeg?.count ?? 0)
        return jpeg
        #else
        return encode(pixelBuffer)
        #endif
    }

    /// Colour management is left exactly as it was, deliberately. It is the one knob here that can
    /// change output PIXELS — `workingColorSpace: NSNull()` would save an unmeasured slice of an
    /// encode, at the risk of a gamma shift on the very surface this pass is repairing. The quality
    /// was bought with resolution instead, which can only make the picture more like the frame that
    /// arrived.
    ///
    /// **`cacheIntermediates: false` is a memory decision and the only addition.** A context keeps
    /// intermediate results so a repeated render can reuse them, which is worth nothing here — every
    /// frame is a new source buffer, so nothing is ever reused — and at 2.07M pixels a render, two
    /// workers deep, 15 times a second, it is worth a great deal to give back. Apple's own guidance
    /// for streaming a series of images says the same.
    private func encodingContext() -> CIContext {
        contextLock.lock()
        defer { contextLock.unlock() }
        if let context { return context }
        let created = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
        context = created
        return created
    }

    // MARK: - Encode Cost

    #if DEBUG
    /// One `ring_encode` line per window of 60 sampled frames — ~4s of a take at 15 fps — rather
    /// than one per frame: a probe write at 15/s would itself be a cost on the queue this exists to
    /// measure. Mean and worst case, because the worst case is what fills the relay's pool, plus the
    /// bytes that say what all of this is costing.
    ///
    /// **What to read, in order.** `worst_ms` against `budget_ms` — which is now one sampled frame
    /// period TIMES the worker count — says whether native resolution fits this device at all.
    /// `depth_max` and `dropped` say whether it fitted in practice: a depth of 1 means a frame never
    /// waited for a worker, 2–4 means both were busy and the pool's slack absorbed it, and any
    /// `dropped` means the slack ran out — turn `maximumEdge` down to 960 before anything else.
    /// `reorder_max` above 1 says the workers are finishing out of order, i.e. that the delivery
    /// barrier is doing real work rather than standing by. `held_kb` and `held_frames` are the ring's
    /// MEASURED footprint, and the pair is what says WHICH bound is deciding the window: ~90 frames
    /// means `retainedDuration` is, ~28MB means `maximumHeldBytes` is. `sheds` is the memory valve
    /// firing — a non-zero value there means this budget is wrong for the device, not merely tight.
    /// `slot_kb` is MEASURED (`CVPixelBufferGetDataSize`), so the pool's real cost is
    /// `slots × slot_kb` and not a figure reasoned from width × height.
    private func noteEncodeCost(seconds: TimeInterval, bytes: Int) {
        guard let window = costMeter.note(seconds: seconds, bytes: bytes) else { return }
        report(window)
    }

    /// Deliberately NOT under `lock`: `coverage()` and `takeLoad()` each take their own, and the
    /// probe write — which appends to a file — happens after both have been released.
    private func report(_ window: EncodeCostMeter.Window) {
        let load = relay.takeLoad()
        let ring = coverage()
        DeviceProbe.event("ring_encode", [
            "frames": String(window.frames),
            "mean_ms": String(format: "%.1f", window.meanMs),
            "worst_ms": String(format: "%.1f", window.worstMs),
            "mean_kb": String(format: "%.0f", window.meanBytes / 1024),
            "edge_px": String(format: "%.0f", Double(Self.maximumEdge)),
            // One sampled frame period per WORKER: the frames arrive every 66.7ms and there are
            // `workers` encoding at once, so that is how long one frame has before the pool
            // backs up.
            "budget_ms": String(format: "%.1f", Double(load.workers) * 1000 / Double(Self.sampledFrameRate)),
            "workers": String(load.workers),
            "depth_max": String(load.peakDepth),
            "reorder_max": String(load.peakReorder),
            "dropped": String(load.dropped),
            "slots": String(load.slots),
            "slot_kb": String(load.slotBytes / 1024),
            "held_frames": String(ring.count),
            "held_kb": String(ring.bytes / 1024),
            "sheds": String(ring.sheds)
        ])
    }

    private let costMeter = EncodeCostMeter(interval: 60)
    #endif
}

// MARK: - Encode Cost Meter

#if DEBUG
/// What the encode costs, accumulated across the relay's workers and handed over once a window
/// closes.
///
/// Its own type with its own lock, and both are the second worker's doing: this is the one piece of
/// state on the encode path that several threads now write at once, and it has no business queueing
/// behind the ring's lock — a probe that contended with `append` would be measuring itself. Split
/// out rather than inlined so `SwingFrameBuffer` keeps one lock with one meaning.
private nonisolated final class EncodeCostMeter: @unchecked Sendable {

    /// One report's worth. Bytes as a `Double` because it is a mean, and reporting a mean as an
    /// integer count of bytes invites it to be read as a measurement of one frame.
    struct Window {
        let frames: Int
        let meanMs: Double
        let worstMs: Double
        let meanBytes: Double
    }

    private let interval: Int
    private let lock = NSLock()
    private var frames = 0
    private var totalMs = 0.0
    private var worstMs = 0.0
    private var totalBytes = 0

    init(interval: Int) {
        self.interval = interval
    }

    /// The closed window, or nil while it is still filling. Resets itself when it answers, so
    /// consecutive reports describe consecutive windows rather than the whole take flattened.
    func note(seconds: TimeInterval, bytes: Int) -> Window? {
        lock.lock()
        defer { lock.unlock() }
        frames += 1
        totalMs += seconds * 1000
        worstMs = max(worstMs, seconds * 1000)
        totalBytes += bytes
        guard frames >= interval else { return nil }
        let window = Window(
            frames: frames,
            meanMs: totalMs / Double(frames),
            worstMs: worstMs,
            meanBytes: Double(totalBytes) / Double(frames)
        )
        reset()
        return window
    }

    /// Lock held.
    private func reset() {
        frames = 0
        totalMs = 0
        worstMs = 0
        totalBytes = 0
    }
}
#endif
