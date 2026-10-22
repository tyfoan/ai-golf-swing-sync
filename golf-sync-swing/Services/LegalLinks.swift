//
//  LegalLinks.swift
//  golf-sync-swing
//
//  The app's legal documents, shared by the paywall and Settings so the two can
//  never drift apart again — both once linked another app's terms and privacy.
//

import Foundation

enum LegalLinks {

    /// Apple's standard EULA, which covers the auto-renewing plans (App Review 3.1.2).
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Golf Sync Swing's own privacy policy. App Store Connect must list the same URL.
    static let privacyPolicy = URL(string: "https://withcoach.app/golf-sync-swing/privacy")!
}
