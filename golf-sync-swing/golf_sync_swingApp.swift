//
//  golf_sync_swingApp.swift
//  golf-sync-swing
//

import SwiftUI
import SwiftData
import os

@main
struct golf_sync_swingApp: App {
    @State private var showDataError = false
    @State private var dataErrorMessage = ""

    private let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([
            SwingVideo.self,
            SwingMarker.self,
            ComparisonSession.self,
        ])

        do {
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            self.sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            AppLogger.general.error("Failed to create persistent ModelContainer: \(error.localizedDescription)")
            AppLogger.general.warning("Falling back to in-memory storage")

            do {
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                self.sharedModelContainer = try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Cannot create ModelContainer even in-memory: \(error)")
            }
        }

        VideoPathMigrationService.migrateIfNeeded(modelContainer: sharedModelContainer)
        VideoExportService.cleanupOrphanedExports()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .alert("Data Error", isPresented: $showDataError) {
                    Button("OK") { }
                } message: {
                    Text(dataErrorMessage)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
