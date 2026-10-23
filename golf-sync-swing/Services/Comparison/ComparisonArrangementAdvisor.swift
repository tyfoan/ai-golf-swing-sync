//
//  ComparisonArrangementAdvisor.swift
//  golf-sync-swing
//
//  Picks the arrangement a comparison opens in: the one that shows the SMALLER of the
//  two swings biggest on a portrait screen. Every bundled pro swing is landscape (3:2),
//  so a pro against anything — or two landscape takes — opens one above the other; two
//  portrait recordings open side by side. The user can still switch either way.
//

import CoreGraphics

struct ComparisonArrangementAdvisor {
    /// Width over height of the comparison stage on a portrait iPhone.
    var stageAspect: CGFloat = 0.7

    func preferredMode(for videos: [SwingVideo]) async -> ComparisonMode {
        var sizes: [CGSize] = []
        for video in videos {
            if let size = await VideoDisplaySize.of(video.validLocalURL) { sizes.append(size) }
        }
        return preferredMode(for: sizes)
    }

    func preferredMode(for sizes: [CGSize]) -> ComparisonMode {
        let rows = smallestFittedArea(of: sizes, in: CGSize(width: stageAspect, height: 0.5))
        let columns = smallestFittedArea(of: sizes, in: CGSize(width: stageAspect / 2, height: 1))
        return rows >= columns ? .topBottom : .sideBySide
    }

    private func smallestFittedArea(of sizes: [CGSize], in pane: CGSize) -> CGFloat {
        sizes.map { fittedArea(of: $0, in: pane) }.min() ?? 0
    }

    private func fittedArea(of size: CGSize, in pane: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 0 }
        let scale = min(pane.width / size.width, pane.height / size.height)
        return size.width * size.height * scale * scale
    }
}
