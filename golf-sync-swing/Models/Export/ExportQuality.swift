//
//  ExportQuality.swift
//  golf-sync-swing
//
//  The three export tiers. A tier is named by the short side of what it
//  renders ("720p", "1080p", "1440p"), so its name stays true for every
//  aspect ratio. The raw values are analytics values — never rename them.
//

import CoreGraphics
import Foundation

enum ExportQuality: String, CaseIterable, Identifiable {
    case standard
    case high
    case ultra

    var id: String { rawValue }

    /// Subscribers start on the recommended HD tier; everyone else on the free one.
    static var defaultChoice: ExportQuality {
        FeatureAccess.isUnlocked(.exportHD) ? .high : .standard
    }

    var isLocked: Bool {
        requiresPremium && !FeatureAccess.isUnlocked(.exportHD)
    }

    func title(renderSize: CGSize) -> String {
        "\(Int(min(renderSize.width, renderSize.height)))p"
    }

    func detail(renderSize: CGSize) -> String {
        [Self.dimensions(of: renderSize), descriptor].joined(separator: " · ")
    }

    /// Plain digits: a localized number would print "1 280" in many locales.
    static func dimensions(of size: CGSize) -> String {
        "\(Int(size.width))×\(Int(size.height))"
    }

    private var descriptor: String {
        guard !isLocked else {
            return String(localized: "Pro", comment: "Export quality row: this tier needs a Pro subscription")
        }
        return Self.descriptors[self] ?? ""
    }

    private static let descriptors: [ExportQuality: String] = [
        .standard: String(localized: "Smaller file", comment: "Export quality row: what the free 720p tier is good for"),
        .high: String(localized: "Recommended", comment: "Export quality row: the 1080p tier is the recommended one"),
        .ultra: String(localized: "Best quality", comment: "Export quality row: the 1440p tier")
    ]

    var resolution: CGSize {
        switch self {
        case .standard: return CGSize(width: 720, height: 1280)
        case .high:     return CGSize(width: 1080, height: 1920)
        case .ultra:    return CGSize(width: 1440, height: 2560)
        }
    }

    /// Multiplier applied to a layout's base export canvas. Derived from the
    /// legacy fixed resolutions (720/1080/1440 wide on a 1080×1920 canvas) so
    /// both export paths produce identical sizes for a 9:16 layout.
    var renderScale: CGFloat {
        switch self {
        case .standard: return 720.0 / 1080.0
        case .high:     return 1.0
        case .ultra:    return 1440.0 / 1080.0
        }
    }

    func renderSize(for exportSize: CGSize) -> CGSize {
        CGSize(
            width: evenPixels(exportSize.width * renderScale),
            height: evenPixels(exportSize.height * renderScale)
        )
    }

    /// Video encoders require even pixel dimensions.
    private func evenPixels(_ value: CGFloat) -> CGFloat {
        (value / 2).rounded() * 2
    }

    var requiresPremium: Bool {
        switch self {
        case .standard: return false
        case .high:     return true
        case .ultra:    return true
        }
    }
}
