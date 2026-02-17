//
//  DebugSettingsSection.swift
//  golf-sync-swing
//
//  Developer-only settings for testing onboarding, paywall,
//  subscription state, and review prompts.
//  Entirely compiled out of release builds via #if DEBUG.
//

#if DEBUG

import SwiftUI
import SwiftData
import RevenueCat

struct DebugSettingsSection: View {

    @Environment(\.modelContext) private var modelContext

    @State private var showPaywall = false
    @State private var showOnboarding = false
    @State private var confirmReset = false
    @State private var demoLoadState: DemoLoadState = .idle
    @State private var screenshotLoadState: ScreenshotDataService.LoadState = .idle

    private var purchaseService: PurchaseService { .shared }
    private var screenshotMode: ScreenshotModeService { .shared }
    private var screenshotData: ScreenshotDataService { .shared }

    var body: some View {
        screenshotModeSection
        developerSection
            .fullScreenCover(isPresented: $showPaywall) {
                AppPaywallView(source: .settings, onDismiss: { showPaywall = false })
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView { showOnboarding = false }
            }
            .confirmationDialog("Reset All Debug State", isPresented: $confirmReset) {
                Button("Reset Everything", role: .destructive) { resetAll() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This resets onboarding, review prompt counter, and expiration caches. RevenueCat state is not affected.")
            }
    }

    // MARK: - Screenshot Mode Section

    private var screenshotModeSection: some View {
        Section {
            screenshotToggleRow
            screenshotDataRow
            screenshotPreviewRow
        } header: {
            Label("Screenshot Mode", systemImage: "camera.viewfinder")
        } footer: {
            Text("Unlocks premium features and loads demo data for App Store screenshots.")
        }
        .listRowBackground(
            screenshotMode.isEnabled
                ? Color.yellow.opacity(0.08)
                : nil
        )
    }

    private var screenshotToggleRow: some View {
        Toggle(isOn: Binding(
            get: { screenshotMode.isEnabled },
            set: { _ in screenshotMode.toggle() }
        )) {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .frame(width: 20)
                Text("Screenshot Mode")
                    .font(.subheadline)
            }
        }
        .tint(.yellow)
    }

    private var screenshotDataRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            debugRow(
                icon: "photo.on.rectangle.angled",
                title: "Screenshot Data",
                detail: screenshotLoadState.label
            )

            HStack(spacing: 12) {
                screenshotActionButton("Load Demo Data", systemImage: "arrow.down.doc") {
                    Task { await loadScreenshotData() }
                }
                .disabled(screenshotLoadState.isLoading)

                screenshotActionButton("Clear All", systemImage: "trash") {
                    clearAllVideos()
                    screenshotLoadState = .idle
                }
                .disabled(screenshotLoadState.isLoading)
            }
        }
    }

    private var screenshotPreviewRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                screenshotActionButton("Onboarding", systemImage: "hand.wave") {
                    showOnboarding = true
                }
                screenshotActionButton("Paywall", systemImage: "creditcard") {
                    showPaywall = true
                }
            }
        }
    }

    private func screenshotActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Developer Section

    private var developerSection: some View {
        Section {
            onboardingRow
            paywallRow
            subscriptionStatusRow
            togglePremiumRow
            reviewPromptRow
            demoVideoRow
            resetAllRow
        } header: {
            Label("Developer", systemImage: "hammer.fill")
        } footer: {
            Text("This section is only visible in DEBUG builds.")
        }
    }

    // MARK: - Onboarding

    private var onboardingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            debugRow(
                icon: "arrow.counterclockwise",
                title: "Onboarding",
                detail: OnboardingService.shared.hasCompletedOnboarding ? "Completed" : "Not shown"
            )

            HStack(spacing: 12) {
                debugActionButton("Reset", systemImage: "arrow.counterclockwise") {
                    OnboardingService.shared.resetOnboarding()
                }
                debugActionButton("Preview", systemImage: "eye") {
                    showOnboarding = true
                }
            }
        }
    }

    // MARK: - Paywall

    private var paywallRow: some View {
        debugActionButton("Preview Paywall", systemImage: "creditcard") {
            showPaywall = true
        }
    }

    // MARK: - Subscription

    private var subscriptionStatusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            debugRow(
                icon: "crown",
                title: "Premium",
                detail: purchaseService.isPremium ? "Active" : "Inactive"
            )

            if let info = purchaseService.customerInfo {
                debugDetail("App User ID", value: info.originalAppUserId)
                debugDetail("Entitlements", value: "\(info.entitlements.active.count) active")
            } else {
                debugDetail("Customer Info", value: "Not loaded")
            }
        }
    }

    private var togglePremiumRow: some View {
        Button {
            Task { await purchaseService.refreshStatus() }
        } label: {
            debugRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Refresh Purchase Status",
                detail: nil
            )
        }
    }

    // MARK: - Review Prompt

    private var reviewPromptRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            let count = UserDefaults.standard.integer(forKey: "reviewPrompt.swingCount")
            let lastVersion = UserDefaults.standard.string(forKey: "reviewPrompt.lastVersion") ?? "never"

            debugRow(
                icon: "star.bubble",
                title: "Review Prompt",
                detail: "Swings: \(count)/3"
            )
            debugDetail("Last prompted", value: lastVersion)

            debugActionButton("Reset Counter", systemImage: "arrow.counterclockwise") {
                UserDefaults.standard.removeObject(forKey: "reviewPrompt.swingCount")
                UserDefaults.standard.removeObject(forKey: "reviewPrompt.lastVersion")
            }
        }
    }

    // MARK: - Demo Videos

    private var demoVideoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            debugRow(
                icon: "film.stack",
                title: "Demo Videos",
                detail: demoLoadState.label
            )

            debugDetail("In bundle", value: "\(DemoVideoPaths.all.count)/\(DemoVideoPaths.entries.count)")

            HStack(spacing: 12) {
                debugActionButton("Load Demo Videos", systemImage: "arrow.down.doc") {
                    Task { await loadDemoVideos() }
                }
                .disabled(demoLoadState.isLoading || DemoVideoPaths.all.isEmpty)

                debugActionButton("Clear All Videos", systemImage: "trash") {
                    clearAllVideos()
                }
                .disabled(demoLoadState.isLoading)
            }
        }
    }

    // MARK: - Reset All

    private var resetAllRow: some View {
        Button(role: .destructive) {
            confirmReset = true
        } label: {
            debugRow(
                icon: "trash",
                title: "Reset All Debug State",
                detail: nil
            )
        }
    }

    // MARK: - Actions

    private func loadScreenshotData() async {
        screenshotLoadState = .loading(0, 1)
        await screenshotData.loadScreenshotData(context: modelContext)
        screenshotLoadState = screenshotData.loadState
    }

    private func resetAll() {
        OnboardingService.shared.resetOnboarding()
        UserDefaults.standard.removeObject(forKey: "reviewPrompt.swingCount")
        UserDefaults.standard.removeObject(forKey: "reviewPrompt.lastVersion")
    }

    private func loadDemoVideos() async {
        let sources = DemoVideoPaths.all
        guard !sources.isEmpty else {
            demoLoadState = .error("No demo videos in bundle")
            return
        }

        let schedule = DemoSchedule.entries(from: sources)
        demoLoadState = .loading(0, schedule.count)

        let storage = VideoStorageService.shared
        let runner = SwingAutoDetectionRunner()
        var loaded = 0

        for entry in schedule {
            do {
                let destURL = try storage.copyVideoToStorage(from: entry.url)
                let video = await storage.createSwingVideo(from: destURL)
                video.createdAt = entry.date
                modelContext.insert(video)
                try modelContext.save()

                _ = await runner.analyze(video: video, context: modelContext)
                try modelContext.save()

                loaded += 1
                demoLoadState = .loading(loaded, schedule.count)
            } catch {
                demoLoadState = .error(error.localizedDescription)
            }
        }

        demoLoadState = .done(loaded)
    }

    private func clearAllVideos() {
        do {
            let descriptor = FetchDescriptor<SwingVideo>()
            let videos = try modelContext.fetch(descriptor)
            for video in videos {
                VideoStorageService.shared.deleteVideo(at: video.localURL)
                modelContext.delete(video)
            }
            try modelContext.save()
            demoLoadState = .idle
        } catch {
            demoLoadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Reusable Components

    private func debugRow(icon: String, title: String, detail: String?) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 20)

            Text(title)
                .font(.subheadline)

            Spacer()

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func debugDetail(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 100, alignment: .leading)
                .padding(.leading, 28)

            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func debugActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Demo Video Paths

private enum DemoVideoPaths {
    static let entries: [(name: String, ext: String)] = [
        ("demo1", "mov"), ("demo2", "mov"),
        ("demo3", "mp4"), ("demo4", "mp4"),
        ("swing1", "mp4"), ("swing2", "mov"),
        ("swing3", "mp4"), ("swing4", "mp4"),
        ("swing5", "mov"), ("swing6", "mov")
    ]

    static var all: [URL] {
        entries.compactMap { Bundle.main.url(forResource: $0.name, withExtension: $0.ext) }
    }
}

// MARK: - Demo Schedule

private enum DemoSchedule {
    struct Entry {
        let url: URL
        let date: Date
    }

    static func entries(from sources: [URL]) -> [Entry] {
        let calendar = Calendar.current
        // Feb 12, 2026 — morning and afternoon sessions
        let feb12AM = calendar.date(from: DateComponents(year: 2026, month: 2, day: 12, hour: 9, minute: 15))!
        let feb12PM = calendar.date(from: DateComponents(year: 2026, month: 2, day: 12, hour: 14, minute: 40))!
        // Feb 13, 2026 — morning and afternoon sessions
        let feb13AM = calendar.date(from: DateComponents(year: 2026, month: 2, day: 13, hour: 10, minute: 5))!
        let feb13PM = calendar.date(from: DateComponents(year: 2026, month: 2, day: 13, hour: 16, minute: 20))!

        let dates = [feb12AM, feb12PM, feb13AM, feb13PM]

        return dates.enumerated().map { index, date in
            Entry(url: sources[index % sources.count], date: date)
        }
    }
}

// MARK: - Demo Load State

private enum DemoLoadState {
    case idle
    case loading(Int, Int)
    case done(Int)
    case error(String)

    var label: String {
        switch self {
        case .idle:                    return "Not loaded"
        case .loading(let n, let t):   return "Loading \(n)/\(t)..."
        case .done(let count):         return "\(count) loaded"
        case .error(let msg):          return "Error: \(msg)"
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

#endif
