//
//  AppPaywallView.swift
//  golf-sync-swing
//
//  Thin wrapper over RevenueCatUI.PaywallView. Layout, copy, and plan
//  selection are managed in the RevenueCat dashboard's Paywall Editor —
//  designers iterate without an app rebuild. This file only forwards
//  purchase / restore / dismissal events back to PurchaseService.
//

import SwiftUI
import RevenueCat
import RevenueCatUI

struct AppPaywallView: View {

    let source: PaywallSource
    let onDismiss: () -> Void

    var body: some View {
        PaywallView(displayCloseButton: true)
            .onPurchaseCompleted { _ in
                Task {
                    await PurchaseService.shared.refreshStatus()
                    onDismiss()
                }
            }
            .onRestoreCompleted { customerInfo in
                guard customerInfo.entitlements[PurchaseService.entitlementID]?.isActive == true else { return }
                Task {
                    await PurchaseService.shared.refreshStatus()
                    onDismiss()
                }
            }
            .onRequestedDismissal { onDismiss() }
    }
}
