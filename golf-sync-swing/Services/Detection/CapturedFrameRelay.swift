//
//  CapturedFrameRelay.swift
//  golf-sync-swing
//
//  Gets work off the capture queue without ever retaining a capture buffer.
//
//  THE RULE THIS EXISTS TO KEEP
//  ---------------------------
//  A `CVPixelBuffer` delivered to `captureOutput` belongs to the capture pool and MUST be
//  released with the callback: holding one starves that pool and collapses the pipeline. That
//  rule is why `SwingFrameBuffer` used to scale and JPEG-encode INLINE on the video queue —
//  which capped the replay's resolution at whatever fitted inside one frame period, because
//  `alwaysDiscardsLateVideoFrames` turns an overrunning callback into a DROPPED frame, and a
//  dropped frame is one the detector wanted.
//
//  This breaks the choice. The capture callback copies the frame's bytes into a buffer THE APP
//  owns — a `memcpy` of a couple of planes, sub-millisecond (estimate) — and returns. The scale
//  and the encode then happen on this relay's own queue, where they cost the detector
//  nothing. The source buffer is read and released inside `submit`; nothing derived from it
//  outlives the callback.
//
//  WHAT MAKES IT SAFE TO OWN BUFFERS
//  ---------------------------------
//  Bounded — in slots AND in bytes, because a slot's size is the source geometry and nothing in
//  this app caps that (`capacity`, `maximumPoolBytes`). And it degrades by DROPPING: when the
//  encoder falls behind, the oldest PENDING frame's buffer is taken back for the incoming frame
//  and that frame is lost. It never grows, and it never blocks the capture queue — a queue that
//  waits is a dropped frame by another name.
//
//  WORK IN PARALLEL, RESULTS IN ORDER
//  ----------------------------------
//  Up to `workers` frames are encoded AT ONCE, because one queue no longer holds the sampled-frame
//  period: the ring stores frames at the camera's own resolution now, which is ~2.25x the pixels
//  the two-thirds downscale used to produce. Concurrency is the answer the owner wanted — dropping
//  frames or sampling fewer of them would cost the replay the frame rate that makes a 0.25s
//  downswing legible at all.
//
//  What concurrency threatens is ORDER, and the ring depends on it completely: it is pulled as a
//  time RANGE, and its readiness test — "the newest frame is at or past the end of the swing,
//  therefore everything before it is here" — is only true if frames arrive in the order they were
//  captured. So this type separates the two jobs. `encode` runs on any worker, whenever a frame is
//  ready for it. `deliver` is called ONE AT A TIME, in submission order, from a barrier that holds
//  a finished frame back until every earlier frame has been delivered or accounted for. Every order
//  issued leaves through exactly one of three doors — delivered, abandoned (displaced from the pool,
//  or an encode that failed), or retired wholesale by `reset` — which is what keeps the barrier from
//  stalling on a frame that is never coming.
//
//  At `workers == 1` the barrier is trivially satisfied on every frame and this is exactly the
//  serial relay it replaced. That is deliberate: it makes the constant a rollback.
//
//  `nonisolated` + `NSLock`, matching `SwingFrameBuffer` and the rest of the capture path: the
//  target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and an implicitly
//  `@MainActor` type would be unreachable from the video queue — the only place frames exist.
//

// Explicit, module by module: the target builds with
// `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`, so re-exports do not count.
import CoreVideo
import Dispatch
import Foundation
// Required for `Logger`'s string interpolation, same as `SwingFrameBuffer`.
import os

nonisolated final class CapturedFrameRelay: @unchecked Sendable {

    /// One copied frame, handed to `encode` on one of the relay's workers. The buffer is the app's
    /// own and is valid for the duration of that call only — it goes back into the pool the moment
    /// the call returns, so anything the handler wants to keep it must copy or encode by then.
    struct Frame {
        let pixelBuffer: CVPixelBuffer
        /// The take the frame belongs to, so a handler can discard one that outlived its take.
        let generation: UInt64
        /// Recording-relative, exactly as the submitter stamped it.
        let timestamp: TimeInterval
    }

    /// What `encode` made of a frame, handed to `deliver` in submission order. It carries the
    /// frame's identity forward and nothing else — the buffer it came from went back into the pool
    /// before this was published.
    struct Encoded {
        let data: Data
        let generation: UInt64
        let timestamp: TimeInterval
    }

    /// What the relay has been doing since this was last read. Diagnostics only, and the whole
    /// answer to "did the encoder keep up on device": a peak depth of 1 means it never fell
    /// behind, and a non-zero `dropped` is the encoder losing frames the ring wanted.
    struct Load {
        let peakDepth: Int
        let dropped: Int
        let slots: Int
        /// `CVPixelBufferGetDataSize` of the first slot allocated — MEASURED, not reasoned from
        /// width × height, because a 1080-wide plane is padded to a wider `bytesPerRow` and the
        /// pool's real cost is the padded figure.
        let slotBytes: Int
        let workers: Int
        /// The most frames ever waiting their TURN rather than waiting for a worker — finished, but
        /// held behind an earlier frame still being encoded. **One is the floor**, since a frame that
        /// finishes in order is filed and delivered without ever queueing; 2 or more is a worker
        /// having finished ahead of an earlier frame, and therefore the barrier doing real work
        /// rather than standing by.
        let peakReorder: Int
    }

    // MARK: - Configuration

    /// Slots. **Half of the memory bound and not the whole of it** — the other half is
    /// `maximumPoolBytes`, because what a slot COSTS is decided by the source geometry rather than
    /// here.
    ///
    /// Four is `defaultWorkers` being encoded plus two waiting. Raised from three with the workers,
    /// and by exactly that much: a slot held by a worker is not slack, so three slots and two
    /// workers would leave a single frame of buffering. Two waiting is ~133ms of slack at the 15fps
    /// `SwingFrameBuffer` samples — enough to absorb a thermal spike or a GPU stall without losing a
    /// frame. Each further slot buys another frame period of slack for another ~3.1MB, and each
    /// frame lost costs the replay a frame rather than the detector anything.
    ///
    /// At 1080x1920 4:2:0 that is 4 × ~3.1MB ≈ 12.5MB (ESTIMATED from the plane arithmetic;
    /// `Load.slotBytes` MEASURES it), and at that geometry this count is what binds.
    static let defaultCapacity = 4

    /// The pool's other bound, and the one a slot COUNT cannot express: a slot is allocated at the
    /// SOURCE geometry, and nothing in this app caps that. `SwingFrameBuffer.maximumEdge` caps the
    /// ring's OUTPUT only — so a configurator that ever targeted 4K, or a device that negotiated it,
    /// would silently hand this pool four ~12.4MB slots (ESTIMATED from the plane arithmetic): ~50MB
    /// held beside a movie file being written, for a replay nobody asked to be sharper. The same
    /// asymmetry `SwingFrameBuffer.maximumHeldBytes` was added to close for the ring.
    ///
    /// 16MB, which is the nominal 1080p pool with room for the padding `bytesPerRow` adds. At 1080p
    /// the SLOT COUNT still binds and nothing changes; this begins to bind only above ~4MB a slot,
    /// i.e. only above the geometry the configurator asks for. At 4K it allows one slot, and the
    /// pipeline then degrades exactly the way it already degrades when the encoder falls behind — the
    /// ring loses frames, the capture queue never waits, and the detector pays nothing.
    ///
    /// Tested against MEASURED bytes, never against width × height: `slotBytes` is
    /// `CVPixelBufferGetDataSize` of the first slot actually allocated. The first slot is therefore
    /// always allowed — there is no way to learn what a slot costs on this device without allocating
    /// one, and refusing it would mean no replay at all.
    static let maximumPoolBytes = 16 * 1024 * 1024

    /// How many frames may be encoded AT ONCE, and the first constant to turn if a device run says
    /// the concurrency misbehaves: **at 1 this type is the serial relay it replaced**, because
    /// completion order is then submission order and the barrier never holds anything. Nothing else
    /// has to change to roll back.
    ///
    /// Two because the encode is no longer a two-thirds downscale. At the ring's native output it is
    /// ~2.25x the pixels — ESTIMATED ~36–65ms per frame on the A17 this is tested on and ~60–110ms
    /// on the A13-class device the iOS 26 floor still admits, against a 66.7ms sampled-frame period.
    /// One queue holds that on the newest hardware and not on the oldest, and what a device that
    /// misses the period loses is replay FRAMES: an 80ms encode against a 66.7ms arrival drops
    /// ~17% of them (ESTIMATED, `1 - 66.7/80`), which reads as a stutter in the one part of the
    /// swing anybody watches. Two workers put the budget at 133ms, which covers the oldest
    /// supported device's estimate with room.
    ///
    /// Deliberately NOT `activeProcessorCount`: the detector's Vision pass owns a core for 100–300ms
    /// at a time and the movie file output's encoder owns another, so a relay that scaled with the
    /// chip would compete hardest with both on exactly the devices that have least to spare.
    static let defaultWorkers = 2

    // MARK: - Collaborators

    /// Turns a copied frame into the bytes the owner keeps. **Runs on any worker, and up to
    /// `workers` calls may be in flight at once, so it must be reentrant** — `SwingFrameBuffer`'s
    /// is, because the only state it touches is a `CIContext` (documented thread-safe) behind its
    /// own lock. Returning nil abandons the frame, which advances the barrier rather than stalling
    /// it.
    ///
    /// Written ONCE, by the owner, before the relay can be reached from a capture callback — which
    /// is what makes both of these safe without a lock. Not injected through `init` only because
    /// the owner is the handler: `SwingFrameBuffer` builds the relay and then hands it methods of
    /// its own.
    var encode: ((Frame) -> Data?)?

    /// Where an encoded frame goes. **Called on the relay's queue, one at a time, in the order the
    /// frames were submitted** — the guarantee the whole barrier exists to make, and the one the
    /// ring's readiness test depends on.
    var deliver: ((Encoded) -> Void)?

    /// What a copy IS. Stateless, and the reason this class is about WHEN to copy and nothing
    /// else.
    private let copier = PixelBufferCopier()

    // MARK: - State

    private let lock = NSLock()
    private let capacity: Int
    private let workers: Int

    /// `.userInitiated`, and deliberately NOT `.utility`.
    ///
    /// Lower than the video queue's `.userInteractive`, so the detector still preempts every
    /// encode — that ordering is the point of moving the work here. But `.utility` invites the
    /// scheduler to run it on an efficiency core, where an encode that fits its frame period
    /// comfortably on a performance core may not, and an encoder that misses the period drops
    /// frames — undoing the quality this whole change buys. `CameraService.sessionQueue` makes
    /// the same call for the same reason: work the user is actively waiting on is
    /// `.userInitiated`, and a golfer watching a progress bar is waiting on this.
    ///
    /// `autoreleaseFrequency: .workItem` because CoreImage and ImageIO autorelease heavily; on
    /// the default (inherited) pool nothing would drain until the queue went idle, which reads
    /// as "memory climbs through a take".
    ///
    /// `.concurrent` now, and it is `activeWorkers` — not the queue — that bounds how many encodes
    /// run at once. A queue with a width is not the same thing as a queue that hands out work: the
    /// count has to be visible under the lock anyway, because that is where a frame arriving
    /// decides whether anyone is free to take it.
    private let queue: DispatchQueue

    private var free: [CVPixelBuffer] = []
    private var pending: [Slot] = []
    private var allocated = 0
    private var geometry: Geometry?

    /// How many workers are alive. Each takes frames until none are waiting and then retires, so
    /// this is between 0 and `workers` and never a thread parked on an empty queue.
    private var activeWorkers = 0

    /// A frame's place in line, stamped at checkout and **monotonic for the life of the process**.
    /// Deliberately not reset by `discard()`: a worker that finishes across a discard must not be
    /// able to collide with a fresh frame's place, and `reset` retires everything outstanding by
    /// moving the barrier instead.
    private var nextOrder: UInt64 = 0

    /// The barrier. The order that must be delivered before anything after it can be.
    private var deliveryOrder: UInt64 = 0

    /// Finished out of turn, waiting for the barrier to reach them. Bounded by `workers` in
    /// practice — a frame can only be early by the number of frames being encoded beside it.
    private var ready: [UInt64: Encoded] = [:]

    /// Orders that will never be delivered and must therefore be STEPPED OVER: a pending frame
    /// displaced from the pool, or an encode that returned nil. Without this the barrier would wait
    /// on them forever and the ring would never see another frame.
    private var abandoned: Set<UInt64> = []

    /// Whether a delivery loop is already draining the barrier. One at a time is what makes
    /// `deliver` serial.
    private var isDelivering = false

    /// Bumped by `discard()`. A slot checked out before a discard carries the OLD number, so
    /// when the handler finishes with it the buffer is released instead of being returned to a
    /// pool that no longer wants it.
    private var poolGeneration: UInt64 = 0

    private var peakDepth = 0
    private var droppedFrames = 0
    private var slotBytes = 0
    private var peakReorder = 0

    /// What a pooled buffer has to match. A camera flip re-negotiates the format, and a pool of
    /// the previous geometry's buffers would copy garbage — so a mismatch rebuilds instead.
    private struct Geometry: Equatable {
        let width: Int
        let height: Int
        let format: OSType

        init(width: Int, height: Int, format: OSType) {
            self.width = width
            self.height = height
            self.format = format
        }

        init(_ pixelBuffer: CVPixelBuffer) {
            width = CVPixelBufferGetWidth(pixelBuffer)
            height = CVPixelBufferGetHeight(pixelBuffer)
            format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        }
    }

    /// A checked-out buffer and the frame it is carrying. `poolGeneration` and `order` never leave
    /// this type — the handler is given a `Frame`, which has no business knowing about the pool or
    /// about the queue it waited in.
    private struct Slot {
        let pixelBuffer: CVPixelBuffer
        let poolGeneration: UInt64
        let order: UInt64
        let generation: UInt64
        let timestamp: TimeInterval
    }

    // MARK: - Init

    init(
        capacity: Int = CapturedFrameRelay.defaultCapacity,
        workers: Int = CapturedFrameRelay.defaultWorkers,
        label: String
    ) {
        self.capacity = max(1, capacity)
        // Never more workers than slots: a worker without a slot to hold could only wait, and
        // nothing here is allowed to wait.
        self.workers = max(1, min(workers, self.capacity))
        queue = DispatchQueue(
            label: label,
            qos: .userInitiated,
            attributes: .concurrent,
            autoreleaseFrequency: .workItem
        )
    }

    // MARK: - Capture Path

    /// The capture queue, inside `captureOutput` — and `pushWarmUpFrame`, which is the only other
    /// caller and runs on this relay's own queue. Everything below it is lock-guarded, so the queue
    /// matters for COST rather than for safety: this is the work a capture callback pays.
    ///
    /// Copies and returns; `source` is borrowed for the duration of this call and is never retained.
    ///
    /// Silent when there is no slot free — that is the drop, and `takeLoad()` is where it is
    /// reported. Nothing here waits for the encoder.
    func submit(_ source: CVPixelBuffer, generation: UInt64, timestamp: TimeInterval) {
        guard let slot = checkout(source, generation: generation, timestamp: timestamp) else { return }
        guard copier.copy(source, into: slot.pixelBuffer) else {
            recycle(slot)
            // The order was issued and now belongs to nothing, so the barrier is told to step over
            // it. No delivery is kicked from here: the next frame to finish drains the barrier
            // anyway, and this runs on the capture queue, which is the one place `deliver` must
            // never be called from.
            abandon(slot.order)
            return
        }
        enqueue(slot)
    }

    /// Pushes ONE throwaway frame through the whole path — allocation, copy, queue, handler — so
    /// that a take's first real frames do not pay for what only has to happen once.
    ///
    /// The handler is where the cost is. `SwingFrameBuffer`'s encode builds a `CIContext` on first
    /// use (a Metal device and compiled shaders, by that file's own account too expensive to put
    /// on app launch) and then specializes the JPEG kernels for the encode's output size. At 15
    /// sampled frames a second the pool fills in ~266ms, so those milliseconds would be spent
    /// DROPPING pending frames — and `ring_encode`'s `dropped` is supposed to mean "this
    /// resolution is too much for this device", not "the first take started". One frame is enough
    /// however many workers there are: the context they share is built by whichever runs first.
    ///
    /// **The hop is the whole body, and it is not tidiness.** The caller is
    /// `RecordingViewModel.startRecording()` — the main actor, on the tap this app has already lost a
    /// cold start to. What the body does is allocate a ~3.1MB IOSurface-backed buffer and `memcpy`
    /// ~3.1MB into another (MEASURED as `Load.slotBytes`), and nothing reads the result, so there is
    /// nothing for the caller to wait for. Fire-and-forget work has no business on the actor that
    /// draws the countdown.
    func warmUp(width: Int, height: Int, format: OSType) {
        let geometry = Geometry(width: width, height: height, format: format)
        queue.async { [weak self] in self?.pushWarmUpFrame(geometry) }
    }

    /// Relay-queue only. The frame goes nowhere: nothing is collecting when this is called. Costs two
    /// transient buffers of the given size, both released as soon as the handler returns —
    /// `discard()` is what gives the pool slot back, and it deliberately leaves the warmed context
    /// alone.
    private func pushWarmUpFrame(_ geometry: Geometry) {
        guard let source = allocate(geometry) else { return }
        submit(source, generation: 0, timestamp: 0)
    }

    /// Drops everything waiting, frees the pool and retires the delivery barrier, so an idle app
    /// holds none of this. Called wherever a take begins or ends: a frame still queued across a stop
    /// belongs to the take that is over.
    func discard() {
        lock.lock()
        defer { lock.unlock() }
        reset(to: geometry)
    }

    /// Peak depth, drops and reorder depth SINCE THE LAST READ, then zeroed — so consecutive
    /// reports describe consecutive windows rather than the whole take flattened.
    func takeLoad() -> Load {
        lock.lock()
        defer { lock.unlock() }
        let load = Load(
            peakDepth: peakDepth,
            dropped: droppedFrames,
            slots: allocated,
            slotBytes: slotBytes,
            workers: workers,
            peakReorder: peakReorder
        )
        peakDepth = 0
        droppedFrames = 0
        peakReorder = 0
        return load
    }

    // MARK: - Pool

    private func checkout(_ source: CVPixelBuffer, generation: UInt64, timestamp: TimeInterval) -> Slot? {
        let wanted = Geometry(source)
        lock.lock()
        defer { lock.unlock() }
        if geometry != wanted { reset(to: wanted) }
        guard let buffer = takeBuffer(matching: wanted) else { return nil }
        let order = nextOrder
        nextOrder &+= 1
        return Slot(
            pixelBuffer: buffer,
            poolGeneration: poolGeneration,
            order: order,
            generation: generation,
            timestamp: timestamp
        )
    }

    /// Lock held. Free list first, then a fresh allocation while BOTH bounds allow one, and only then
    /// the oldest PENDING frame — which is the degradation this type promises: the ring loses its
    /// stalest unencoded frame, memory does not grow, and the capture queue does not wait.
    ///
    /// A displaced frame's order is abandoned here, under the lock that removed it, so the two can
    /// never disagree. The barrier is not kicked: a displacement happens because a NEWER frame
    /// needed the slot, and that frame's completion drains the barrier past this one.
    ///
    /// `droppedFrames` counts BOTH ways a frame is lost, and the counter's meaning is unchanged by
    /// that: one increment, one frame gone, whether it was the pending frame displaced from its slot
    /// or the incoming frame that found no slot at all. The second path is unreachable at 1080p — two
    /// workers can hold at most two of four slots, so `free` and `pending` cannot both be empty — and
    /// exists for the geometry where `maximumPoolBytes` refuses a slot the count would have allowed.
    private func takeBuffer(matching geometry: Geometry) -> CVPixelBuffer? {
        if let buffer = free.popLast() { return buffer }
        if allocated < capacity, affordsAnotherSlot(), let buffer = allocate(geometry) {
            allocated += 1
            if slotBytes == 0 { slotBytes = CVPixelBufferGetDataSize(buffer) }
            return buffer
        }
        droppedFrames += 1
        guard !pending.isEmpty else { return nil }
        let displaced = pending.removeFirst()
        abandoned.insert(displaced.order)
        return displaced.pixelBuffer
    }

    /// Lock held. Whether one more slot fits under `maximumPoolBytes`, on the strength of what the
    /// slots already allocated MEASURED. True by construction for the first slot: `slotBytes` is zero
    /// until one exists, and a pool that never allocated a slot could never report its size.
    ///
    /// Every slot shares one geometry — `checkout` rebuilds the pool when it changes — so one measured
    /// figure describes all of them.
    private func affordsAnotherSlot() -> Bool {
        guard slotBytes > 0 else { return true }
        return (allocated + 1) * slotBytes <= Self.maximumPoolBytes
    }

    /// IOSurface- and Metal-backed, because CoreImage renders these on the GPU: a plain
    /// malloc'd buffer would make `CIImage(cvPixelBuffer:)` stage a copy of its own on the
    /// encode queue, paying twice for the copy this design exists to make cheap.
    private func allocate(_ geometry: Geometry) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            geometry.width,
            geometry.height,
            geometry.format,
            attributes as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess else {
            AppLogger.camera.error("CapturedFrameRelay: could not allocate a \(geometry.width)x\(geometry.height) slot (status \(status)) — this take's replay will lose frames")
            return nil
        }
        return buffer
    }

    /// Lock held. Everything waiting is abandoned and every buffer released; a slot a worker is
    /// still holding is dropped by `recycle` when it comes back, on the strength of the generation
    /// it carries.
    private func reset(to geometry: Geometry?) {
        pending.removeAll()
        free.removeAll()
        allocated = 0
        // Re-measured with the next allocation rather than carried over: the reason this runs at
        // all may be that the geometry changed, and a stale figure would misreport the pool.
        slotBytes = 0
        poolGeneration &+= 1
        // THE BARRIER GOES WITH THE POOL, and this is the line that keeps a discard from stalling
        // delivery forever. Every order still outstanding — waiting in `pending`, being encoded by a
        // worker, or already finished and held back in `ready` — is retired at once by moving the
        // barrier to the next order that will be issued. Without it, `deliveryOrder` would sit
        // waiting on a frame this call just threw away while `nextOrder` climbed past it, and every
        // later replay would wait out its deadline and pull a partial range.
        ready.removeAll()
        abandoned.removeAll()
        deliveryOrder = nextOrder
        self.geometry = geometry
    }

    private func recycle(_ slot: Slot) {
        lock.lock()
        defer { lock.unlock() }
        // Not a decrement of `allocated`: `reset` already zeroed it, and this buffer is simply
        // released here.
        guard slot.poolGeneration == poolGeneration else { return }
        free.append(slot.pixelBuffer)
    }

    // MARK: - Workers

    private func enqueue(_ slot: Slot) {
        lock.lock()
        pending.append(slot)
        peakDepth = max(peakDepth, pending.count)
        let shouldHire = activeWorkers < workers
        if shouldHire { activeWorkers += 1 }
        lock.unlock()
        guard shouldHire else { return }
        // The `Frame` is built inside `work`, on the relay's queue, so no buffer is ever captured
        // across this boundary.
        queue.async { [weak self] in self?.work() }
    }

    /// One worker's whole life: take the oldest frame waiting, encode it, give the slot back, and
    /// publish the result — then again, until nothing is waiting. Up to `workers` of these run at
    /// once, which is the entire reason `encode` has to be reentrant.
    ///
    /// The slot is recycled BEFORE the result is published, so a buffer is never held across the
    /// barrier: a frame waiting its turn costs a few hundred KB of JPEG, not 3.1MB of pool.
    private func work() {
        while let slot = nextSlot() {
            let frame = Frame(
                pixelBuffer: slot.pixelBuffer,
                generation: slot.generation,
                timestamp: slot.timestamp
            )
            let encoded = encode?(frame)
            recycle(slot)
            publish(encoded, of: slot)
        }
    }

    /// Oldest first, and it is this method that retires a worker: the FIFO going empty and
    /// `activeWorkers` dropping happen under one lock, so a frame submitted at that instant either
    /// finds a worker still running or hires one, never neither.
    private func nextSlot() -> Slot? {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else {
            activeWorkers -= 1
            return nil
        }
        return pending.removeFirst()
    }

    // MARK: - Delivery Barrier

    /// Files a finished frame under its place in line and opens a delivery loop if nobody else is
    /// already draining one.
    ///
    /// The claim and the filing happen under ONE lock, which is what makes a lost wake-up
    /// impossible: a loop that stalls clears `isDelivering` under that same lock, so a frame stored
    /// after it either finds the flag down and claims it, or was stored before the stall and is
    /// found by the loop.
    private func publish(_ data: Data?, of slot: Slot) {
        lock.lock()
        file(data, of: slot)
        let shouldDeliver = !isDelivering
        if shouldDeliver { isDelivering = true }
        lock.unlock()
        guard shouldDeliver else { return }
        queue.async { [weak self] in self?.deliverInOrder() }
    }

    /// Lock held. A slot from a retired pool generation is dropped rather than filed — `reset` moved
    /// the barrier past its order, so nothing would ever deliver it and it would sit in `ready`
    /// until the next discard. Same test `recycle` makes on the buffer, for the same reason.
    private func file(_ data: Data?, of slot: Slot) {
        guard slot.poolGeneration == poolGeneration else { return }
        guard let data else {
            abandoned.insert(slot.order)
            return
        }
        ready[slot.order] = Encoded(data: data, generation: slot.generation, timestamp: slot.timestamp)
        peakReorder = max(peakReorder, ready.count)
    }

    /// Relay-queue only, and one at a time by `isDelivering`: this is where the promise that
    /// `deliver` sees frames in submission order is kept.
    private func deliverInOrder() {
        while let encoded = nextDeliverable() { deliver?(encoded) }
    }

    /// The barrier's one step. Three outcomes, and the loop only stops on the third: the frame at
    /// the barrier is here and is delivered; the frame at the barrier is one that will never come
    /// and is stepped over; or an earlier frame is still being encoded, in which case delivery
    /// closes and whichever worker finishes it will re-open it.
    private func nextDeliverable() -> Encoded? {
        lock.lock()
        defer { lock.unlock() }
        while true {
            if let encoded = ready.removeValue(forKey: deliveryOrder) {
                deliveryOrder &+= 1
                return encoded
            }
            guard abandoned.remove(deliveryOrder) != nil else {
                isDelivering = false
                return nil
            }
            deliveryOrder &+= 1
        }
    }

    /// An order that was issued and will never be delivered. Called from the capture queue, so it
    /// does no more than record the fact.
    private func abandon(_ order: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        abandoned.insert(order)
    }

}

// MARK: - Pixel Buffer Copier

/// Moves one pixel buffer's bytes into another of the same geometry, and knows nothing about
/// pools, queues or takes. Stateless, and split out from the relay because "what a copy IS" and
/// "when a copy is worth making" are two jobs.
/// `nonisolated` for the same reason the relay is: with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
/// even this type's synthesized initializer would be main-actor isolated, and it is built and used
/// from the capture queue.
private nonisolated struct PixelBufferCopier {

    /// Both buffers locked for exactly as long as the bytes move.
    ///
    /// A partial copy is possible if a plane refuses its base address, and it is reported rather
    /// than enqueued — the relay recycles the slot and the frame is simply missing from the ring,
    /// which is the same outcome as a drop.
    func copy(_ source: CVPixelBuffer, into destination: CVPixelBuffer) -> Bool {
        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }
        copyAttachments(from: source, to: destination)
        let planes = CVPixelBufferGetPlaneCount(source)
        guard planes > 0 else { return copyFlat(source, into: destination) }
        return (0..<planes).allSatisfy { copyPlane($0, from: source, to: destination) }
    }

    /// **The colour tags travel with the pixels, or the replay changes colour.** The configurator
    /// asks for full-range bi-planar YCbCr, and what makes that decodable is the buffer's
    /// attachments — `CVImageBufferYCbCrMatrix`, `ColorPrimaries`, `TransferFunction`.
    /// `CIImage(cvPixelBuffer:)` reads them off the buffer it is handed; a copy that dropped
    /// them would have CoreImage guess the matrix, and the replay would come out with a
    /// different cast from the preview beside it.
    ///
    /// `CVBufferCopyAttachments` rather than the `Get` spelling, which is deprecated from iOS 15
    /// and would warn.
    func copyAttachments(from source: CVPixelBuffer, to destination: CVPixelBuffer) {
        guard let attachments = CVBufferCopyAttachments(source, .shouldPropagate) else { return }
        CVBufferSetAttachments(destination, attachments, .shouldPropagate)
    }

    func copyPlane(_ index: Int, from source: CVPixelBuffer, to destination: CVPixelBuffer) -> Bool {
        guard let sourceBase = CVPixelBufferGetBaseAddressOfPlane(source, index),
              let destinationBase = CVPixelBufferGetBaseAddressOfPlane(destination, index) else { return false }
        copyRows(
            from: sourceBase,
            stride: CVPixelBufferGetBytesPerRowOfPlane(source, index),
            to: destinationBase,
            stride: CVPixelBufferGetBytesPerRowOfPlane(destination, index),
            height: min(
                CVPixelBufferGetHeightOfPlane(source, index),
                CVPixelBufferGetHeightOfPlane(destination, index)
            )
        )
        return true
    }

    /// For a format with no planes at all (BGRA, say). Not the one the configurator asks for
    /// today, and here so that a change of `videoSettings` degrades to a slower copy rather
    /// than to a blank replay.
    func copyFlat(_ source: CVPixelBuffer, into destination: CVPixelBuffer) -> Bool {
        guard let sourceBase = CVPixelBufferGetBaseAddress(source),
              let destinationBase = CVPixelBufferGetBaseAddress(destination) else { return false }
        copyRows(
            from: sourceBase,
            stride: CVPixelBufferGetBytesPerRow(source),
            to: destinationBase,
            stride: CVPixelBufferGetBytesPerRow(destination),
            height: min(CVPixelBufferGetHeight(source), CVPixelBufferGetHeight(destination))
        )
        return true
    }

    /// ONE `memcpy` per plane whenever the strides agree, which they do when both buffers hold
    /// the same format at the same size — the whole reason the pool matches geometry. The row
    /// loop is the fallback for a destination the system padded differently.
    func copyRows(
        from source: UnsafeMutableRawPointer,
        stride sourceStride: Int,
        to destination: UnsafeMutableRawPointer,
        stride destinationStride: Int,
        height: Int
    ) {
        guard sourceStride == destinationStride else {
            copyRowByRow(from: source, stride: sourceStride, to: destination, stride: destinationStride, height: height)
            return
        }
        memcpy(destination, source, sourceStride * height)
    }

    func copyRowByRow(
        from source: UnsafeMutableRawPointer,
        stride sourceStride: Int,
        to destination: UnsafeMutableRawPointer,
        stride destinationStride: Int,
        height: Int
    ) {
        let bytes = min(sourceStride, destinationStride)
        for row in 0..<height {
            memcpy(destination + row * destinationStride, source + row * sourceStride, bytes)
        }
    }
}
