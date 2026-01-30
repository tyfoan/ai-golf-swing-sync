//
//  ThumbnailService.swift
//  golf-sync-swing
//

import Foundation
import AVFoundation
import UIKit

final class ThumbnailService {
    static let shared = ThumbnailService()
    private init() {}

    private func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Generate thumbnail from video URL and return the image data
    func generateThumbnail(for url: URL) -> Data? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        guard let imageRef = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            return nil
        }

        return UIImage(cgImage: imageRef).jpegData(compressionQuality: 0.8)
    }

    /// Get UIImage from thumbnail data
    func thumbnailImage(from data: Data?) -> UIImage? {
        guard let data = data else { return nil }
        return UIImage(data: data)
    }

    /// Placeholder image when no thumbnail available
    var placeholder: UIImage {
        UIImage(systemName: "video.fill") ?? UIImage()
    }
}
