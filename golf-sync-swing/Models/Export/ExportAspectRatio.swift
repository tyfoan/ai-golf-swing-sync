//
//  ExportAspectRatio.swift
//  golf-sync-swing
//
//  Output aspect ratio presets for the export editor.
//  Lifted with adaptation from video-collage's AspectRatio enum.
//

import CoreGraphics

enum ExportAspectRatio: String, CaseIterable, Identifiable {
    case sideBySide        // 16:9 (also covers "Landscape")
    case tikTokVertical    // 9:16
    case square            // 1:1
    case instagramPortrait // 4:5
    case classicLandscape  // 4:3
    case classicPortrait   // 3:4
    case photoPortrait     // 2:3
    case photoLandscape    // 3:2
    case cinemascope       // 2.35:1
    case ultraWide         // 2:1
    case tallBanner        // 1:2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sideBySide:        return "Side-by-side"
        case .tikTokVertical:    return "Vertical (TikTok)"
        case .square:            return "Square"
        case .instagramPortrait: return "Instagram 4:5"
        case .classicLandscape:  return "Classic 4:3"
        case .classicPortrait:   return "Classic 3:4"
        case .photoPortrait:     return "Photo 2:3"
        case .photoLandscape:    return "Photo 3:2"
        case .cinemascope:       return "Cinemascope"
        case .ultraWide:         return "Ultra-wide"
        case .tallBanner:        return "Tall Banner"
        }
    }

    var exportSize: CGSize {
        switch self {
        case .sideBySide:        return CGSize(width: 1920, height: 1080)
        case .tikTokVertical:    return CGSize(width: 1080, height: 1920)
        case .square:            return CGSize(width: 1080, height: 1080)
        case .instagramPortrait: return CGSize(width: 1080, height: 1350)
        case .classicLandscape:  return CGSize(width: 1440, height: 1080)
        case .classicPortrait:   return CGSize(width: 1080, height: 1440)
        case .photoPortrait:     return CGSize(width: 1080, height: 1620)
        case .photoLandscape:    return CGSize(width: 1620, height: 1080)
        case .cinemascope:       return CGSize(width: 2540, height: 1080)
        case .ultraWide:         return CGSize(width: 2160, height: 1080)
        case .tallBanner:        return CGSize(width: 1080, height: 2160)
        }
    }

    var ratio: CGFloat { exportSize.width / exportSize.height }

    var arrangement: VideoArrangement {
        exportSize.width >= exportSize.height ? .horizontal : .vertical
    }

    var isPrimary: Bool {
        switch self {
        case .sideBySide, .tikTokVertical, .square: return true
        default: return false
        }
    }
}
