//
//  PlaybackTransport.swift
//  golf-sync-swing
//
//  What the transport row drives. The comparison and the single-video player offer the
//  same play/pause, frame step and speed, so both screens share one row of controls
//  (TransportControlsView) and cannot drift apart in look or behaviour.
//

@MainActor
protocol PlaybackTransport: AnyObject {
    static var playbackRates: [Float] { get }
    var isPlaying: Bool { get }
    var playbackRate: Float { get }
    func togglePlayPause()
    func stepFrame(forward: Bool)
    func setPlaybackRate(_ rate: Float)
}

extension ComparisonViewModel: PlaybackTransport {}
extension VideoPlayerViewModel: PlaybackTransport {}
