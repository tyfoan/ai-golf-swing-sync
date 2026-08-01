//
//  CaptureDisplayMode.swift
//  golf-sync-swing
//
//  Which of the capture screen's two surfaces — the full screen, or the picture-in-picture
//  tile — is showing the live camera, and which is showing the last detected swing. Exactly
//  one of them is the camera at any moment, so one enum describes both.
//
//  WHAT THE MODE DOES *NOT* DO
//  ---------------------------
//  It never moves a camera preview. There is one `AVCaptureVideoPreviewLayer`, mounted
//  full-screen for the life of the tab, and it stays where it is in both modes. Mode A draws
//  the replay OVER it and feeds the tile from `SwingFrameBuffer`'s JPEG ring; mode B draws
//  nothing over it and puts the replay in the tile. Switching changes only what is drawn on
//  top, so no layer is created, destroyed or moved — which is the entire reason the swap is
//  instant and cannot reproduce the black preview that a second layer caused twice.
//
//  The cost of that, stated plainly: the live half of mode A runs at the ring's sampling
//  rate (~15 fps, 240px long edge) rather than true preview smoothness. On a 120×160 tile
//  that is a trade worth making to delete a whole class of failure.
//

import Foundation

enum CaptureDisplayMode: String, CaseIterable, Identifiable {

    /// Full screen: the looping replay of the last detected swing. Tile: the live camera.
    case swingOnMain

    /// Full screen: the live camera preview, uncovered. Tile: the looping replay.
    case cameraOnMain

    var id: String { rawValue }

    /// The other one. There are exactly two surfaces and exactly two contents, so a swap is
    /// total and needs no default case to fall through to.
    var swapped: CaptureDisplayMode {
        switch self {
        case .swingOnMain:  return .cameraOnMain
        case .cameraOnMain: return .swingOnMain
        }
    }

    // MARK: - Stored Default

    /// The `@AppStorage` key behind the Settings preference. Declared on the type rather than
    /// inline in the view, for the same reason `FeatureAccess.devPremiumOverrideKey` is: the
    /// Settings section writes it and `RecordingViewModel` reads it, and a spelling those two
    /// could disagree about is a setting that silently does nothing.
    static let defaultModeKey = "capture.defaultDisplayMode"

    /// The mode a take adopts when its first swing is detected.
    ///
    /// Unset — every install until someone visits Settings — resolves to `.swingOnMain`,
    /// which is the point of the feature: once there is a swing to look at, the swing is what
    /// the screen is for. An unrecognised value gets the same answer rather than a crash.
    static var storedDefault: CaptureDisplayMode {
        UserDefaults.standard.string(forKey: defaultModeKey)
            .flatMap(CaptureDisplayMode.init(rawValue:)) ?? .swingOnMain
    }

    // MARK: - Labels

    /// Settings picker option, read as the answer to "after a swing is detected, the main
    /// screen shows…". Phrased so each option stands up alone in a menu, away from the row
    /// label that asked the question.
    var settingsLabel: String {
        switch self {
        case .swingOnMain:
            return String(localized: "The swing", comment: "Settings option: after a swing is detected the capture screen's main surface shows a looping replay of that swing, and the live camera moves into the small picture-in-picture tile")
        case .cameraOnMain:
            return String(localized: "The camera", comment: "Settings option: after a swing is detected the capture screen's main surface stays on the live camera, and the swing replay goes into the small picture-in-picture tile")
        }
    }

    /// Caption on the picture-in-picture tile — and the only thing that tells the golfer
    /// which of the two surfaces is live, so it names what is IN the tile, never the mode.
    func tileBadge(swingNumber: Int) -> String {
        switch self {
        case .swingOnMain:
            return String(localized: "LIVE", comment: "Badge on the capture screen's picture-in-picture tile when the tile holds the live camera and the main screen is replaying the last detected swing")
        case .cameraOnMain:
            return String(localized: "SWING \(swingNumber)", comment: "Badge on the capture screen's picture-in-picture tile, numbering the detected swing being replayed inside it")
        }
    }
}
