//
//  SwingReplayPlayerView.swift
//  golf-sync-swing
//
//  The looping replay itself, at whatever size it is handed. One implementation, two
//  presentations: the 120×160 picture-in-picture tile, and the full-screen cover that draws
//  over the live preview when the swing is on the main surface. Nothing here knows which of
//  the two it is in — it fills the space it is given and lets its parent decide the space.
//
//  What this must never become:
//    * a second camera preview. The old tile mounted its own `AVCaptureVideoPreviewLayer`,
//      which showed the same picture as the screen behind it AND blacked out the main preview
//      by adding a second connection to the running session.
//    * an `AVPlayer` on the recording file. Opening the in-progress .mov makes iOS terminate
//      the capture.
//
//  So it draws images, and nothing else.
//
//  WHETHER IT HOLDS THEM ALL IS A BUDGET, NOT A HABIT
//  --------------------------------------------------
//  It used to decode the whole clip into `[UIImage]` before the first tick, which at the 1920px
//  the ring stores now would be ~315MB of bitmaps on top of a live capture session. Then it held
//  two frames and re-decoded everything else — which, in a LOOP that never ends, is a
//  full-resolution decode 15 times a second for the rest of the take.
//
//  Neither is a policy. `cacheCapacity(forClipOf:at:)` reads the clip against a stated byte
//  budget and answers with one of exactly two numbers: the whole clip, or the playhead plus its
//  lookahead. In the 120x160 tile the whole clip fits, so it is decoded once and the loop then
//  costs nothing at all. On the full screen it does not fit at any budget this app could hold, so
//  one frame is decoded per tick — and that decode is now a single allocation rather than two
//  (`RingFrameDecoder.decoded`).
//
//  AND IT DECODES AT THE SIZE IT IS DRAWN AT
//  -----------------------------------------
//  A decoded 1080x1920 bitmap is 8.3MB, so "one implementation, two presentations" stopped being
//  free the moment the ring went native: in the 120x160 tile this view was spending a full-frame
//  bitmap to fill 360x480 device pixels. It now measures its own box and asks `RingFrameDecoder`
//  for that many pixels — 1/16 of the bytes in the tile, unchanged on the full screen. The size is
//  part of the playback identity, so a surface that changes size re-decodes rather than drawing
//  bitmaps sized for the box it used to be in.
//
//  IT ALSO DRAWS THE WAIT
//  ----------------------
//  A swing reaches this view before its own frames do. The clip runs to `impact + 1.0` and
//  detection reports it a few frames past impact, so ~1s of the swing has not been captured yet
//  when the golfer is told it was found — `RecordingViewModel` has always slept that out, and it
//  now hands the wait over as `SwingReplay.loading` instead of showing nothing. The surface goes
//  black and a white bar fills across it, in real time, off the wait's known length.
//
//  The bar is the reason this view has two states and not three. `frames.isEmpty` IS the loading
//  state; there is no separate flag to keep in step with it.
//

// Explicit, module by module, matching `SwingFrameBuffer`: the target enables
// MemberImportVisibility, so a re-export does not make `String(localized:comment:)` — a
// Foundation extension member — visible here.
import Foundation
import SwiftUI
import UIKit

struct SwingReplayPlayerView: View {
    let replay: SwingReplay

    /// Whether the live preview shows the analysed buffer mirrored — the same parity the
    /// skeleton overlay flips by. These frames come from the video-data output, which the
    /// configurator forces unmirrored, while the front camera's preview auto-mirrors; without
    /// this the replay would play the swing back the wrong way round.
    let isMirrored: Bool

    /// Points to device pixels, for the decode size. Read from the environment rather than from
    /// `UIScreen`, which is per-window and which SwiftUI does not promise this view is in.
    @Environment(\.displayScale) private var displayScale

    /// What is on screen this tick, and the only frame guaranteed to be resident. It is held
    /// across a swap of swings only until the new clip's first frame decodes.
    @State private var displayed: UIImage?

    /// The decoded frames, and the ceiling they are held under. One object rather than three
    /// pieces of state — see `FrameCache`.
    @State private var cache = FrameCache()

    /// Read off the ring rather than spelled out here, so the replay cannot end up playing at a
    /// rate the ring stopped sampling at. Divided rather than written as milliseconds because
    /// 1/15s is 66.67ms, and rounding it down would play the swing ~1% fast for the life of the
    /// take.
    private static let frameInterval = Duration.seconds(1) / SwingFrameBuffer.sampledFrameRate

    /// How far ahead of the playhead frames are decoded, and it exists for the LOOP SEAM rather
    /// than for margin: the wrap back to frame 0 is decoded during the tick before it is shown, so
    /// it costs exactly what every other frame costs instead of stalling the loop for a decode.
    ///
    /// One tick, cut from four and then from two as the ring's resolution rose, because headroom is
    /// bought in ticks and paid for in whole bitmaps — 8.3MB each at native. One tick is 66.7ms
    /// against a full-frame JPEG decode of ~10–25ms (ESTIMATED), so the margin is still 3–6x and the
    /// seam is still covered.
    private static let lookahead = 1

    /// What the decoded bitmaps may cost. `24 * 1024 * 1024` bytes — MiB, spelled the way
    /// `SwingFrameBuffer.maximumHeldBytes` is, which is 25MB against the decimal MB every bitmap
    /// figure below is quoted in.
    ///
    /// Deliberately the figure the full-screen path ALREADY spends: two 8.3MB frames cached plus one
    /// being decoded is 24.9MB, which is exactly what a capacity of `lookahead + 1` came to. Nothing
    /// grows here. What changes is that the same budget, spent on the tile's 0.52MB frames, buys the
    /// WHOLE clip instead of two frames of it.
    ///
    /// The budget is also insensitive, which is the useful thing to know before moving it: anything
    /// from ~20MB to ~300MB produces identical behaviour in both modes, because the tile needs
    /// 19.7MB and the full screen needs 315MB. Moving it inside that band changes nothing.
    ///
    /// **And these bytes are reclaimable, which is what makes holding 19.7MB in a 120pt tile
    /// defensible.** They belong to a view that is mounted only while `RecordingViewModel`
    /// publishes a replay, and a system memory-pressure event now drops that replay
    /// (`SwingFrameBuffer.onShed`) — so the tile's whole cache goes back with it, in the same event
    /// that empties the ring. Before that fan-out existed this budget would have been a leak the
    /// valve could not reach.
    private static let bitmapBudget = 24 * 1024 * 1024

    /// How many decoded frames to keep, and the answer is one of exactly two numbers — because in a
    /// LOOP nothing in between buys anything.
    ///
    /// **The reason is the wrap.** The playhead is cyclic and eviction is FIFO, so a cache smaller
    /// than the clip has already evicted frame 0 by the time the wrap reaches it again: every frame
    /// is a miss on every lap whether the cache held 2 of 38 or 30 of 38. Only a cache that covers
    /// the WHOLE clip ever stops decoding. So this returns full coverage when the budget affords it
    /// and the bare minimum — the playhead plus its lookahead, the least at which every `show` is a
    /// hit — when it does not. Anything between is bytes spent for no decode saved.
    ///
    /// What that comes to today (MEASURED arithmetic from `bitmapBytes(at:)`):
    ///   * **The 120x160 tile** decodes at 480px, 0.52MB a frame, so a ~38-frame clip (2.5s at
    ///     15fps) is 19.7MB and fits. Decoded ONCE — after the first lap the loop performs no
    ///     decode, no allocation and no free, for as long as it is on screen.
    ///   * **The full screen** decodes at 1920px, 8.3MB a frame, so the same clip is 315MB and does
    ///     not fit, at any budget an app holding a movie file open could ask for. It keeps 2 of 38
    ///     frames — 5% of the clip — and decodes one frame a tick for as long as the replay is up.
    ///     That is intrinsic to a full-resolution replay rather than a number chosen here: the only
    ///     lever is `SwingFrameBuffer.maximumEdge`, and even its documented step down to 960 leaves
    ///     the clip at 79MB.
    private static func cacheCapacity(forClipOf frames: Int, at longEdge: Int) -> Int {
        let minimum = lookahead + 1
        guard frames > minimum, frames * bitmapBytes(at: longEdge) <= bitmapBudget else { return minimum }
        return frames
    }

    /// What one decoded frame costs. Exact rather than rounded: `RingFrameDecoder.longEdge` only
    /// ever answers 240, 480, 960 or 1920 — halvings of the stored edge — so the 9/16 divides
    /// cleanly and this is 8.29MB at 1920 and 0.52MB at 480.
    ///
    /// Two assumptions, both named because they are the way this figure goes wrong. **4 bytes a
    /// pixel** is what an 8-bit RGB bitmap with a skipped alpha channel costs, not a measurement of
    /// what ImageIO returned. **9:16** is `CaptureSessionConfigurator`'s 1080p target — the same
    /// dependency `SwingFrameBuffer.warmUpWidth`/`warmUpHeight` name — so a device that negotiated
    /// 4:3 would make this an under-estimate by a third. Both err by a constant factor, and the
    /// budget above has a ~16x band of insensitivity, so neither can change the answer.
    private static func bitmapBytes(at longEdge: Int) -> Int {
        longEdge * (longEdge * 9 / 16) * 4
    }

    /// `Color.clear` as the base, never a fixed frame: it expands to whatever the parent
    /// offers, and the image letterboxes inside it. That is the whole reason one view can
    /// serve both a 120pt tile and a full screen.
    ///
    /// The `GeometryReader` is what turns that box into a decode size, and it changes no layout:
    /// `Color.clear` fills the reader and the reader fills what the parent offered. It is read here,
    /// in the body, rather than through `onGeometryChange` so the first tick already knows how big
    /// its bitmap should be — a callback that landed after the loop started would decode the opening
    /// frame at the wrong size.
    var body: some View {
        GeometryReader { proxy in
            surface(decodedAt: RingFrameDecoder.longEdge(drawnIn: proxy.size, scale: displayScale))
        }
    }

    private func surface(decodedAt longEdge: Int) -> some View {
        Color.clear
            .overlay { picture }
            .task(id: playbackIdentity(decodedAt: longEdge)) { await play(decodedAt: longEdge) }
    }

    /// What restarts the loop: a new swing, the same swing crossing from waiting to playable, or the
    /// box changing size. The `replay.id` alone cannot express the second — a swing keeps its
    /// `SwingClip` id through both publications — and without the restart a replay would sit on its
    /// own progress bar forever. The third is what keeps the cache honest: every bitmap in it was
    /// decoded for one size, so a resize has to start over rather than mix them.
    private func playbackIdentity(decodedAt longEdge: Int) -> PlaybackIdentity {
        PlaybackIdentity(swing: replay.id, isPlayable: !replay.frames.isEmpty, longEdge: longEdge)
    }

    private struct PlaybackIdentity: Equatable {
        let swing: UUID
        let isPlayable: Bool
        let longEdge: Int
    }

    /// **`.fit`, deliberately, at every size.** The frames are 9:16 and neither presentation
    /// is, so filling would crop away the top of the backswing arc and the ground the ball
    /// sits on — which is most of what a golfer looks at. Letterboxing against the black
    /// underneath costs some bar on two sides and keeps the whole swing in view.
    ///
    /// The two branches are mutually exclusive by construction: the loading surface is what this
    /// shows when there is no frame yet, and the first frame to arrive replaces it.
    @ViewBuilder
    private var picture: some View {
        if let displayed {
            Image(uiImage: displayed)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(x: isMirrored ? -1 : 1)
        } else {
            SwingReplayLoadingView(loading: replay.loading)
        }
    }

    /// The loop, and the decoder, deliberately the same thing.
    ///
    /// This was a `TimelineView(.periodic)` while every frame was already decoded. It cannot
    /// stay one: a `TimelineView` body must be pure, so it can neither decode a missing frame
    /// nor fill the cache, and a schedule that ticks independently of the decoder would
    /// outrun it and draw gaps. One loop that shows, then prefetches, then sleeps to the next
    /// boundary keeps the two in step by construction.
    ///
    /// `ContinuousClock` against an advancing `deadline` rather than a plain sleep, so the
    /// interval does not accumulate the decode time as drift. `max(clock.now, ...)` is the
    /// catch-up clamp: after a stall — a backgrounded scene, a starved main actor — a deadline
    /// left in the past would make the loop replay the lost seconds flat out, decoding dozens
    /// of frames back to back. It drops the lost time instead.
    private func play(decodedAt longEdge: Int) async {
        let frames = replay.frames
        // Before the guard, never after it. A replay still waiting for its frames would
        // otherwise leave the PREVIOUS swing's bitmaps on screen under the new swing's identity —
        // the same stale-content failure the cancellation check below exists to stop. Clearing
        // `displayed` here is also what raises the loading surface for the wait.
        //
        // The ceiling is re-stated in the same call, because it is decided by exactly the two
        // things that restart this loop: how long the clip is and how big its bitmaps are.
        restart(holding: Self.cacheCapacity(forClipOf: frames.count, at: longEdge))
        guard !frames.isEmpty else { return }

        let clock = ContinuousClock()
        var deadline = clock.now
        var cursor = 0

        while !Task.isCancelled {
            await show(cursor, of: frames, decodedAt: longEdge)
            await prefetch(after: cursor, of: frames, decodedAt: longEdge)
            cursor = (cursor + 1) % frames.count
            deadline = max(clock.now, deadline.advanced(by: Self.frameInterval))
            try? await clock.sleep(until: deadline)
        }
    }

    /// Draws a frame, decoding it first if the prefetch has not got to it yet — which is only
    /// ever true of the clip's very first frame.
    private func show(_ index: Int, of frames: [Data], decodedAt longEdge: Int) async {
        await fill(index, of: frames, decodedAt: longEdge)
        guard !Task.isCancelled, let image = cache[index] else { return }
        // The one line that takes the loading surface down, because it is the only place that
        // knows a frame is actually on screen.
        displayed = image
    }

    /// One tick's worth of headroom, refilled one tick at a time. `fill` returns without
    /// suspending for anything already cached, so on a cache too small for the clip this is exactly
    /// one JPEG decode per tick — the frame that just entered the window — and `show` above is a
    /// cache hit. The first tick is the exception: it decodes the frame it draws and then banks the
    /// whole lookahead, which is where the depth comes from.
    ///
    /// On a cache that COVERS the clip this is one decode per tick for the first lap and then
    /// nothing at all: every index is already resident, `fill` returns without suspending, and the
    /// loop is a sleep and an assignment. The seam back to frame 0 is covered either way — that is
    /// what `lookahead` is for, and on the covering cache frame 0 is simply still there.
    private func prefetch(after cursor: Int, of frames: [Data], decodedAt longEdge: Int) async {
        for step in 1...Self.lookahead {
            await fill((cursor + step) % frames.count, of: frames, decodedAt: longEdge)
        }
    }

    /// The cancellation guard the old `load()` was missing, now on the only path that writes
    /// decoded state. `.task(id:)` cancels this loop when a newer swing arrives, but a decode
    /// already suspended resumes regardless — and without this it would publish the PREVIOUS
    /// swing's frame under the new swing's badge, which is exactly what the loop's own doc
    /// comment promises cannot happen.
    private func fill(_ index: Int, of frames: [Data], decodedAt longEdge: Int) async {
        guard cache[index] == nil else { return }
        guard let image = await RingFrameDecoder.decoded(frames[index], longEdge: longEdge) else { return }
        guard !Task.isCancelled else { return }
        cache.hold(image, at: index)
    }

    /// The previous swing's bitmaps go before the new one's first decode, not after it: a
    /// blank tick is honest, a stale swing under a fresh badge is not.
    private func restart(holding capacity: Int) {
        cache.restart(holding: capacity)
        displayed = nil
    }
}

// MARK: - Frame Cache

/// The decoded frames a surface is holding, and the ceiling it holds them under.
///
/// Its own type because "which bitmaps are resident" is one decision with three parts that have to
/// agree — the images, the order they were decoded in, and how many are allowed — and three pieces
/// of `@State` can be changed one at a time. Here a new clip or a new decode size resets all three
/// or none, which is the only correct pair of outcomes: every bitmap in it was decoded for one clip
/// at one size.
///
/// FIFO is what makes the eviction right rather than merely bounded: frames are decoded in playback
/// order, so the oldest entry is always the one furthest behind the playhead. When the ceiling is
/// the clip's own length nothing is ever evicted, and `decodeOrder` simply grows to it once.
private struct FrameCache {
    private var images: [Int: UIImage] = [:]
    private var decodeOrder: [Int] = []
    private var capacity = 0

    subscript(index: Int) -> UIImage? { images[index] }

    mutating func hold(_ image: UIImage, at index: Int) {
        images[index] = image
        decodeOrder.append(index)
        guard decodeOrder.count > capacity else { return }
        images.removeValue(forKey: decodeOrder.removeFirst())
    }

    mutating func restart(holding capacity: Int) {
        images = [:]
        decodeOrder = []
        self.capacity = capacity
    }
}

// MARK: - Loading

/// The wait, drawn as the user asked for it: black, with a bar filling left to right in white.
///
/// **The progress is real.** It is not an animation standing in for one — the bar's length is the
/// wait's own length, published by `RecordingViewModel` as `SwingReplay.Loading` before the wait
/// starts, and the fill is that clock. Two consequences worth stating, because they are what
/// separate this from a bar that lies:
///
///   * It cannot stall. The fill is driven off a duration that is known up front, so it advances
///     until it is full whatever the encoder is doing.
///   * It cannot finish early. The replay is presented the moment its frames are ready, which is
///     normally BEFORE the bar is full — the picture cutting a bar off is honest, a full bar with
///     nothing behind it is not.
///
/// One implementation at two sizes, like everything else on this surface: 120×160 in the tile,
/// full screen over the preview. The bar scales with the box it is in rather than being suppressed
/// in the small one, because in `.cameraOnMain` the tile is the ONLY place the wait is shown.
private struct SwingReplayLoadingView: View {

    /// The wait, or nil when there is none to describe — which happens for the handful of
    /// milliseconds between a playable replay arriving and its first JPEG decoding (~10–25ms at the
    /// ring's native size, ESTIMATED), and for a wait too short to have been worth a bar at all.
    /// Then the surface is
    /// plain black: there is no honest bar to draw, and a bar drawn anyway would be the guess this
    /// whole view exists to avoid.
    let loading: SwingReplay.Loading?

    /// Under Reduce Motion nothing is handed to the animator. The fill is stepped instead — see
    /// `step`.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var fill: Double = 0

    /// Below this the surface is the picture-in-picture tile rather than the screen. 120pt is the
    /// tile (`CapturePiPTile.Metrics`), and nothing between it and a full screen exists.
    private static let compactWidth: CGFloat = 200

    /// How often the stepped fill advances under Reduce Motion. Four times a second: coarse
    /// enough to read as a change of state rather than as movement, frequent enough that a ~1s
    /// wait is described four times over.
    private static let stepInterval = Duration.milliseconds(250)

    /// One display frame at 60Hz — long enough for the resumed fill to be rendered before the
    /// animation is attached to it, short enough to be invisible in a ~1s wait. See `follow`.
    private static let resumeHandoff = Duration.milliseconds(16)

    var body: some View {
        ZStack {
            Color.black
            bar
        }
    }

    @ViewBuilder
    private var bar: some View {
        if let loading {
            GeometryReader { proxy in track(sized: Metrics(containerWidth: proxy.size.width)) }
                // Keyed on the wait itself, not on the view's appearance: a swing detected while
                // the previous one is still loading replaces the wait under a surface that is
                // already mounted, and the bar has to start over for it.
                .task(id: loading.startedAt) { await follow(loading) }
        }
    }

    /// The bar and its track, centred in whatever box this is. The track is what makes the fill
    /// legible as a fraction — without it a short white bar on black reads as a short bar, not as
    /// a fifth of the way through.
    private func track(sized metrics: Metrics) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.22))
            .frame(width: metrics.width, height: metrics.height)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.white)
                    .frame(width: metrics.width * fill, height: metrics.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Loading the swing replay", comment: "Accessibility label for the progress bar shown on the capture screen while a detected swing's replay is still being assembled"))
            .accessibilityAddTraits(.updatesFrequently)
    }

    /// Hands the fill to the render server as ONE linear animation over the wait's remaining
    /// length. No per-frame main-actor writes — this runs over a live capture session while
    /// detection is analysing 30 frames a second, and a 60Hz state write to keep a bar moving is
    /// exactly the cost this screen refuses to pay for a skeleton nobody can see.
    ///
    /// `fraction` first, which is what makes a surface mounted PART WAY through a wait pick the
    /// bar up where the wait actually is: the tile and the full screen trade places on a tap, and
    /// a swing detected during another swing's wait replaces it under a surface already on screen.
    ///
    /// **The sleep between the two writes is load-bearing, not a settling delay.** SwiftUI
    /// coalesces every state change in one turn into a single update, so an unanimated resume and
    /// an animated target written together would collapse into "animate to 1" — interpolated from
    /// whatever was last on screen, which after a previous wait can be a full bar that then never
    /// appears to move. One display frame apart, the resume is rendered before the animation is
    /// attached to it.
    private func follow(_ loading: SwingReplay.Loading) async {
        fill = loading.fraction
        guard reduceMotion else {
            try? await Task.sleep(for: Self.resumeHandoff)
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: loading.remaining)) { fill = 1 }
            return
        }
        await step(loading)
    }

    /// The Reduce Motion path: the same clock, sampled, with nothing interpolated between the
    /// samples. Ends when the wait does, or when the surface goes away.
    private func step(_ loading: SwingReplay.Loading) async {
        while !Task.isCancelled, fill < 1 {
            try? await Task.sleep(for: Self.stepInterval)
            guard !Task.isCancelled else { return }
            fill = loading.fraction
        }
    }

    /// The bar at both sizes it has to read at. Proportional rather than fixed, so it is a bar in
    /// a 120pt tile and a bar on a 393pt screen instead of a hairline in one and a slab in the
    /// other.
    private struct Metrics {
        let width: CGFloat
        let height: CGFloat

        init(containerWidth: CGFloat) {
            let isCompact = containerWidth < SwingReplayLoadingView.compactWidth
            width = max(24, containerWidth * (isCompact ? 0.62 : 0.5))
            height = isCompact ? 3 : 6
        }
    }
}
