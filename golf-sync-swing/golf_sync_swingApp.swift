//
//  golf_sync_swingApp.swift
//  golf-sync-swing
//

import os
import SwiftData
import SwiftUI

@main
struct golf_sync_swingApp: App {
    @State private var showDataError = false
    @State private var dataErrorMessage = ""
    @State private var showOnboarding: Bool

    private let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema(versionedSchema: SchemaV1.self)

        if let container = try? ModelContainer(
            for: schema,
            migrationPlan: SwingDataMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
        ) {
            self.sharedModelContainer = container
        } else {
            AppLogger.general.error("Persistent storage failed — falling back to in-memory")
            let fallbackContainer: ModelContainer
            do {
                fallbackContainer = try ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
            } catch {
                AppLogger.general.error("In-memory fallback also failed: \(error)")
                fatalError("Cannot create any ModelContainer: \(error)")
            }
            self.sharedModelContainer = fallbackContainer
            self._showDataError = State(initialValue: true)
            self._dataErrorMessage = State(initialValue: "Unable to save data permanently. Your recordings may not persist between sessions.")
        }

        self._showOnboarding = State(initialValue: !OnboardingService.shared.hasCompletedOnboarding)

        PurchaseService.shared.configure()
        VideoPathMigrationService.migrateIfNeeded(modelContainer: sharedModelContainer)
        VideoExportService.cleanupOrphanedExports()
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            rootView
                .alert("Data Error", isPresented: $showDataError) {
                    Button("OK") { }
                } message: {
                    Text(dataErrorMessage)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        VideoExportService.cleanupOrphanedExports()
                    }
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
