//
//  golf_sync_swingApp.swift
//  golf-sync-swing
//

import SwiftUI
import SwiftData

@main
struct golf_sync_swingApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SwingVideo.self,
            SwingMarker.self,
            ComparisonSession.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}
