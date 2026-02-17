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
    @State private var showOnboarding: Bool

    private let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([
            SwingVideo.self,
            SwingMarker.self,
            ComparisonSession.self,
        ])

        if let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
        ) {
            self.sharedModelContainer = container
        } else {
            AppLogger.general.error("Persistent storage failed — falling back to in-memory")
            let fallback = try? ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            self.sharedModelContainer = fallback ?? (try! ModelContainer(
                for: Schema([]),
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            ))
            self._showDataError = State(initialValue: true)
            self._dataErrorMessage = State(initialValue: "Unable to save data permanently. Your recordings may not persist between sessions.")
        }

        self._showOnboarding = State(initialValue: !OnboardingService.shared.hasCompletedOnboarding)

        PurchaseService.shared.configure()
        VideoPathMigrationService.migrateIfNeeded(modelContainer: sharedModelContainer)
        VideoExportService.cleanupOrphanedExports()
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .alert("Data Error", isPresented: $showDataError) {
                    Button("OK") { }
                } message: {
                    Text(dataErrorMessage)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    @ViewBuilder
    private var rootView: some View {
        if showOnboarding {
            OnboardingView {
                withAnimation {
                    showOnboarding = false
                }
            }
        } else {
            MainTabView()
        }
    }
}
