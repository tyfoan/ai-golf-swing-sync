//
//  MainTabView.swift
//  golf-sync-swing
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordingView()
                .tabItem {
                    Label("Camera", systemImage: "camera.fill")
                }
                .tag(0)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(1)

            HomeView()
                .tabItem {
                    Label("Compare", systemImage: "square.split.2x1.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(.appTeal)
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [SwingVideo.self, SwingMarker.self, ComparisonSession.self], inMemory: true)
}
