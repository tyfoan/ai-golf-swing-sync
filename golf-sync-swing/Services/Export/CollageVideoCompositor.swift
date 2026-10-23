//
//  CollageVideoCompositor.swift
//  golf-sync-swing
//
//  Custom AVVideoCompositing implementation. The reason this exists rather than
//  using setTransform on AVMutableVideoCompositionLayerInstruction: standard
//  layer instructions have no per-cell clipping. When a video gets zoomed beyond
//  its cell rect, it bleeds across the canvas and overlaps the other cell. Here
//  we explicitly cropped(to: cellRect) each frame so cells respect their bounds.
//
//  Port of video-collage's CollageVideoCompositor, simplified to video-only
//  (no photos, stickers, watermarks or borders). CellRenderer draws
//  each cell; this class is the AVFoundation plumbing and the layering.
//

import AVFoundation
import CoreImage
import CoreVideo
import UIKit

final class CollageVideoCompositor: NSObject, AVVideoCompositing {

    // MARK: - Shared configuration

    private static var sharedCells: [CellConfiguration] = []
    private static var sharedLayout: CompositorLayout = .sideBySide
    private static let configLock = NSLock()

    static func configureShared(cells: [CellConfiguration], layout: CompositorLayout = .sideBySide) {
        configLock.lock()
        sharedCells = cells
        sharedLayout = layout
        configLock.unlock()
    }

    // MARK: - Instance state

    private var cells: [CellConfiguration] = []
    private var layout: CompositorLayout = .sideBySide
    private let ciContext: CIContext
    private let renderQueue = DispatchQueue(label: "com.golfsyncswing.compositor", qos: .userInitiated)
    private var renderContext: AVVideoCompositionRenderContext?
    private var activeRequests: [AVAsynchronousVideoCompositionRequest] = []
    private let requestsLock = NSLock()

    override init() {
        let opts: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .cacheIntermediates: true,
            .highQualityDownsample: true
        ]
        if let metal = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: metal, options: opts)
        } else {
            ciContext = CIContext(options: opts)
        }
        super.init()
        Self.configLock.lock()
        cells = Self.sharedCells
        layout = Self.sharedLayout
        Self.configLock.unlock()
    }

    // MARK: - AVVideoCompositing

    var sourcePixelBufferAttributes: [String: Any]? {
        [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderQueue.async { [weak self] in
            self?.renderContext = newRenderContext
        }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            autoreleasepool {
                guard let self else {
                    request.finish(with: NSError(domain: "CollageVideoCompositor", code: -1))
                    return
                }
                self.requestsLock.lock()
                self.activeRequests.append(request)
                self.requestsLock.unlock()

                do {
                    let buffer = try self.render(request: request)
                    request.finish(withComposedVideoFrame: buffer)
                } catch {
                    request.finish(with: error as NSError)
                }

                self.requestsLock.lock()
                self.activeRequests.removeAll { $0 === request }
                self.requestsLock.unlock()
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        requestsLock.lock()
        let pending = activeRequests
        activeRequests.removeAll()
        requestsLock.unlock()
        for r in pending {
            r.finish(with: NSError(domain: AVFoundationErrorDomain, code: AVError.Code.operationCancelled.rawValue))
        }
    }

    // MARK: - Frame rendering

    private func render(request: AVAsynchronousVideoCompositionRequest) throws -> CVPixelBuffer {
        guard let renderContext else {
            throw NSError(domain: "CollageVideoCompositor", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Render context is nil"])
        }
        guard let outputBuffer = renderContext.newPixelBuffer() else {
            throw NSError(domain: "CollageVideoCompositor", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create output pixel buffer"])
        }
        let canvasRect = CGRect(origin: .zero, size: renderContext.size)
        let output = composedFrame(for: request, canvas: canvasRect)
        ciContext.render(output, to: outputBuffer, bounds: canvasRect, colorSpace: CGColorSpaceCreateDeviceRGB())
        ciContext.clearCaches()
        return outputBuffer
    }

    /// The cream canvas, then each cell that has a frame at this time, cut to its card;
    /// a blended swing only inside the first swing's card. A track with nothing at this
    /// time (the waiting swing of a sequential export) has no frame and draws nothing,
    /// and in sequential the swing whose turn it is replaces the one before it.
    private func composedFrame(for request: AVAsynchronousVideoCompositionRequest, canvas: CGRect) -> CIImage {
        let background = CIImage(color: ExportCanvasColor.ciColor).cropped(to: canvas)
        var output = background
        var firstCard: [RoundedFrame] = []
        for (index, cell) in cells.enumerated() {
            guard let pixelBuffer = request.sourceFrame(byTrackID: cell.videoTrackID) else { continue }
            let renderer = CellRenderer(cell: cell, canvasSize: canvas.size)
            let upright = renderer.uprightImage(of: pixelBuffer)
            let video = renderer.video(from: upright, within: layout.isBlended(cellAt: index) ? firstCard : [])
            if index == 0 { firstCard = [renderer.cardFrame(of: upright)] }
            if layout.showsOneSwingAtATime { output = background }
            output = applyLayoutFilter(video, cellIndex: index).composited(over: output)
        }
        return output.cropped(to: canvas)
    }

    /// For stacked layout, video 2 is rendered with reduced alpha so video 1
    /// shows through; every other cell is drawn as is.
    private func applyLayoutFilter(_ image: CIImage, cellIndex: Int) -> CIImage {
        let opacity = layout.opacity(ofCellAt: cellIndex)
        guard opacity < 1 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)
        ])
    }
}
