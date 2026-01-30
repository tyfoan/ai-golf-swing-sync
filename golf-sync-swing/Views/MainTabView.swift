//
//  MainTabView.swift
//  golf-sync-swing
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Compare", systemImage: "square.split.2x1")
                }

            HistoryView()
                .tabItem {
                    Label("Recordings", systemImage: "list.bullet")
                }
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [SwingVideo.self, SwingMarker.self, ComparisonSession.self], inMemory: true)
}
