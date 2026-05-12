//
//  AppPaywallView.swift
//  golf-sync-swing
//
//  Public paywall entry point. Hosts CustomPaywallView (hand-built
//  SwiftUI). The wrapper exists so the three call sites (Onboarding /
//  FeatureGate / Settings) keep an unchanging API even if we swap the
//  underlying paywall implementation again.
//

import SwiftUI

struct AppPaywallView: View {

    let source: PaywallSource
    let onDismiss: () -> Void

    var body: some View {
        CustomPaywallView(source: source, onDismiss: onDismiss)
    }
}
