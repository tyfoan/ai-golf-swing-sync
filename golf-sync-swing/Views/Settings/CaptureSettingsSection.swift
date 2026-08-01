//
//  CaptureSettingsSection.swift
//  golf-sync-swing
//
//  One preference: what the capture screen's main surface shows once a swing has been
//  detected. The swap itself is always available on the tile — this only decides which way
//  round a take opens, so someone who always wants one of the two never has to tap for it.
//

import SwiftUI

struct CaptureSettingsSection: View {

    /// The key comes from `CaptureDisplayMode`, never a literal: `RecordingViewModel` reads
    /// the same default when a take's first swing lands, and a spelling the two could disagree
    /// about is a setting that silently does nothing. The fallback matches
    /// `CaptureDisplayMode.storedDefault`, so an untouched install and a saved choice describe
    /// the same screen.
    @AppStorage(CaptureDisplayMode.defaultModeKey)
    private var defaultMode: CaptureDisplayMode = .swingOnMain

    var body: some View {
        Section {
            modePicker
        } header: {
            Text(String(localized: "Recording", comment: "Settings section header for capture-screen preferences"))
        } footer: {
            Text(String(localized: "Once a swing is detected, the main screen can show it looping while the live camera moves into the small tile. Tap the tile at any time to swap them.", comment: "Settings explanation for the preference that decides which of the capture screen's two surfaces holds the swing replay after a swing is detected"))
        }
    }

    private var modePicker: some View {
        Picker(selection: $defaultMode) {
            ForEach(CaptureDisplayMode.allCases) { mode in
                Text(mode.settingsLabel).tag(mode)
            }
        } label: {
            Text(String(localized: "Main screen shows", comment: "Settings row label; the options answer what the capture screen's main surface shows after a swing has been detected"))
        }
    }
}
