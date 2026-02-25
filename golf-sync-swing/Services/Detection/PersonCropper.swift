//
//  PersonCropper.swift
//  golf-sync-swing
//
//  Crops a person-centered 160x160 region from a full camera frame
//  using Vision's human body detection. Caches the last known bounding
//  box for frames where detection fails.
//

import CoreImage
import Vision

// MARK: - Protocol

protocol PersonCropping: Sendable {
    func crop(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer
}

// MARK: - Implementation

final class PersonCropper: PersonCropping {

    private let targetSize: Int
    private let padding: CGFloat
    private let ciContext = CIContext()

    /// Last successful bounding box — used when detection fails.
    private var cachedBoundingBox: CGRect?

    init(targetSize: Int = 160, padding: CGFloat = 0.20) {
        self.targetSize = targetSize
        self.padding = padding
    }

    // MARK: - Public

    func crop(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        let boundingBox = detectPerson(in: pixelBuffer) ?? cachedBoundingBox
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let cropRect = buildCropRect(boundingBox: boundingBox, imageExtent: sourceImage.extent)
        return renderCroppedBuffer(from: sourceImage, cropRect: cropRect)
    }

    // MARK: - Person Detection

    private func detectPerson(in pixelBuffer: CVPixelBuffer) -> CGRect? {
        let request = VNDetectHumanRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        try? handler.perform([request])

        guard let observation = request.results?.first else { return nil }

        cachedBoundingBox = observation.boundingBox
        return observation.boundingBox
    }

    // MARK: - Crop Geometry

    private func buildCropRect(boundingBox: CGRect?, imageExtent: CGRect) -> CGRect {
        guard let bbox = boundingBox else {
            return centerSquare(in: imageExtent)
        }

        let pixelRect = VNImageRectForNormalizedRect(bbox, Int(imageExtent.width), Int(imageExtent.height))
        return paddedSquare(from: pixelRect, within: imageExtent)
    }

    private func centerSquare(in extent: CGRect) -> CGRect {
        let side = min(extent.width, extent.height)
        let originX = (extent.width - side) / 2
        let originY = (extent.height - side) / 2
        return CGRect(x: originX, y: originY, width: side, height: side)
    }

    private func paddedSquare(from rect: CGRect, within bounds: CGRect) -> CGRect {
        let side = max(rect.width, rect.height)
        let padded = side * (1 + padding)

        let centerX = rect.midX
        let centerY = rect.midY

        let clampedX = max(bounds.minX, min(bounds.maxX - padded, centerX - padded / 2))
        let clampedY = max(bounds.minY, min(bounds.maxY - padded, centerY - padded / 2))
        let clampedSide = min(padded, min(bounds.width, bounds.height))

        return CGRect(x: clampedX, y: clampedY, width: clampedSide, height: clampedSide)
    }

    // MARK: - Rendering

    private func renderCroppedBuffer(from source: CIImage, cropRect: CGRect) -> CVPixelBuffer {
        let cropped = source
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))

        let scale = CGFloat(targetSize) / max(cropRect.width, 1)
        let scaled = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        var output: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetSize, targetSize,
            kCVPixelFormatType_32BGRA,
            nil,
            &output
        )

        guard let buffer = output else { return source.pixelBuffer ?? createBlankBuffer() }

        ciContext.render(scaled, to: buffer)
        return buffer
    }

    private func createBlankBuffer() -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, targetSize, targetSize, kCVPixelFormatType_32BGRA, nil, &buffer)
        return buffer!
    }
}
