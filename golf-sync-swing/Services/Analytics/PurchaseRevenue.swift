//
//  PurchaseRevenue.swift
//  golf-sync-swing
//
//  Analytics-layer value type describing a completed PAID purchase, carried by
//  the purchase_completed event. Kept separate from RevenueCat / PaywallPlan so
//  the analytics seam never imports the purchase SDK. Recognised revenue comes
//  from RevenueCat's server-side Amplitude integration, not from this type.
//  Trials carry no revenue and never produce one of these.
//

import Foundation

struct PurchaseRevenue: Equatable {
    let productId: String
    let price: Double
    let currency: String
}
