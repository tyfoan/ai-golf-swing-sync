//
//  CompositorLayout.swift
//  golf-sync-swing
//
//  Branch hint for CollageVideoCompositor. Sequential mode never reaches
//  the compositor (handled by AVMutableComposition track concatenation),
//  so it has only the two cases the compositor cares about.
//

import Foundation
import CoreGraphics

enum CompositorLayout: Equatable {
    case sideBySide          // per-cell crop, transforms applied independently
    case stacked(opacity: CGFloat)
}
