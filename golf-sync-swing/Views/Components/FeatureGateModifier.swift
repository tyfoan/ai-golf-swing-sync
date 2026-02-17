//
//  FeatureGateModifier.swift
//  golf-sync-swing
//
//  View modifier that presents a paywall when the user
//  attempts to access a locked premium feature.
//

import SwiftUI

struct FeatureGateModifier: ViewModifier {

    let feature: PremiumFeature
    @Binding var isPresented: Bool
    @State private var showPaywall = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, shouldShow in
                guard shouldShow else { return }
                handleGate()
            }
            .fullScreenCover(isPresented: $showPaywall) {
                AppPaywallView(
                    source: .featureGate,
                    onDismiss: {
                        showPaywall = false
                        isPresented = false
                    }
                )
            }
    }

    private func handleGate() {
        guard !FeatureAccess.isUnlocked(feature) else { return }
        isPresented = false
        showPaywall = true
    }
}

extension View {
    func featureGate(_ feature: PremiumFeature, isPresented: Binding<Bool>) -> some View {
        modifier(FeatureGateModifier(feature: feature, isPresented: isPresented))
    }
}
