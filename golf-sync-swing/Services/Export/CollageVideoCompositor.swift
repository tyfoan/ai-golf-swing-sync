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
//  (no photos, stickers, watermarks, borders, or corner radius).
//

import AVFoundation
import CoreImage
import CoreVideo
import UIKit

final class CollageVideoCompositor: NSObject, AVVideoCompositing {

    // MARK: - Shared configuration

    private static var sharedCells: [CellConfiguration] = []
    private static let configLock = NSLock()

    static func configureShared(cells: [CellConfiguration]) {
        configLock.lock()
        sharedCells = cells
        configLock.unlock()
    }

    // MARK: - Instance state

    private var cells: [CellConfiguration] = []
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
        var output = CIImage(color: CIColor.black).cropped(to: canvasRect)

        for cell in cells {
            if let cellImage = renderCell(cell, request: request, canvasSize: renderContext.size) {
                output = cellImage.composited(over: output)
            }
        }

        output = output.cropped(to: canvasRect)
        ciContext.render(output, to: outputBuffer, bounds: canvasRect, colorSpace: CGColorSpaceCreateDeviceRGB())
        ciContext.clearCaches()
        return outputBuffer
    }

    private func renderCell(_ cell: CellConfiguration,
                            request: AVAsynchronousVideoCompositionRequest,
                            canvasSize: CGSize) -> CIImage? {
        guard let pixelBuffer = request.sourceFrame(byTrackID: cell.videoTrackID) else {
            return nil
        }
        var image = CIImage(cvPixelBuffer: pixelBuffer)

        // Y-flip + rotate + Y-flip dance to bring source pixels into Core Image's
        // bottom-up coords, with the video's metadata rotation applied.
        var rotationOnly = cell.preferredTransform
        rotationOnly.tx = 0
        rotationOnly.ty = 0

        let naturalSize = cell.naturalSize
        var flip = CGAffineTransform(scaleX: 1, y: -1)
        flip = flip.translatedBy(x: 0, y: -naturalSize.height)
        flip = flip.concatenating(rotationOnly)
        let rotatedHeight = abs(naturalSize.applying(rotationOnly).height)
        flip = flip.concatenating(CGAffineTransform(scaleX: 1, y: -1))
        flip = flip.translatedBy(x: 0, y: -rotatedHeight)
        image = image.transformed(by: flip)

        // Pan: the editor renders `.offset(x).scaleEffect(s)` so the visible shift
        // is `userOffset × userScale` in tile points. Map that fractional shift
        // into export pixels via `mediaInExport / mediaInScreen`.
        let mediaDisplay = cell.displaySize.absoluteSize()
        let screenBaseScale: CGFloat
        if cell.containerSize.width > 0, cell.containerSize.height > 0,
           mediaDisplay.width > 0, mediaDisplay.height > 0 {
            screenBaseScale = min(cell.containerSize.width / mediaDisplay.width,
                                  cell.containerSize.height / mediaDisplay.height)
        } else {
            screenBaseScale = cell.baseScale
        }
        let mediaInScreen = CGSize(width: mediaDisplay.width * screenBaseScale,
                                   height: mediaDisplay.height * screenBaseScale)
        let mediaInExport = CGSize(width: mediaDisplay.width * cell.baseScale,
                                   height: mediaDisplay.height * cell.baseScale)

        let contentX = cell.userOffset.x * cell.userScale
        let contentY = cell.userOffset.y * cell.userScale
        let panX = mediaInScreen.width  > 0 ? contentX  * (mediaInExport.width  / mediaInScreen.width)  : 0
        let panY = mediaInScreen.height > 0 ? -contentY * (mediaInExport.height / mediaInScreen.height) : 0

        // Apply scale.
        image = image.transformed(by: CGAffineTransform(scaleX: cell.finalScale, y: cell.finalScale))

        // Position so video center lands in the cell center (with pan).
        let imgCenter = CGPoint(x: image.extent.midX, y: image.extent.midY)
        let flippedCellY = canvasSize.height - cell.cellRect.origin.y - cell.cellRect.height
        let targetX = cell.cellRect.origin.x + cell.cellRect.width / 2 + panX
        let targetY = flippedCellY + cell.cellRect.height / 2 + panY
        image = image.transformed(by: CGAffineTransform(translationX: targetX - imgCenter.x,
                                                        y: targetY - imgCenter.y))

        // CRITICAL: clip to cell rect. Without this, zoomed video bleeds into
        // neighboring cells. This is the whole reason the custom compositor exists.
        let cropRect = CGRect(
            x: max(0, cell.cellRect.origin.x),
            y: max(0, min(flippedCellY, canvasSize.height - 1)),
            width: min(cell.cellRect.width, canvasSize.width),
            height: min(cell.cellRect.height, canvasSize.height)
        )
        return image.cropped(to: cropRect)
    }
}
