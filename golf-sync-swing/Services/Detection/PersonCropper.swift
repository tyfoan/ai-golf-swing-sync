//
//  PersonCropper.swift
//  golf-sync-swing
//
//  Pose-based person detection and frame cropping.
//  Uses VNDetectHumanBodyPoseRequest to find the golfer's bounding box,
//  then crops and scales frames to the target size for SwingNet input.
//

import CoreImage
import Vision

protocol PersonCropping: Sendable {
    func updatePersonBounds(from pixelBuffer: CVPixelBuffer)
    func extractRGBData(from pixelBuffer: CVPixelBuffer, frameWidth: Int, frameHeight: Int) -> ContiguousArray<UInt8>?
}

final class PersonCropper: PersonCropping, @unchecked Sendable {

    private let lock = NSLock()
    private var cachedPersonBounds: CGRect?
    private var poseDetectionCounter: Int = 0
    private let poseDetectionInterval: Int = 60  // ~2x/sec at 30fps
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func updatePersonBounds(from pixelBuffer: CVPixelBuffer) {
        lock.lock()
        poseDetectionCounter += 1
        guard poseDetectionCounter >= poseDetectionInterval else {
            lock.unlock()
            return
        }
        poseDetectionCounter = 0
        lock.unlock()

        detectPersonPose(from: pixelBuffer)
    }

    func extractRGBData(from pixelBuffer: CVPixelBuffer, frameWidth: Int, frameHeight: Int) -> ContiguousArray<UInt8>? {
        updatePersonBounds(from: pixelBuffer)

        lock.lock()
        let bounds = cachedPersonBounds
        lock.unlock()

        return autoreleasepool {
            var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            if let bounds {
                let imgW = ciImage.extent.width
                let imgH = ciImage.extent.height
                let cropRect = CGRect(
                    x: bounds.origin.x * imgW,
                    y: bounds.origin.y * imgH,
                    width: bounds.width * imgW,
                    height: bounds.height * imgH
                ).integral
                ciImage = ciImage.cropped(to: cropRect)
                    .transformed(by: CGAffineTransform(
                        translationX: -cropRect.origin.x,
                        y: -cropRect.origin.y
                    ))
            }

            let scaleX = CGFloat(frameWidth) / ciImage.extent.width
            let scaleY = CGFloat(frameHeight) / ciImage.extent.height
            let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            var outputBuffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, frameWidth, frameHeight, kCVPixelFormatType_32BGRA, nil, &outputBuffer)
            guard let output = outputBuffer else { return nil }

            ciContext.render(scaled, to: output)

            CVPixelBufferLockBaseAddress(output, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(output, .readOnly) }

            guard let baseAddress = CVPixelBufferGetBaseAddress(output) else { return nil }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(output)
            let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

            let pixelCount = frameWidth * frameHeight
            var rgbData = ContiguousArray<UInt8>()
            rgbData.reserveCapacity(3 * pixelCount)

            // CHW order: R, G, B planes (BGRA source)
            for y in 0..<frameHeight {
                for x in 0..<frameWidth {
                    let offset = y * bytesPerRow + x * 4
                    rgbData.append(buffer[offset + 2])  // R
                }
            }
            for y in 0..<frameHeight {
                for x in 0..<frameWidth {
                    let offset = y * bytesPerRow + x * 4
                    rgbData.append(buffer[offset + 1])  // G
                }
            }
            for y in 0..<frameHeight {
                for x in 0..<frameWidth {
                    let offset = y * bytesPerRow + x * 4
                    rgbData.append(buffer[offset])       // B
                }
            }

            return rgbData
        }
    }

    // MARK: - Private

    private func detectPersonPose(from pixelBuffer: CVPixelBuffer) {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            lock.lock()
            cachedPersonBounds = nil
            lock.unlock()
            return
        }

        guard let observation = request.results?.first else {
            lock.lock()
            cachedPersonBounds = nil
            lock.unlock()
            return
        }

        let allPoints = observation.availableJointNames.compactMap { jointName -> CGPoint? in
            guard let point = try? observation.recognizedPoint(jointName),
                  point.confidence > 0.1 else { return nil }
            return point.location
        }

        guard allPoints.count >= 3 else {
            lock.lock()
            cachedPersonBounds = nil
            lock.unlock()
            return
        }

        let xs = allPoints.map(\.x)
        let ys = allPoints.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            lock.lock()
            cachedPersonBounds = nil
            lock.unlock()
            return
        }

        let width = maxX - minX
        let height = maxY - minY

        guard width > 0.01, height > 0.01 else {
            lock.lock()
            cachedPersonBounds = nil
            lock.unlock()
            return
        }

        let expandX = width * 0.3
        let expandY = height * 0.3

        let newBounds = CGRect(
            x: max(0, minX - expandX),
            y: max(0, minY - expandY),
            width: min(1.0 - max(0, minX - expandX), width + 2 * expandX),
            height: min(1.0 - max(0, minY - expandY), height + 2 * expandY)
        )

        lock.lock()
        cachedPersonBounds = newBounds
        lock.unlock()
    }
}
