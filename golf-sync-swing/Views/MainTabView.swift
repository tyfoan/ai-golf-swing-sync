//
//  MainTabView.swift
//  golf-sync-swing
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            RecordingView()
                .tabItem {
                    Label("Camera", systemImage: "camera.fill")
                }
                .tag(AppRouter.Tab.camera)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(AppRouter.Tab.history)

            HomeView()
                .tabItem {
                    Label("Compare", systemImage: "square.split.2x1.fill")
                }
                .tag(AppRouter.Tab.compare)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(AppRouter.Tab.settings)
        }
        .tint(.appTeal)
        .onAppear { Analytics.shared.track(.mainAppReached) }
    }
}

#Preview {
    MainTabView()
        .environment(AppRouter())
        .modelContainer(for: [SwingVideo.self, SwingMarker.self, ComparisonSession.self], inMemory: true)
}
