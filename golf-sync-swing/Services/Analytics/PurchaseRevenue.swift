//
//  PurchaseRevenue.swift
//  golf-sync-swing
//
//  Analytics-layer value type describing a completed PAID purchase. Kept
//  separate from RevenueCat / PaywallPlan so the analytics seam never imports
//  the purchase SDK. Maps onto Amplitude's Revenue API in AmplitudeAnalytics.
//  Trials carry no revenue and never produce one of these.
//

import Foundation

struct PurchaseRevenue: Equatable {
    let productId: String
    let price: Double
    let currency: String
    let quantity: Int

    init(productId: String, price: Double, currency: String, quantity: Int = 1) {
        self.productId = productId
        self.price = price
        self.currency = currency
        self.quantity = quantity
    }
}
