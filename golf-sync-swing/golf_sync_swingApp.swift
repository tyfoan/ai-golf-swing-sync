//
//  golf_sync_swingApp.swift
//  golf-sync-swing
//

import SwiftUI
import SwiftData

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
            // Try in-memory fallback so app can still launch
            print("⚠️ Failed to create persistent ModelContainer: \(error)")
            print("⚠️ Falling back to in-memory storage")

            do {
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                self.sharedModelContainer = try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                // Last resort: crash with clear message
                fatalError("Cannot create ModelContainer even in-memory: \(error)")
            }
        }
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
