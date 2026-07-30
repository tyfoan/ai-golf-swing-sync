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
    @State private var router = AppRouter()

    private let sharedModelContainer: ModelContainer

    /// Static so it outlives `init`. MetricKit delivers diagnostics on a LATER launch, so the
    /// subscriber must stay registered for the whole process lifetime.
    private static let crashReporter = CrashDiagnosticsReporter()

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
            self._dataErrorMessage = State(initialValue: String(localized: "Unable to save data permanently. Your recordings may not persist between sessions.", comment: "Alert shown at launch when persistent SwiftData storage fails and the app falls back to in-memory storage"))
        }

        self._showOnboarding = State(initialValue: !OnboardingService.shared.hasCompletedOnboarding)

        // First line the timeline ever gets, so `t` is measured from here.
        #if DEBUG
        DeviceProbe.event("app_launched", [
            "onboarding_pending": String(!OnboardingService.shared.hasCompletedOnboarding),
            "scenario": DebugScenario.requested ?? "none"
        ])
        #endif

        Analytics.shared.configure()
        // After configure() — Analytics is a NoOp until then, so anything tracked earlier is
        // silently dropped.
        Analytics.shared.track(.appLaunched)
        Self.crashReporter.start()
        PurchaseService.shared.configure()
        VideoPathMigrationService.migrateIfNeeded(modelContainer: sharedModelContainer)

        // Keep the launch path short. Pro-swing seeding moved to the Compare tab's first
        // appearance (HomeView): on a first launch it copies 19 clips (~59 MB) and decodes
        // a thumbnail per clip, and running that during onboarding contended with the
        // camera's first bring-up on disk and mediaserverd — stretching the first-recording
        // freeze into seconds. The orphaned-export sweep stays: it only walks tmp.
        Task.detached(priority: .utility) {
            VideoExportService.cleanupOrphanedExports()
        }

        // The swing classifier's one-time CoreML specialization used to be kicked from here
        // as well. It no longer is: on device the model reported "loaded successfully" AFTER
        // the camera's `startRunning` returned 15.5 s in, so the ANE compile spent the cold
        // launch competing with the bring-up it was meant to stay clear of. It now starts
        // from `RecordingViewModel.activate()`, where it overlaps the countdown instead.
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
                // Attached to `rootView` rather than to the post-onboarding branch on
                // purpose: a scenario launched onto a device still showing onboarding must
                // record that fact and time out saying so, not vanish.
                //
                // The modifier itself is inside the `#if`, not just its body: a wrapper
                // whose body compiled away would still leave SwiftUI creating a no-op
                // `Task` on every launch of a shipping build. `begin` is a no-op unless
                // `GSS_SCENARIO` is set, so even a Debug build costs one optional read.
                #if DEBUG
                .task { DebugScenario.shared.begin(router: router) }
                #endif
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
                .environment(router)
        }
    }
}
