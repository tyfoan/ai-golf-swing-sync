import Foundation
import SwiftData

/// Local simulator review mode. No SDK customers or analytics are created.
enum ActivationPreview {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--activation-preview")
        #else
        false
        #endif
    }

    #if DEBUG
    static func seed(in container: ModelContainer) throws {
        guard isEnabled else { return }
        if ProcessInfo.processInfo.arguments.contains("--reset-activation-preview") {
            UserDefaults.standard.removeObject(forKey: "activation.freeComparedVideoID")
        }
        let context = container.mainContext
        for index in 1...2 { try addSample(index, context: context) }
        try context.save()
    }

    private static func addSample(_ index: Int, context: ModelContext) throws {
        guard let descriptor = ProSwingCatalog.all.first,
              let source = Bundle.main.url(forResource: descriptor.bundleFilename, withExtension: "mp4") else { return }
        let directory = SwingVideo.documentsDirectory.appendingPathComponent("ActivationPreview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("sample-\(index).mp4")
        if !FileManager.default.fileExists(atPath: url.path) { try FileManager.default.copyItem(at: source, to: url) }
        let video = SwingVideo(localURL: url, duration: descriptor.duration, fps: descriptor.framesPerSecond)
        video.id = UUID(uuidString: index == 1 ? "11111111-1111-4111-8111-111111111111" : "22222222-2222-4222-8222-222222222222")!
        video.hasBeenAnalyzed = true
        let marker = SwingMarker(startTime: descriptor.startTime, contactTime: descriptor.contactTime, endTime: descriptor.endTime)
        marker.video = video
        video.swings.append(marker)
        context.insert(video)
    }
    #endif
}
