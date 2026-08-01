//
//  LiveRingFrameView.swift
//  golf-sync-swing
//
//  The live camera, drawn as still frames pulled off `SwingFrameBuffer`.
//
//  WHY NOT A PREVIEW LAYER
//  -----------------------
//  Because there is already one, it is mounted full-screen, and attaching a second
//  `AVCaptureVideoPreviewLayer` to the running session is what blacked out the main preview —
//  twice, on two separate device sessions. Moving the existing one into the tile is the same
//  hazard by another name: a `UIViewRepresentable` that changes container in SwiftUI is
//  destroyed and recreated, which detaches and reattaches the layer.
//
//  So when the replay covers the main screen, the tile draws the camera from the ring the
//  replay itself comes from. The honest consequence: this updates at the ring's sampling rate
//  (~15 fps) and not at preview smoothness. On a 120×160 tile that is a trade worth making to
//  delete the whole black-screen failure class.
//
//  The ring stores those frames at 1080x1920 now, and this tile draws them into 360x480 device
//  pixels — so it asks `RingFrameDecoder` for the size it is actually drawing rather than for the
//  size that was stored. That is 0.5MB a frame instead of 8.3MB, and a quarter-scale decode
//  straight out of the JPEG's DCT blocks instead of a full one.
//
//  WHY POLLING
//  -----------
//  A callback fired from `ingest` would put a closure call — and a main-queue hop — on the
//  30 fps capture path for the benefit of a thumbnail. Polling costs the capture path exactly
//  nothing, and costs an idle app nothing either: this view is only ever mounted while a take
//  is running, which is the only time the ring holds anything.
//

import SwiftUI
import UIKit

struct LiveRingFrameView: View {

    /// The ring itself, injected. `nonisolated` and lock-guarded, so reading it from the main
    /// actor is safe and synchronous.
    let buffer: SwingFrameBuffer

    /// The same parity the replay flips by: these frames come from the video-data output,
    /// which the configurator forces unmirrored, while the front camera's preview auto-mirrors.
    /// Without this the tile would show the golfer's mirror image next to a main preview
    /// showing them the other way round.
    let isMirrored: Bool

    /// Points to device pixels, for the decode size — the same environment value
    /// `SwingReplayPlayerView` reads, for the same reason.
    @Environment(\.displayScale) private var displayScale

    @State private var image: UIImage?
    @State private var drawnSequence: UInt64?

    /// The ring samples every other frame of a 30 fps capture, so polling faster than this
    /// only asks for frames that cannot exist yet.
    private static let pollInterval = Duration.milliseconds(66)

    /// `Color.clear` as the base for the same reason `SwingReplayPlayerView` uses one: it
    /// takes the size the parent offers and lets the frame letterbox inside it. The
    /// `GeometryReader` around it changes no layout and buys the decode size — measured rather than
    /// hardcoded to the tile's 120×160, so this view keeps knowing nothing about where it is mounted.
    var body: some View {
        GeometryReader { proxy in
            surface(decodedAt: RingFrameDecoder.longEdge(drawnIn: proxy.size, scale: displayScale))
        }
    }

    private func surface(decodedAt longEdge: Int) -> some View {
        Color.clear
            .overlay { picture }
            .task(id: longEdge) { await follow(decodedAt: longEdge) }
    }

    /// `.fit` and never `.fill`, matching the replay beside it — the two surfaces show the
    /// same camera and must not disagree about how much of it is in shot.
    @ViewBuilder
    private var picture: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(x: isMirrored ? -1 : 1)
        }
    }

    /// Runs for exactly as long as the view is mounted at one size: `.task` cancels the loop when
    /// the tile goes away or changes size, and a cancelled sleep returns immediately rather than
    /// holding it open. A resize keeps the frame already on screen and simply decodes the next one
    /// at the new size — there is only ever one live frame, so there is nothing stale to clear.
    private func follow(decodedAt longEdge: Int) async {
        while !Task.isCancelled {
            await drawLatest(decodedAt: longEdge)
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    /// Two ways to draw nothing new, and both leave the previous frame on screen rather than
    /// blanking: the ring is disarmed (a take that ended a main-queue hop ago), or it has not
    /// produced a frame since the last poll. A tile that flickers to black between frames
    /// reads as a broken camera, which is precisely the report this whole design exists to
    /// stop generating.
    ///
    /// Deliberately NO cancellation check after the await, unlike `SwingReplayPlayerView`,
    /// which needs one. The distinction is identity: that view's `.task` carries an `id` and
    /// restarts on every new swing, so a superseded decode can publish the PREVIOUS swing's
    /// frames. This `.task` carries no id — it is cancelled only at unmount — and there is
    /// exactly one live camera and one monotonic `sequence`, so a late write can only ever
    /// publish a slightly stale frame of the very content it was already drawing.
    private func drawLatest(decodedAt longEdge: Int) async {
        guard let latest = buffer.latest(), latest.sequence != drawnSequence else { return }
        guard let decoded = await RingFrameDecoder.decoded(latest.jpeg, longEdge: longEdge) else { return }
        drawnSequence = latest.sequence
        image = decoded
    }
}
