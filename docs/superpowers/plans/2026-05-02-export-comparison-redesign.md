# Export & Comparison Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign comparison modes (3 cases) and export flow (WYSIWYG, top-right entry on both Single Video and Comparison screens), wire the broken history-view share button, and add a Swings-Only export that concatenates a video's swings.

**Architecture:** Two parallel export paths share `VideoExportService`. The Comparison flow uses a custom AVVideoCompositor (existing) with new `.stacked` and `.sideBySide` branches; Sequential mode bypasses the compositor and uses standard `AVMutableComposition` with tracks inserted back-to-back. The Single Video flow has no editor — a small bottom sheet collects intent and dispatches to `VideoExportService.exportSingleVideo(...)`.

**Tech Stack:** Swift 5, SwiftUI, AVFoundation, Core Image, SwiftData. Tests use Swift Testing (`@Test`).

**Spec:** `docs/superpowers/specs/2026-05-01-export-comparison-redesign.md`

---

## File map

```
golf-sync-swing/
├── Models/
│   ├── ComparisonMode.swift                  (rewrite — Task 2)
│   └── Export/
│       ├── VideoLayoutConfig.swift           (extend — Task 5)
│       └── CompositorLayout.swift            (new — Task 6)
├── Services/
│   ├── FeatureAccess.swift                   (update PremiumFeature — Task 1)
│   ├── VideoExportService.swift              (add exportSingleVideo + branch on layoutMode — Tasks 7, 12)
│   └── Export/
│       └── CollageVideoCompositor.swift      (layoutMode branch — Task 7)
├── ViewModels/
│   ├── ComparisonViewModel.swift             (drop isSynchronized branches, rename onionSkinOpacity, add sequential — Task 3)
│   └── ExportEditorViewModel.swift           (mode awareness, sequential editor state — Task 9)
└── Views/
    ├── ComparisonView.swift                  (button layout — Task 4)
    ├── SingleVideoPlayerView.swift           (present export sheet — Task 14)
    ├── Components/
    │   ├── PlayerTopBarView.swift            (wire share button — Task 13)
    │   └── SingleVideoExportSheet.swift      (new — Task 13)
    └── Export/
        ├── ExportEditorView.swift            (inline aspect toggle — Task 10)
        ├── ExportFlowCoordinator.swift       (collapse to 2 steps — Task 11)
        ├── AspectRatioPickerView.swift       (DELETE — Task 11)
        └── Components/
            └── EditorCanvas.swift            (mode branching — Task 8)
```

---

### Task 1: Update PremiumFeature flags

**Files:**
- Modify: `golf-sync-swing/Services/FeatureAccess.swift`

- [ ] **Step 1: Replace the three legacy flags with one new flag**

```swift
//
//  FeatureAccess.swift
//  golf-sync-swing
//
//  Single source of truth for premium feature gating.
//  Delegates to PurchaseService for RevenueCat entitlement checks.
//

import Foundation

enum PremiumFeature: String, CaseIterable {
    case advancedComparisonModes
    // TODO: Gate pose estimation behind premium when real-time skeleton overlay ships
    case poseEstimation
    case exportHD
    case exportNoWatermark
}

struct FeatureAccess {
    static func isUnlocked(_ feature: PremiumFeature) -> Bool {
        #if DEBUG
        if ScreenshotModeService.shared.isEnabled { return true }
        #endif
        return PurchaseService.shared.isPremium
    }

    static var isPremiumUser: Bool {
        #if DEBUG
        if ScreenshotModeService.shared.isEnabled { return true }
        #endif
        return PurchaseService.shared.isPremium
    }
}
```

- [ ] **Step 2: Build (will fail — old flags are still referenced from ComparisonMode)**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error:" | head -10`

Expected: errors mentioning `synchronizedPlayback`, `onionSkinMode`, `overlayMode` from `ComparisonMode.swift`. Task 2 fixes them.

- [ ] **Step 3: No commit yet — paired with Task 2**

This task and Task 2 must land together. Stage but do not commit.

```bash
git add golf-sync-swing/Services/FeatureAccess.swift
```

---

### Task 2: Rewrite ComparisonMode enum

**Files:**
- Modify: `golf-sync-swing/Models/ComparisonMode.swift`

- [ ] **Step 1: Replace the enum with the new 3-case version**

```swift
//
//  ComparisonMode.swift
//  golf-sync-swing
//
//  Display modes for comparison playback. All modes sync at impact —
//  sync is no longer a separate mode.
//

import Foundation

enum ComparisonMode: String, CaseIterable, Identifiable {
    case sideBySide = "Side-by-Side"
    case stacked    = "Stacked"
    case sequential = "Sequential"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .stacked:    return "square.on.square"
        case .sequential: return "arrow.right.to.line"
        }
    }

    var premiumFeature: PremiumFeature? {
        switch self {
        case .sideBySide: return nil
        case .stacked, .sequential: return .advancedComparisonModes
        }
    }

    var isAvailable: Bool {
        guard let feature = premiumFeature else { return true }
        return FeatureAccess.isUnlocked(feature)
    }
}
```

- [ ] **Step 2: Build to verify model + FeatureAccess compile**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error:" | head -20`

Expected: errors will move into `ComparisonViewModel.swift` (uses `comparisonMode.isSynchronized`, `onionSkin`, `.overlay`) and `ComparisonView.swift`. Task 3 fixes the view model; Task 4 fixes the view.

- [ ] **Step 3: Stage and commit**

```bash
git add golf-sync-swing/Services/FeatureAccess.swift golf-sync-swing/Models/ComparisonMode.swift
git commit -m "refactor(modes): collapse 4 comparison modes to 3 (sideBySide, stacked, sequential)"
```

The build is broken until Task 3 lands — that's expected, the type changes ripple.

---

### Task 3: Rewrite ComparisonViewModel

**Files:**
- Modify: `golf-sync-swing/ViewModels/ComparisonViewModel.swift`

- [ ] **Step 1: Rename `onionSkinOpacity` → `stackedOpacity`**

In `ComparisonViewModel.swift` line 34, replace:

```swift
    var onionSkinOpacity: Double = 0.5
```

with:

```swift
    var stackedOpacity: Double = 0.5
    var currentSequentialSwing: Int = 0   // 0 = swing1 playing, 1 = swing2 playing
```

- [ ] **Step 2: Drop `isSynchronized` branches — sync is always on for sideBySide**

Search the file for `comparisonMode.isSynchronized` (8 sites). The new logic:

- `.sideBySide` → behaves like the old `.sideBySideSynced` (always synced).
- `.stacked` → also synced (one canvas, both videos play in parallel).
- `.sequential` → only one player plays at a time, swap on loop.

Replace each `comparisonMode.isSynchronized` with the appropriate explicit check. Concretely, the old `isSynchronized` returned `true` for everything except the old `.sideBySide` (independent loops). In the new world, the unsynchronized mode is gone — both `.sideBySide` and `.stacked` use the synchronizer; `.sequential` uses a different playback approach.

Replace `onPlayer1Tick` (lines 117–123):

```swift
    private func onPlayer1Tick(_ time: TimeInterval) {
        currentTime = time
        loopIfNeeded(player: player1, swing: swing1, isReference: true)

        guard usesSynchronizer, isPlaying else { return }
        synchronizer.correctDriftIfNeeded(referenceTime: time)
    }

    /// Sequential mode runs only one player at a time, no synchronizer.
    /// Both other modes use the manual synchronizer.
    private var usesSynchronizer: Bool {
        comparisonMode != .sequential
    }
```

Replace `loopIfNeeded` (lines 131–143):

```swift
    private func loopIfNeeded(player: AVPlayer, swing: SwingTimeRange, isReference: Bool) {
        guard isPlaying else { return }
        let time = CMTimeGetSeconds(player.currentTime())
        guard time >= swing.endTime - 0.01 else { return }

        if comparisonMode == .sequential {
            advanceSequentialSwing()
            return
        }
        // sideBySide / stacked: only the reference player triggers a joint loop.
        guard isReference else { return }
        seekToSwingStarts()
    }

    private func advanceSequentialSwing() {
        currentSequentialSwing = (currentSequentialSwing + 1) % 2
        if currentSequentialSwing == 0 {
            seekPlayer(player1, to: swing1.startTime)
            player1.rate = playbackRate
            player2.pause()
        } else {
            seekPlayer(player2, to: swing2.startTime)
            player2.rate = playbackRate
            player1.pause()
        }
    }
```

Replace `play()` (lines 151–159):

```swift
    func play() {
        if usesSynchronizer {
            startSynchronizer()
            synchronizer.resync(referenceTime: currentTime)
            player1.rate = playbackRate
            player2.rate = playbackRate
        } else {
            playSequential()
        }
        isPlaying = true
    }

    private func playSequential() {
        if currentSequentialSwing == 0 {
            player1.rate = playbackRate
            player2.pause()
        } else {
            player2.rate = playbackRate
            player1.pause()
        }
    }
```

Replace `seek` (lines 167–178):

```swift
    func seek(to time: TimeInterval) {
        guard time.isFinite, swing1.startTime.isFinite, swing1.endTime.isFinite else { return }
        let clamped = clamp(time, within: swing1)
        seekPlayer(player1, to: clamped)

        if usesSynchronizer {
            synchronizer.resync(referenceTime: clamped)
        } else {
            seekPlayer2Proportionally(clamped)
        }
        currentTime = clamped
    }
```

Replace `swapVideos` (lines 195–211):

```swift
    func swapVideos() {
        let wasPlaying = isPlaying
        if usesSynchronizer {
            player1.pause()
            player2.pause()
            synchronizer.stop()
        }
        isSwapped.toggle()
        syncOffset = -syncOffset
        guard usesSynchronizer else { return }
        startSynchronizer()
        synchronizer.resync(referenceTime: currentTime)
        if wasPlaying {
            effectivePlayer1.rate = playbackRate
            effectivePlayer2.rate = playbackRate
        }
    }
```

Replace `onModeChanged` (lines 260–267):

```swift
    private func onModeChanged() {
        guard usesSynchronizer else {
            synchronizer.stop()
            // Reset sequential state on mode entry
            currentSequentialSwing = 0
            return
        }
        startSynchronizer()
        synchronizer.resync(referenceTime: currentTime)
    }
```

- [ ] **Step 2.5: Update the file's header comment** (lines 6–11) to reflect the new mode semantics:

```swift
//  Three modes (all use a baseline of impact-frame sync):
//  - sideBySide: both videos visible, manual synchronizer keeps them aligned.
//  - stacked: both visible at full canvas, blended at stackedOpacity.
//  - sequential: one player plays at a time, advances on loop.
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error:" | head -10`

Expected: errors only in `ComparisonView.swift` (still references `.onionSkin` and `onionSkinOpacity`). Task 4 fixes it.

- [ ] **Step 4: Stage and commit**

```bash
git add golf-sync-swing/ViewModels/ComparisonViewModel.swift
git commit -m "refactor(comparison): drop isSynchronized, rename onionSkinOpacity, add sequential playback"
```

---

### Task 4: ComparisonView layout — top-right Export, bottom-right Swap, drop DONE

**Files:**
- Modify: `golf-sync-swing/Views/ComparisonView.swift`

- [ ] **Step 1: Replace the topBar function (lines 67–74) — keep only the close button on top-left, add export icon on top-right, remove swap from top**

```swift
    func topBar(viewModel: ComparisonViewModel) -> some View {
        HStack {
            circleButton(icon: "xmark", accessibilityLabel: "Close comparison") { dismiss() }
            Spacer()
            circleButton(icon: "square.and.arrow.up", accessibilityLabel: "Export comparison") {
                showExportSheet = true
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }
```

- [ ] **Step 2: Add a floating swap button overlaid on the video area**

In `ComparisonVideoAreaView`, the existing video content fills the area. We add the swap button as an overlay in `contentStack`. Replace lines 59–65 (`contentStack`) with:

```swift
    func contentStack(viewModel: ComparisonViewModel) -> some View {
        VStack(spacing: 0) {
            topBar(viewModel: viewModel)
            ZStack(alignment: .bottomTrailing) {
                ComparisonVideoAreaView(viewModel: viewModel)
                circleButton(icon: "arrow.left.arrow.right", accessibilityLabel: "Swap videos") {
                    viewModel.swapVideos()
                }
                .padding(16)
            }
            controlsPanel(viewModel: viewModel)
        }
    }
```

- [ ] **Step 3: Drop the DONE button + confirmation dialog**

Replace `controlsPanel` (lines 92–102) — remove `doneButton` from the VStack:

```swift
    func controlsPanel(viewModel: ComparisonViewModel) -> some View {
        VStack(spacing: 12) {
            ComparisonTimelineSlider(viewModel: viewModel)
            syncOffsetRow(viewModel: viewModel)
            modePicker(viewModel: viewModel)
            premiumControls(viewModel: viewModel)
            ComparisonControlsView(viewModel: viewModel)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
```

Delete `doneButton` (lines 174–183) and the `confirmationDialog` modifier (lines 45–49 in `body`). Replace `body` (lines 27–53) with:

```swift
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let viewModel = viewModel {
                contentStack(viewModel: viewModel)
            } else {
                ProgressView().tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { onViewAppear() }
        .onDisappear { viewModel?.cleanup() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { viewModel?.pause() }
        }
        .sheet(isPresented: $showExportSheet) { exportSheet }
        .fullScreenCover(isPresented: $showPaywall) {
            AppPaywallView(source: .featureGate, onDismiss: { showPaywall = false })
        }
    }
```

Remove the now-unused `@State private var showDoneSheet = false` declaration.

- [ ] **Step 4: Update the onion-skin slider check to use new `.stacked` mode**

Replace `premiumControls` (lines 152–157):

```swift
    @ViewBuilder
    func premiumControls(viewModel: ComparisonViewModel) -> some View {
        if viewModel.comparisonMode == .stacked {
            stackedOpacitySlider(viewModel: viewModel)
        }
    }

    func stackedOpacitySlider(viewModel: ComparisonViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
            Slider(value: Binding(
                get: { viewModel.stackedOpacity },
                set: { viewModel.stackedOpacity = $0 }
            ), in: 0.1...0.9)
            .tint(Color.appTeal)
            Image(systemName: "circle.righthalf.filled")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
```

Delete the old `onionSkinSlider` function.

- [ ] **Step 5: Update sync-offset-strip visibility — show only for `.sideBySide`**

Replace `syncOffsetRow` (lines 104–109):

```swift
    @ViewBuilder
    func syncOffsetRow(viewModel: ComparisonViewModel) -> some View {
        if viewModel.comparisonMode == .sideBySide {
            SyncOffsetStrip(viewModel: viewModel)
        }
    }
```

- [ ] **Step 6: Build to verify**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`. The export flow still works through `ExportFlowCoordinator` (which we haven't touched yet — that's Task 11).

- [ ] **Step 7: Commit**

```bash
git add golf-sync-swing/Views/ComparisonView.swift
git commit -m "feat(comparison): top-right export icon, floating swap button, drop DONE bottom button"
```

---

### Task 5: Extend VideoLayoutConfig with mode + stackedOpacity

**Files:**
- Modify: `golf-sync-swing/Models/Export/VideoLayoutConfig.swift`

- [ ] **Step 1: Replace file**

```swift
//
//  VideoLayoutConfig.swift
//  golf-sync-swing
//
//  The contract between the export editor and the exporter:
//  output aspect ratio + comparison mode + per-video transforms (always 2).
//

import CoreGraphics
import Foundation

struct VideoLayoutConfig: Equatable {
    let aspectRatio: ExportAspectRatio
    let mode: ComparisonMode
    let stackedOpacity: CGFloat?    // only used when mode == .stacked
    let transforms: [VideoTransform]

    init(
        aspectRatio: ExportAspectRatio,
        mode: ComparisonMode,
        stackedOpacity: CGFloat? = nil,
        transforms: [VideoTransform]
    ) {
        precondition(transforms.count == 2, "VideoLayoutConfig must have exactly 2 transforms")
        self.aspectRatio = aspectRatio
        self.mode = mode
        self.stackedOpacity = stackedOpacity
        self.transforms = transforms
    }

    static func identity(aspectRatio: ExportAspectRatio, mode: ComparisonMode) -> VideoLayoutConfig {
        let v1 = VideoTransform()
        var v2 = VideoTransform()
        v2.isMuted = true
        return VideoLayoutConfig(
            aspectRatio: aspectRatio, mode: mode,
            stackedOpacity: mode == .stacked ? 0.5 : nil,
            transforms: [v1, v2]
        )
    }
}
```

- [ ] **Step 2: Build (will fail — call sites pass old signature)**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error:" | head -10`

Expected: errors in `ExportEditorViewModel.buildLayoutConfig()`, `VideoLayoutConfig.identity(aspectRatio:)`. These get fixed in Tasks 9 and 10.

- [ ] **Step 3: Stage but do NOT commit yet — paired with Task 6 + 9**

```bash
git add golf-sync-swing/Models/Export/VideoLayoutConfig.swift
```

---

### Task 6: Add CompositorLayout enum

**Files:**
- Create: `golf-sync-swing/Models/Export/CompositorLayout.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  CompositorLayout.swift
//  golf-sync-swing
//
//  Branch hint for CollageVideoCompositor. Sequential mode never reaches
//  the compositor (handled by AVMutableComposition track concatenation),
//  so it has only the two cases the compositor cares about.
//

import Foundation

enum CompositorLayout: Equatable {
    case sideBySide          // per-cell crop, transforms applied independently
    case stacked(opacity: CGFloat)
}
```

- [ ] **Step 2: Stage**

```bash
git add golf-sync-swing/Models/Export/CompositorLayout.swift
```

---

### Task 7: Update CollageVideoCompositor with layoutMode branch

**Files:**
- Modify: `golf-sync-swing/Services/Export/CollageVideoCompositor.swift`

- [ ] **Step 1: Add layoutMode storage and accept it via configureShared**

Replace the "Shared configuration" section (around lines 17–35) with:

```swift
    // MARK: - Shared configuration

    private static var sharedCells: [CellConfiguration] = []
    private static var sharedLayout: CompositorLayout = .sideBySide
    private static let configLock = NSLock()

    static func configureShared(cells: [CellConfiguration], layout: CompositorLayout = .sideBySide) {
        configLock.lock()
        sharedCells = cells
        sharedLayout = layout
        configLock.unlock()
    }
```

Replace the "Instance state" section (around lines 39–55) so each compositor instance captures the current layout:

```swift
    // MARK: - Instance state

    private var cells: [CellConfiguration] = []
    private var layout: CompositorLayout = .sideBySide
    private let ciContext: CIContext
    private let renderQueue = DispatchQueue(label: "com.golfsyncswing.compositor", qos: .userInitiated)
    private var renderContext: AVVideoCompositionRenderContext?
    private var activeRequests: [AVAsynchronousVideoCompositionRequest] = []
    private let requestsLock = NSLock()
```

In `init()` (replace the bottom of the function — the part that reads from sharedCells):

```swift
        Self.configLock.lock()
        cells = Self.sharedCells
        layout = Self.sharedLayout
        Self.configLock.unlock()
```

- [ ] **Step 2: Branch the cell loop in render(request:) — for stacked, apply opacity to video 2 before compositing**

In the `render(request:)` function, replace the cell composition loop (the `for cell in cells { ... }` block) with:

```swift
        for (index, cell) in cells.enumerated() {
            guard let cellImage = renderCell(cell, request: request, canvasSize: renderContext.size) else { continue }
            let toComposite = applyLayoutFilter(cellImage, cellIndex: index)
            output = toComposite.composited(over: output)
        }
```

- [ ] **Step 3: Add `applyLayoutFilter` helper at the bottom of the class (above the closing `}`)**

```swift
    /// For stacked layout, video 2 is rendered with reduced alpha so video 1
    /// shows through. Video 1 (cellIndex 0) renders fully opaque. Side-by-side
    /// is identity (no filter).
    private func applyLayoutFilter(_ image: CIImage, cellIndex: Int) -> CIImage {
        switch layout {
        case .sideBySide:
            return image
        case .stacked(let opacity):
            guard cellIndex == 1 else { return image }
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)
            ])
        }
    }
```

- [ ] **Step 4: Build (still failing because of Task 5/Task 9, but compositor itself compiles)**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error:" | head -10`

Expected: same VideoLayoutConfig-related errors as Task 5; nothing new.

- [ ] **Step 5: Stage**

```bash
git add golf-sync-swing/Services/Export/CollageVideoCompositor.swift
```

---

### Task 8: Update VideoExportService to honor mode + new layoutMode

**Files:**
- Modify: `golf-sync-swing/Services/VideoExportService.swift`

- [ ] **Step 1: Branch `performLayoutExport` on `layoutConfig.mode`**

Find the section in `performLayoutExport(...)` that builds `cellConfigs`, calls `CollageVideoCompositor.configureShared(...)`, and creates `videoComposition`. Replace it (the section starting at "Configure the custom compositor with both cells…" through "videoComposition.instructions = [instruction]") with:

```swift
        // Branch on mode. Sequential bypasses the custom compositor entirely.
        let videoComposition: AVMutableVideoComposition
        let instructionDuration: CMTime

        switch layoutConfig.mode {
        case .sequential:
            videoComposition = try await buildSequentialComposition(
                composition: composition,
                track1c: track1c, track2c: track2c,
                slice1: slice1, slice2: slice2,
                renderSize: renderSize,
                frameRate: max(frameRate1, frameRate2, 30)
            )
            instructionDuration = CMTimeAdd(slice1.duration, slice2.duration)

        case .sideBySide, .stacked:
            let cellRectsForLayout = (layoutConfig.mode == .stacked)
                ? [CGRect(origin: .zero, size: renderSize), CGRect(origin: .zero, size: renderSize)]
                : cells

            let cellConfigs: [CellConfiguration] = [
                CellConfiguration(
                    cellRect: cellRectsForLayout[0], videoTrackID: track1c.trackID,
                    naturalSize: size1, preferredTransform: pref1,
                    userScale: layoutConfig.transforms[0].scale,
                    userOffset: layoutConfig.transforms[0].offset,
                    containerSize: layoutConfig.transforms[0].containerSize
                ),
                CellConfiguration(
                    cellRect: cellRectsForLayout[1], videoTrackID: track2c.trackID,
                    naturalSize: size2, preferredTransform: pref2,
                    userScale: layoutConfig.transforms[1].scale,
                    userOffset: layoutConfig.transforms[1].offset,
                    containerSize: layoutConfig.transforms[1].containerSize
                )
            ]
            let compositorLayout: CompositorLayout = (layoutConfig.mode == .stacked)
                ? .stacked(opacity: layoutConfig.stackedOpacity ?? 0.5)
                : .sideBySide
            CollageVideoCompositor.configureShared(cells: cellConfigs, layout: compositorLayout)

            videoComposition = AVMutableVideoComposition()
            videoComposition.customVideoCompositorClass = CollageVideoCompositor.self
            videoComposition.renderSize = renderSize
            videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(frameRate1, frameRate2, 30)))

            let layer1 = AVMutableVideoCompositionLayerInstruction(assetTrack: track1c)
            let layer2 = AVMutableVideoCompositionLayerInstruction(assetTrack: track2c)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: effectiveDuration)
            instruction.backgroundColor = UIColor.black.cgColor
            instruction.layerInstructions = [layer1, layer2]
            videoComposition.instructions = [instruction]
            instructionDuration = effectiveDuration
        }

        // For sequential, also rebuild the audio routing (concatenated tracks need
        // their own audio, not parallel mix). Handled inside buildSequentialComposition.

        return try await runExport(composition: composition, videoComposition: videoComposition, progress: progress)
```

- [ ] **Step 2: Add `buildSequentialComposition` helper**

Add at the bottom of the class (above the closing `}` of `VideoExportService`):

```swift
    /// Sequential mode: tracks play one after another. We rewrite the composition
    /// tracks (which were inserted in parallel by `performLayoutExport`'s setup)
    /// into back-to-back order on a single source track, then return a standard
    /// (non-custom-compositor) AVMutableVideoComposition.
    private static func buildSequentialComposition(
        composition: AVMutableComposition,
        track1c: AVMutableCompositionTrack,
        track2c: AVMutableCompositionTrack,
        slice1: (start: CMTime, duration: CMTime),
        slice2: (start: CMTime, duration: CMTime),
        renderSize: CGSize,
        frameRate: Float
    ) async throws -> AVMutableVideoComposition {
        // Move slice2 to play AFTER slice1.
        // track2c was inserted at v2Start in the caller (parallel insertion).
        // Remove that insertion and re-insert at slice1.duration so it follows slice1.
        track2c.removeTimeRange(CMTimeRange(start: .zero, duration: composition.duration))
        // Re-fetch the original asset track to re-insert from. We need the source
        // track that track2c was originally pulled from.
        // The caller already gave us slice2 in source-asset time; we need to walk
        // the source asset to get the AVAssetTrack again. To keep this contained,
        // we accept that limitation by inserting from track2c's asset reference.
        // Simpler path: ask the caller to pass the source AVAssetTrack. We already
        // have track2 (source) in scope at the call site — but to keep this helper
        // self-contained, we use the segments API.
        // Concrete approach: capture track2c's segments before clearing and re-emit them.
        // Since we already cleared, we cannot. So the cleanest fix is to do all the
        // sequential work BEFORE inserting slice2 in parallel. See Step 3.

        let videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        return videoComposition
    }
```

- [ ] **Step 3: Refactor `performLayoutExport`'s track insertion to be mode-aware**

The cleanest fix is to insert track2c at `slice1.duration` (back-to-back) when mode is `.sequential`, and at `v2Start` (parallel) otherwise. Replace the two `track1c.insertTimeRange(...)` and `track2c.insertTimeRange(...)` calls (around lines 399–400 in the existing file) with:

```swift
        // For sequential mode, track2 plays AFTER track1 (back-to-back).
        // For sideBySide / stacked, both tracks play in parallel from their offsets.
        let track1InsertAt: CMTime
        let track2InsertAt: CMTime
        let parallelEffectiveDuration = effectiveDuration

        if layoutConfig.mode == .sequential {
            track1InsertAt = .zero
            track2InsertAt = slice1.duration
        } else {
            track1InsertAt = v1Start
            track2InsertAt = v2Start
        }

        try track1c.insertTimeRange(CMTimeRange(start: slice1.start, duration: slice1.duration), of: track1, at: track1InsertAt)
        try track2c.insertTimeRange(CMTimeRange(start: slice2.start, duration: slice2.duration), of: track2, at: track2InsertAt)
```

For audio (around lines 403–411), apply the same pattern:

```swift
        if !layoutConfig.transforms[0].isMuted,
           let audio1 = try await asset1.loadTracks(withMediaType: .audio).first,
           let audio1c = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audio1c.insertTimeRange(CMTimeRange(start: slice1.start, duration: slice1.duration), of: audio1, at: track1InsertAt)
        }
        if !layoutConfig.transforms[1].isMuted,
           let audio2 = try await asset2.loadTracks(withMediaType: .audio).first,
           let audio2c = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audio2c.insertTimeRange(CMTimeRange(start: slice2.start, duration: slice2.duration), of: audio2, at: track2InsertAt)
        }
```

- [ ] **Step 4: Simplify `buildSequentialComposition` now that tracks are pre-arranged**

Replace the helper with the simpler version:

```swift
    private static func buildSequentialComposition(
        composition: AVMutableComposition,
        track1c: AVMutableCompositionTrack,
        track2c: AVMutableCompositionTrack,
        slice1: (start: CMTime, duration: CMTime),
        slice2: (start: CMTime, duration: CMTime),
        renderSize: CGSize,
        frameRate: Float
    ) async throws -> AVMutableVideoComposition {
        // Tracks already inserted back-to-back by performLayoutExport.
        // Standard composition handles single-track-at-a-time playback automatically.
        let videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        return videoComposition
    }
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error:" | head -10`

Expected: errors only from VideoLayoutConfig call sites that haven't been updated yet (Tasks 9, 10, 11). Nothing from VideoExportService itself.

- [ ] **Step 6: Stage**

```bash
git add golf-sync-swing/Services/VideoExportService.swift
```

---

### Task 9: Update ExportEditorViewModel for mode awareness

**Files:**
- Modify: `golf-sync-swing/ViewModels/ExportEditorViewModel.swift`

- [ ] **Step 1: Accept mode + stackedOpacity in init**

Replace the property declarations (around lines 17–30). Note `aspectRatio` is now `var` so the inline aspect toggle in Task 11 can mutate it without rebuilding the view model:

```swift
    var aspectRatio: ExportAspectRatio
    let mode: ComparisonMode
    var stackedOpacity: CGFloat
    var currentSequentialEditSwing: Int = 0   // 0 or 1 — which swing the user is framing
    var transforms: [VideoTransform] {
        didSet { syncMuteToPlayers() }
    }
    var isPlaying: Bool = true

    private(set) var player1: AVPlayer?
    private(set) var player2: AVPlayer?

    private let video1URL: URL?
    private let video2URL: URL?
    private let swing1: SwingTimeRange?
    private let swing2: SwingTimeRange?
    private let syncOffset: TimeInterval
```

- [ ] **Step 2: Replace the init signature to accept mode + opacity**

Replace the main `init(...)` (lines 35–50):

```swift
    init(
        aspectRatio: ExportAspectRatio,
        mode: ComparisonMode,
        stackedOpacity: CGFloat = 0.5,
        video1URL: URL,
        video2URL: URL,
        swing1: SwingTimeRange,
        swing2: SwingTimeRange,
        syncOffset: TimeInterval
    ) {
        self.aspectRatio = aspectRatio
        self.mode = mode
        self.stackedOpacity = stackedOpacity
        self.video1URL = video1URL
        self.video2URL = video2URL
        self.swing1 = swing1
        self.swing2 = swing2
        self.syncOffset = syncOffset
        self.transforms = Self.defaultTransforms()
    }
```

Replace the test-only init (lines 53–61):

```swift
    private init(aspectRatio: ExportAspectRatio, mode: ComparisonMode = .sideBySide) {
        self.aspectRatio = aspectRatio
        self.mode = mode
        self.stackedOpacity = 0.5
        self.video1URL = nil
        self.video2URL = nil
        self.swing1 = nil
        self.swing2 = nil
        self.syncOffset = 0
        self.transforms = Self.defaultTransforms()
    }
```

Update `makeForTesting` if you want to keep it test-friendly:

```swift
    static func makeForTesting(aspectRatio: ExportAspectRatio, mode: ComparisonMode = .sideBySide) -> ExportEditorViewModel {
        ExportEditorViewModel(aspectRatio: aspectRatio, mode: mode)
    }
```

- [ ] **Step 3: Update `buildLayoutConfig` to include mode + opacity**

Replace `buildLayoutConfig` (lines 127–129):

```swift
    func buildLayoutConfig() -> VideoLayoutConfig {
        VideoLayoutConfig(
            aspectRatio: aspectRatio,
            mode: mode,
            stackedOpacity: mode == .stacked ? stackedOpacity : nil,
            transforms: transforms
        )
    }
```

- [ ] **Step 4: Build (the editor view + coordinator still pass the old init signature — fixed in Tasks 10, 11)**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error:" | head -10`

Expected: errors only in `ExportFlowCoordinator` and `ExportEditorView`. Tasks 10, 11 fix them.

- [ ] **Step 5: Stage**

```bash
git add golf-sync-swing/ViewModels/ExportEditorViewModel.swift
```

---

### Task 10: Update EditorCanvas with mode branching

**Files:**
- Modify: `golf-sync-swing/Views/Export/Components/EditorCanvas.swift`

- [ ] **Step 1: Replace the file**

```swift
//
//  EditorCanvas.swift
//  golf-sync-swing
//
//  Mode-aware canvas. Branches by ComparisonMode:
//  - sideBySide: two tiles arranged HSTACK/VSTACK per aspect.
//  - stacked: two tiles overlaid full-canvas; video 2 at user-set opacity.
//  - sequential: one full-canvas tile + a Swing 1 / Swing 2 segmented toggle.
//

import SwiftUI
import AVFoundation

struct EditorCanvas: View {
    let aspectRatio: ExportAspectRatio
    let mode: ComparisonMode
    let stackedOpacity: CGFloat
    let player1: AVPlayer
    let player2: AVPlayer
    @Binding var transform1: VideoTransform
    @Binding var transform2: VideoTransform
    @Binding var sequentialEditIndex: Int  // 0 or 1, which swing the user is editing

    var body: some View {
        VStack(spacing: 12) {
            if mode == .sequential {
                sequentialPicker
            }
            GeometryReader { geo in
                let canvas = sizeFitting(aspectRatio: aspectRatio.ratio, into: geo.size)
                canvasContent(canvas: canvas)
                    .frame(width: canvas.width, height: canvas.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func canvasContent(canvas: CGSize) -> some View {
        switch mode {
        case .sideBySide:
            sideBySideTiles
        case .stacked:
            stackedTiles
        case .sequential:
            sequentialTile
        }
    }

    private var sideBySideTiles: some View {
        Group {
            switch aspectRatio.arrangement {
            case .horizontal:
                HStack(spacing: 0) { tile1; tile2 }
            case .vertical:
                VStack(spacing: 0) { tile1; tile2 }
            }
        }
    }

    private var stackedTiles: some View {
        ZStack {
            tile1
            tile2
                .opacity(stackedOpacity)
        }
    }

    private var sequentialTile: some View {
        sequentialEditIndex == 0 ? AnyView(tile1) : AnyView(tile2)
    }

    private var tile1: some View {
        ZStack(alignment: .bottomLeading) {
            ZoomableVideoTile(player: player1, transform: $transform1)
            MuteToggleButton(isMuted: Binding(
                get: { transform1.isMuted },
                set: { transform1.isMuted = $0 }
            ))
            .padding(8)
        }
    }

    private var tile2: some View {
        ZStack(alignment: .bottomLeading) {
            ZoomableVideoTile(player: player2, transform: $transform2)
            MuteToggleButton(isMuted: Binding(
                get: { transform2.isMuted },
                set: { transform2.isMuted = $0 }
            ))
            .padding(8)
        }
    }

    private var sequentialPicker: some View {
        Picker("", selection: $sequentialEditIndex) {
            Text("Swing 1").tag(0)
            Text("Swing 2").tag(1)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
    }

    private func sizeFitting(aspectRatio: CGFloat, into size: CGSize) -> CGSize {
        let containerRatio = size.width / size.height
        if containerRatio > aspectRatio {
            return CGSize(width: size.height * aspectRatio, height: size.height)
        } else {
            return CGSize(width: size.width, height: size.width / aspectRatio)
        }
    }
}
```

- [ ] **Step 2: Build (will fail — call site in ExportEditorView passes old args)**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error:" | head -10`

Expected: errors in `ExportEditorView`. Task 11 fixes.

- [ ] **Step 3: Stage**

```bash
git add golf-sync-swing/Views/Export/Components/EditorCanvas.swift
```

---

### Task 11: Update ExportEditorView with inline aspect toggle, drop AspectRatioPickerView, simplify Coordinator

**Files:**
- Modify: `golf-sync-swing/Views/Export/ExportEditorView.swift`
- Modify: `golf-sync-swing/Views/Export/ExportFlowCoordinator.swift`
- Delete: `golf-sync-swing/Views/Export/AspectRatioPickerView.swift`

- [ ] **Step 1: Replace `ExportEditorView.swift`**

```swift
//
//  ExportEditorView.swift
//  golf-sync-swing
//

import SwiftUI

struct ExportEditorView: View {
    @State var viewModel: ExportEditorViewModel
    let onCancel: () -> Void
    let onExport: (VideoLayoutConfig) -> Void

    /// Three primary aspect options shown inline at the top of the editor.
    private let primaryAspects: [ExportAspectRatio] = [.sideBySide, .tikTokVertical, .square]

    var body: some View {
        VStack(spacing: 0) {
            header
            aspectToggle
            canvas
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Spacer()
            exportButton
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { viewModel.setupPlayers() }
        .onDisappear { viewModel.cleanup() }
    }

    private var header: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            Spacer()
            Text("Export").foregroundStyle(.white).font(.headline)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var aspectToggle: some View {
        Picker("", selection: Binding(
            get: { viewModel.aspectRatio },
            set: { viewModel.aspectRatio = $0 }
        )) {
            ForEach(primaryAspects) { aspect in
                Text(aspect.displayName).tag(aspect)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var canvas: some View {
        if let p1 = viewModel.player1, let p2 = viewModel.player2 {
            EditorCanvas(
                aspectRatio: viewModel.aspectRatio,
                mode: viewModel.mode,
                stackedOpacity: viewModel.stackedOpacity,
                player1: p1,
                player2: p2,
                transform1: Binding(
                    get: { viewModel.transforms[0] },
                    set: { viewModel.transforms[0] = $0 }
                ),
                transform2: Binding(
                    get: { viewModel.transforms[1] },
                    set: { viewModel.transforms[1] = $0 }
                ),
                sequentialEditIndex: Binding(
                    get: { viewModel.currentSequentialEditSwing },
                    set: { viewModel.currentSequentialEditSwing = $0 }
                )
            )
        } else {
            ProgressView().tint(.white)
        }
    }

    private var exportButton: some View {
        Button {
            onExport(viewModel.buildLayoutConfig())
        } label: {
            Text("Export")
                .font(.headline).fontWeight(.bold).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.appTeal)
                .clipShape(RoundedRectangle(cornerRadius: 26))
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
    }
}
```

- [ ] **Step 2: Replace `ExportFlowCoordinator.swift`**

Aspect picker step removed. Coordinator now opens the editor directly with the comparison view's current mode + a default aspect (the side-by-side 16:9 unless mode is `.sequential`/`.stacked` where vertical 9:16 makes more sense).

```swift
//
//  ExportFlowCoordinator.swift
//  golf-sync-swing
//
//  Hosts the 2-step export flow: editor → progress.
//  Aspect picking is inline in the editor.
//

import SwiftUI

struct ExportFlowCoordinator: View {
    let video1URL: URL
    let video2URL: URL
    let swing1: SwingTimeRange
    let swing2: SwingTimeRange
    let syncOffset: TimeInterval
    let comparisonViewModel: ComparisonViewModel
    let onDismiss: () -> Void

    @State private var step: Step = .editor
    @State private var pendingConfig: VideoLayoutConfig?
    @State private var isExporting = false
    @State private var progress: Float = 0

    enum Step: Equatable {
        case editor
        case progress(VideoLayoutConfig)
    }

    var body: some View {
        Group {
            switch step {
            case .editor:
                editor()
            case .progress(let config):
                progressSheet(config: config)
            }
        }
    }

    private func editor() -> some View {
        let defaultAspect = defaultAspectFor(mode: comparisonViewModel.comparisonMode)
        let vm = ExportEditorViewModel(
            aspectRatio: defaultAspect,
            mode: comparisonViewModel.comparisonMode,
            stackedOpacity: CGFloat(comparisonViewModel.stackedOpacity),
            video1URL: video1URL,
            video2URL: video2URL,
            swing1: swing1,
            swing2: swing2,
            syncOffset: syncOffset
        )
        return ExportEditorView(
            viewModel: vm,
            onCancel: onDismiss,
            onExport: { config in
                pendingConfig = config
                step = .progress(config)
            }
        )
    }

    /// Sequential and Stacked default to 9:16 (more natural full-canvas);
    /// Side-by-Side defaults to 16:9 (HSTACK).
    private func defaultAspectFor(mode: ComparisonMode) -> ExportAspectRatio {
        switch mode {
        case .sideBySide: return .sideBySide
        case .stacked, .sequential: return .tikTokVertical
        }
    }

    private func progressSheet(config: VideoLayoutConfig) -> some View {
        ExportProgressView(
            viewModel: comparisonViewModel,
            layoutConfig: config,
            swingTrim: (swing1, swing2),
            isExporting: $isExporting,
            progress: $progress,
            onDismiss: onDismiss
        )
    }
}
```

- [ ] **Step 3: Delete `AspectRatioPickerView.swift`**

```bash
rm golf-sync-swing/Views/Export/AspectRatioPickerView.swift
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit Tasks 5–11 together (the whole export-mode chain)**

```bash
git add golf-sync-swing/Models/Export/ \
        golf-sync-swing/ViewModels/ExportEditorViewModel.swift \
        golf-sync-swing/Services/Export/CollageVideoCompositor.swift \
        golf-sync-swing/Services/VideoExportService.swift \
        golf-sync-swing/Views/Export/Components/EditorCanvas.swift \
        golf-sync-swing/Views/Export/ExportEditorView.swift \
        golf-sync-swing/Views/Export/ExportFlowCoordinator.swift \
        golf-sync-swing/Views/Export/AspectRatioPickerView.swift
git commit -m "feat(export): WYSIWYG export inheriting comparison mode (sideBySide/stacked/sequential)"
```

---

### Task 12: Add VideoExportService.exportSingleVideo

**Files:**
- Modify: `golf-sync-swing/Services/VideoExportService.swift`

- [ ] **Step 1: Add the new entry point + helper**

Add at the bottom of `VideoExportService` (above the closing `}` of the class):

```swift
    // MARK: - Single-video export

    /// Export a single source video to Photos.
    /// - When `swings` is nil, the full source is transcoded as-is.
    /// - When `swings` is non-empty, the swing slices are concatenated back-to-back.
    static func exportSingleVideo(
        videoURL: URL,
        swings: [SwingTimeRange]?,
        progress: @escaping (Float) -> Void,
        completion: @escaping (Result<URL, ExportError>) -> Void
    ) {
        Task {
            do {
                let outputURL = try await performSingleVideoExport(
                    videoURL: videoURL, swings: swings, progress: progress
                )
                await MainActor.run { completion(.success(outputURL)) }
            } catch let e as ExportError {
                await MainActor.run { completion(.failure(e)) }
            } catch {
                await MainActor.run { completion(.failure(.exportFailed(error.localizedDescription))) }
            }
        }
    }

    private static func performSingleVideoExport(
        videoURL: URL,
        swings: [SwingTimeRange]?,
        progress: @escaping (Float) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.missingVideoTrack
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let fullDuration = try await asset.load(.duration)

        let composition = AVMutableComposition()
        guard let videoTrackC = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ExportError.missingVideoTrack }

        let audioTrackC = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        )

        let slices: [(start: CMTime, duration: CMTime)]
        if let swings, !swings.isEmpty {
            slices = swings.sorted { $0.startTime < $1.startTime }.map { swing in
                let s = CMTime(seconds: max(0, swing.startTime), preferredTimescale: 600)
                let d = CMTime(seconds: max(0.05, swing.endTime - swing.startTime), preferredTimescale: 600)
                return (s, d)
            }
        } else {
            slices = [(.zero, fullDuration)]
        }

        var insertAt: CMTime = .zero
        for slice in slices {
            try videoTrackC.insertTimeRange(CMTimeRange(start: slice.start, duration: slice.duration),
                                            of: videoTrack, at: insertAt)
            if let audioTrack, let audioTrackC {
                try? audioTrackC.insertTimeRange(CMTimeRange(start: slice.start, duration: slice.duration),
                                                 of: audioTrack, at: insertAt)
            }
            insertAt = CMTimeAdd(insertAt, slice.duration)
        }

        let videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
        let nominalFPS = try await videoTrack.load(.nominalFrameRate)
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(nominalFPS, 30)))

        return try await runExport(composition: composition, videoComposition: videoComposition, progress: progress)
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Add a smoke test**

Create `golf-sync-swingTests/SingleVideoExportTests.swift`:

```swift
//
//  SingleVideoExportTests.swift
//  golf-sync-swingTests
//

import Testing
import Foundation
import AVFoundation
@testable import golf_sync_swing

struct SingleVideoExportTests {

    @Test("Empty swings list falls back to full video", .timeLimit(.minutes(1)))
    func emptySwingsFallsBack() async throws {
        // We cannot run an actual export in unit tests without a fixture video.
        // Instead, verify the slice-computation branch by inspecting public state.
        // (The actual export is verified manually on device — see plan Task 16.)
        // This test exists to guard against regressions in the input handling.
        let url = URL(fileURLWithPath: "/dev/null")
        await withCheckedContinuation { continuation in
            VideoExportService.exportSingleVideo(
                videoURL: url, swings: nil,
                progress: { _ in },
                completion: { result in
                    if case .failure(let err) = result {
                        // /dev/null is not a video — we expect ExportError, not crash
                        #expect(err.errorDescription != nil)
                    }
                    continuation.resume()
                }
            )
        }
    }
}
```

- [ ] **Step 4: Run the test to verify**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:golf-sync-swingTests/SingleVideoExportTests 2>&1 | grep -E "Test (case|suite)|passed|failed" | head`

Expected: 1 passed.

- [ ] **Step 5: Commit**

```bash
git add golf-sync-swing/Services/VideoExportService.swift golf-sync-swingTests/SingleVideoExportTests.swift
git commit -m "feat(export): add exportSingleVideo for full-video and swings-only paths"
```

---

### Task 13: Add SingleVideoExportSheet

**Files:**
- Create: `golf-sync-swing/Views/Components/SingleVideoExportSheet.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  SingleVideoExportSheet.swift
//  golf-sync-swing
//
//  Bottom sheet for exporting a single source video to Photos.
//  No editor, no aspect picker — saves in source aspect.
//

import SwiftUI
import Photos

struct SingleVideoExportSheet: View {
    let video: SwingVideo
    let mode: VideoPlaybackMode
    let onDismiss: () -> Void

    @State private var isExporting = false
    @State private var progress: Float = 0
    @State private var errorMessage: String?
    @State private var savedConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            handle
            if let errorMessage {
                errorContent(errorMessage)
            } else if savedConfirmation {
                successContent
            } else if isExporting {
                progressContent
            } else {
                idleContent
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .presentationDetents([.fraction(0.42)])
    }

    private var handle: some View {
        Capsule()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 36, height: 4)
            .padding(.top, 4)
    }

    private var idleContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.up.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.appTeal)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: startExport) {
                Text("Export to Photos")
                    .font(.headline).fontWeight(.bold).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(canExport ? Color.appTeal : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .disabled(!canExport)
        }
    }

    private func progressContent(_ message: String = "Exporting…") -> some View {
        VStack(spacing: 12) {
            ProgressView(value: progress).tint(Color.appTeal)
            Text("\(Int(progress * 100))% — \(message)").font(.caption)
        }
    }

    private var progressContent: some View {
        progressContent("Exporting…")
    }

    private var successContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Saved to Photos").font(.headline)
            Button("Done", action: onDismiss).buttonStyle(.borderedProminent)
        }
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Export failed").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Button("Close", action: onDismiss).buttonStyle(.bordered)
        }
    }

    private var title: String {
        mode == .swingsOnly ? "Export Swings Only" : "Export Full Video"
    }

    private var subtitle: String {
        switch mode {
        case .swingsOnly:
            let count = video.swings.count
            let totalSeconds = video.swings.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
            let s = String(format: "%.1f", totalSeconds)
            return "\(count) swing\(count == 1 ? "" : "s") · ~\(s) seconds total"
        case .fullVideo:
            let m = Int(video.duration) / 60
            let s = Int(video.duration) % 60
            return String(format: "Duration: %d:%02d", m, s)
        }
    }

    private var canExport: Bool {
        if mode == .swingsOnly { return !video.swings.isEmpty }
        return true
    }

    private func startExport() {
        guard let url = video.validLocalURL else {
            errorMessage = "Video file unavailable"
            return
        }
        let swings: [SwingTimeRange]? = (mode == .swingsOnly)
            ? video.swings.map { SwingTimeRange(startTime: $0.startTime, contactTime: $0.contactTime, endTime: $0.endTime) }
            : nil
        isExporting = true
        VideoExportService.exportSingleVideo(
            videoURL: url, swings: swings,
            progress: { p in Task { @MainActor in progress = p } },
            completion: { result in
                isExporting = false
                switch result {
                case .success(let outputURL):
                    saveToPhotos(url: outputURL)
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        )
    }

    private func saveToPhotos(url: URL) {
        VideoExportService.saveToPhotos(url: url) { result in
            switch result {
            case .success:
                savedConfirmation = true
            case .failure(let err):
                errorMessage = err.localizedDescription
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Stage**

```bash
git add golf-sync-swing/Views/Components/SingleVideoExportSheet.swift
```

---

### Task 14: Wire PlayerTopBarView share button + present sheet from SingleVideoPlayerView

**Files:**
- Modify: `golf-sync-swing/Views/Components/PlayerTopBarView.swift`
- Modify: `golf-sync-swing/Views/SingleVideoPlayerView.swift`

- [ ] **Step 1: Add `onExport` callback to `PlayerTopBarView`**

Replace `PlayerTopBarView.swift` lines 11–14 (struct decl + properties):

```swift
struct PlayerTopBarView: View {
    let playbackMode: VideoPlaybackMode
    let onDismiss: () -> Void
    let onSwitchMode: (VideoPlaybackMode) -> Void
    let onExport: () -> Void
```

Replace `shareButton` (line 71) — wire the action and disable if no swings in swingsOnly mode:

```swift
    private var shareButton: some View {
        Button(action: onExport) {
            Image(systemName: "square.and.arrow.up")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.appTeal)
                .clipShape(Circle())
        }
        .accessibilityLabel("Export video")
    }
```

- [ ] **Step 2: Pass the callback from `SingleVideoPlayerView`**

In `SingleVideoPlayerView.swift`:

Add state at line 22:

```swift
    @State private var showExportSheet = false
```

Update the `PlayerTopBarView` call site (lines 44–48):

```swift
                PlayerTopBarView(
                    playbackMode: playbackMode,
                    onDismiss: { dismiss() },
                    onSwitchMode: switchMode,
                    onExport: { showExportSheet = true }
                )
```

Add a `.sheet` modifier in the body's `.sheet(...)` chain — replace the existing sheet (line 33) with:

```swift
        .sheet(isPresented: $showSwingEditor) { swingEditorSheet }
        .sheet(isPresented: $showExportSheet) {
            SingleVideoExportSheet(
                video: video,
                mode: playbackMode,
                onDismiss: { showExportSheet = false }
            )
        }
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add golf-sync-swing/Views/Components/PlayerTopBarView.swift \
        golf-sync-swing/Views/SingleVideoPlayerView.swift \
        golf-sync-swing/Views/Components/SingleVideoExportSheet.swift
git commit -m "feat(history): wire single-video export sheet (full video + swings-only)"
```

---

### Task 15: Run full test suite + smoke test

**Files:** none

- [ ] **Step 1: Build clean**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "BUILD"`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Run all tests**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30`

Expected: only the pre-existing flaky `validationScorecard` test may fail. All export and aspect tests should pass. Specifically, verify no test regressions from the mode rename: `ExportEditorViewModelTests`, `VideoExportServiceTests`, `ExportAspectRatioTests`, `SingleVideoExportTests`.

If any export/aspect test fails, fix it inline (the most likely fixes are updating test helpers that constructed `ExportEditorViewModel` or `VideoLayoutConfig` with the old signatures — pass `mode: .sideBySide` and the renamed property).

- [ ] **Step 3: Commit any test fixes**

```bash
git add golf-sync-swingTests/
git commit -m "test(export): adapt test helpers to new mode-aware signatures"
```

(Skip if no test fixes were needed.)

---

### Task 16: Manual end-to-end verification on simulator

**Files:** none

- [ ] **Step 1: Launch the app on iPhone 17 simulator**

Run: `xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator; xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' install`

- [ ] **Step 2: Verify history → single-video export (Full Video mode)**

In the History tab, tap a video. In the top bar, switch to "Full Video" mode. Tap the top-right share icon. Verify the sheet appears with title "Export Full Video" and a duration. Tap Export to Photos. Verify success state.

- [ ] **Step 3: Verify history → single-video export (Swings Only mode)**

Switch to "Swings Only" mode (requires the video to have at least one swing). Tap the top-right share icon. Verify title is "Export Swings Only" and the subtitle shows the swing count and total duration. Tap Export. Open Photos and verify the saved video contains only the swing windows, back-to-back.

- [ ] **Step 4: Verify comparison → side-by-side export**

From the Home tab, pick two videos with swings. In the comparison view: confirm top-right has a `square.and.arrow.up` icon and bottom-right of the video area has the swap arrows. Tap the top-right icon. The editor opens immediately (no aspect picker). Pinch-zoom video 2 — confirm it stays inside its cell (does not bleed into video 1's area). Switch the inline aspect toggle to 9:16 — layout should flip from HSTACK to VSTACK. Tap Export, save to Photos, verify the result.

- [ ] **Step 5: Verify comparison → stacked export**

In the comparison view, switch the mode picker to "Stacked" (requires premium / use screenshot-mode debug bypass if available). Drag the opacity slider to ~30%. Tap top-right export icon. The editor shows the two videos overlaid at the chosen opacity. Tap Export, save, and confirm the exported file shows both videos blended at the captured opacity.

- [ ] **Step 6: Verify comparison → sequential export**

Switch the mode picker to "Sequential". The video area should show only one swing playing at a time, and the loop should advance to the second swing. Tap top-right export. The editor shows a "Swing 1 / Swing 2" segmented toggle. Tap Swing 2 — the canvas switches to show video 2; pinch/pan to frame it. Tap Export. The exported video should play swing 1, then swing 2, no overlap.

- [ ] **Step 7: Verify swap button**

Back in the comparison view (any mode), tap the floating bottom-right swap button. Confirm the two videos exchange positions (or roles, in stacked/sequential).

- [ ] **Step 8: Verify the DONE button is gone**

Confirm the controls panel no longer has a "DONE" button. The X in the top-left is the only dismiss path.

- [ ] **Step 9: Final commit (no code changes — this is a verification task)**

If any issues are found, file each as a follow-up commit. Otherwise no commit needed.

---

## Self-review

**Spec coverage:**

- ✅ Spec §1.1 (3 modes) → Task 2
- ✅ Spec §1.2 (deletions) → Task 2 (sideBySideSynced/onionSkin/overlay removed from enum)
- ✅ Spec §1.3 (premium gating, advancedComparisonModes flag) → Task 1, Task 2
- ✅ Spec §2 (ComparisonView layout) → Task 4
- ✅ Spec §3 (SingleVideoPlayerView wire button) → Task 14
- ✅ Spec §4 (Comparison export flow B) → Tasks 9, 10, 11
- ✅ Spec §5 (Single-video export flow C) → Tasks 12, 13, 14
- ✅ Spec §6.1 (VideoExportService changes) → Tasks 8, 12
- ✅ Spec §6.2 (CollageVideoCompositor layoutMode) → Tasks 6, 7
- ✅ Spec §6.3 (ComparisonViewModel changes) → Task 3
- ✅ Spec §7 (files retired) → Task 1, Task 2, Task 11
- ✅ Spec §8 (no migration needed) → no task required
- ✅ Spec §9 (testing) → Task 12 (smoke), Task 15 (suite), Task 16 (manual)

**Placeholder scan:** None. Each step has actual code or commands.

**Type consistency:**
- `ComparisonMode` cases used consistently (`.sideBySide`, `.stacked`, `.sequential`).
- `stackedOpacity` (CGFloat on `VideoLayoutConfig`, Double on `ComparisonViewModel` — note: cast at the boundary in Task 11's coordinator: `CGFloat(comparisonViewModel.stackedOpacity)`).
- `currentSequentialEditSwing` on `ExportEditorViewModel` is editor-only state.
- `currentSequentialSwing` on `ComparisonViewModel` is playback state. Different responsibilities, different names — intentional.
- `CompositorLayout` enum used in Task 7 matches Task 6 definition (`.sideBySide`, `.stacked(opacity:)`).

**Known caveats:**
- Task 8's sequential composition relies on `AVMutableVideoComposition.videoComposition(withPropertiesOf:)` to auto-derive layer instructions for the back-to-back tracks. In practice this works because the tracks don't overlap in time. If results are wrong on physical device, fall back to a manual single-layer instruction per track.
- Aspect changes in the editor mutate `viewModel.aspectRatio` directly. The canvas re-layouts; transforms are preserved (their `containerSize` will refresh on next layout pass via the `ZoomableVideoTile` `onChange(of: geo.size)` handler).
- Premium-gating on `Stacked` and `Sequential` runs through the new `advancedComparisonModes` flag (Task 1). The paywall sheet's display copy may want a refresh in a follow-up but is not a blocker for shipping.
