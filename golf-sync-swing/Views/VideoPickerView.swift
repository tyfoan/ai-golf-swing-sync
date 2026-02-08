//
//  VideoPickerView.swift
//  golf-sync-swing
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import os

struct VideoPickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onVideoPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 1
        configuration.filter = .videos

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPickerView

        init(_ parent: VideoPickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // If user cancelled, dismiss immediately
            guard let result = results.first else {
                DispatchQueue.main.async {
                    self.parent.isPresented = false
                }
                return
            }

            // Find a video type identifier
            let videoTypeIdentifiers = result.itemProvider.registeredTypeIdentifiers.filter {
                UTType($0)?.conforms(to: .movie) == true || UTType($0)?.conforms(to: .video) == true
            }

            guard let typeIdentifier = videoTypeIdentifiers.first ?? result.itemProvider.registeredTypeIdentifiers.first else {
                DispatchQueue.main.async {
                    self.parent.isPresented = false
                }
                return
            }

            result.itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, error in
                guard let self = self else { return }

                guard let url = url, error == nil else {
                    AppLogger.storage.error("Error loading video: \(error?.localizedDescription ?? "Unknown error")")
                    DispatchQueue.main.async {
                        self.parent.isPresented = false
                    }
                    return
                }

                // Copy to temp location to keep access after picker dismisses
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)

                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    DispatchQueue.main.async {
                        self.parent.onVideoPicked(tempURL)
                        self.parent.isPresented = false
                    }
                } catch {
                    AppLogger.storage.error("Error copying video: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.parent.isPresented = false
                    }
                }
            }
        }
    }
}
