# Audit Fix Round 2 — Implementation Plan

> **For Claude:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all critical, high, and medium bugs found during the pre-distribution audit (round 2).

**Architecture:** Targeted fixes across models, view models, services, and views. No new files needed — all changes modify existing code. Grouped by dependency order: models first, then services, then view models, then views.

**Tech Stack:** Swift 5.0, SwiftUI, AVFoundation, Vision, SwiftData

**Build command:** `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build`

---

## Chunk 1: Critical Fixes

### Task 1: Fix PoseFrame Sendable violation

**Files:**
- Modify: `golf-sync-swing/Models/PoseFrame.swift:12`

PoseFrame claims `Sendable` but holds `VNHumanBodyPoseObservation?` which is not Sendable. Mark as `@unchecked Sendable` with safety documentation.

- [ ] **Step 1: Fix the conformance**

```swift
// Change line 12 from:
struct PoseFrame: Sendable {
// To:
/// @unchecked because VNHumanBodyPoseObservation is effectively immutable once created
/// by Vision framework. All properties are read-only after initialization.
struct PoseFrame: @unchecked Sendable {
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "(error:|BUILD)"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Models/PoseFrame.swift
git commit -m "fix: mark PoseFrame as @unchecked Sendable with safety docs"
```

---

### Task 2: Fix PersonCropper force unwrap crash

**Files:**
- Modify: `golf-sync-swing/Services/Detection/PersonCropper.swift:109,115-119`

`createBlankBuffer()` force-unwraps a CVPixelBuffer allocation that can fail under memory pressure. Also, `renderCroppedBuffer` falls back to `source.pixelBuffer` which may also be nil.

- [ ] **Step 1: Replace createBlankBuffer with safe version**

Replace lines 115-119:
```swift
private func createBlankBuffer() -> CVPixelBuffer? {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, targetSize, targetSize, kCVPixelFormatType_32BGRA, nil, &buffer)
    return buffer
}
```

- [ ] **Step 2: Update renderCroppedBuffer to propagate optionality**

Replace lines 92-113 — change return type and callers:
```swift
private func renderCroppedBuffer(from source: CIImage, cropRect: CGRect) -> CVPixelBuffer? {
    let cropped = source
        .cropped(to: cropRect)
        .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))

    let scale = CGFloat(targetSize) / max(cropRect.width, 1)
    let scaled = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

    var output: CVPixelBuffer?
    CVPixelBufferCreate(
        kCFAllocatorDefault,
        targetSize, targetSize,
        kCVPixelFormatType_32BGRA,
        nil,
        &output
    )

    guard let buffer = output else { return source.pixelBuffer ?? createBlankBuffer() }

    ciContext.render(scaled, to: buffer)
    return buffer
}
```

- [ ] **Step 3: Update crop() to handle nil**

Replace the `crop` method (line 37-42). Since the protocol returns non-optional, fall back to source buffer:
```swift
func crop(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
    let boundingBox = detectPerson(in: pixelBuffer) ?? cachedBoundingBox
    let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
    let cropRect = buildCropRect(boundingBox: boundingBox, imageExtent: sourceImage.extent)
    return renderCroppedBuffer(from: sourceImage, cropRect: cropRect) ?? pixelBuffer
}
```

- [ ] **Step 4: Build to verify**

Run: build command
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add golf-sync-swing/Services/Detection/PersonCropper.swift
git commit -m "fix: eliminate force unwrap in PersonCropper CVPixelBuffer allocation"
```

---

### Task 3: Fix privacy URL mismatch

**Files:**
- Modify: `golf-sync-swing/Views/Settings/SettingsView.swift:94`

Settings uses `golfswingsync.app/privacy` while Paywall uses `withcoach.app/privacy`. Standardize both to `withcoach.app/privacy` (the newer domain set in the previous audit).

- [ ] **Step 1: Update SettingsView privacy URL**

In `golf-sync-swing/Views/Settings/SettingsView.swift`, change line 94:
```swift
// From:
Link(destination: URL(string: "https://golfswingsync.app/privacy")!) {
// To:
Link(destination: URL(string: "https://withcoach.app/privacy")!) {
```

- [ ] **Step 2: Build to verify**

Run: build command
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Views/Settings/SettingsView.swift
git commit -m "fix: unify privacy policy URL to withcoach.app across paywall and settings"
```

---

### Task 4: Fix RecordingViewModel missing callback cleanup

**Files:**
- Modify: `golf-sync-swing/ViewModels/RecordingViewModel.swift:74-100,317-319`

Callbacks `onSwingDetected` and `onRecordingFinished` are never cleared. Also, the error path in `onRecordingFinished` doesn't stop detection. Also, `cleanup()` should clear callbacks.

- [ ] **Step 1: Add deinit to clear callbacks**

After line 83 (end of init), add:
```swift
deinit {
    detectionOrchestrator.onSwingDetected = nil
    cameraService.onRecordingFinished = nil
    cameraService.onFrameCaptured = nil
    cameraService.onAudioCaptured = nil
}
```

- [ ] **Step 2: Fix error path in setupCallbacks**

In `setupCallbacks()`, add cleanup to the error branch (after line 93, before `self.state = .idle`):
```swift
if let error {
    self.errorMessage = error.localizedDescription
    self.detectionOrchestrator.stop()
    self.cameraService.onFrameCaptured = nil
    self.cameraService.onAudioCaptured = nil
    self.mainViewShowsReplay = false
    self.isLoadingReplay = false
    self.replayingSwingIndex = nil
    self.state = .idle
} else {
```

- [ ] **Step 3: Enhance cleanup() to clear callbacks**

Replace the `cleanup()` method (lines 317-319):
```swift
func cleanup() {
    detectionOrchestrator.stop()
    detectionOrchestrator.onSwingDetected = nil
    cameraService.onRecordingFinished = nil
    cameraService.onFrameCaptured = nil
    cameraService.onAudioCaptured = nil
    cameraService.stopSession()
}
```

- [ ] **Step 4: Build to verify**

Run: build command
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add golf-sync-swing/ViewModels/RecordingViewModel.swift
git commit -m "fix: clear detection/camera callbacks in RecordingViewModel deinit, error path, and cleanup"
```

---

### Task 5: Fix onboarding skip bypassing paywall

**Files:**
- Modify: `golf-sync-swing/Views/Onboarding/OnboardingView.swift:144-148`

The "Skip" button currently bypasses the paywall entirely — a revenue leak. Change it to show the paywall instead.

- [ ] **Step 1: Change skipAll to show paywall**

Replace lines 144-148:
```swift
/// Skip goes directly to paywall (skipping remaining onboarding pages).
private func skipAll() {
    showPaywall = true
}
```

- [ ] **Step 2: Build to verify**

Run: build command
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Views/Onboarding/OnboardingView.swift
git commit -m "fix: onboarding skip shows paywall instead of bypassing it"
```

---

## Chunk 2: High Priority Fixes

### Task 6: Fix AVPlayer resource leaks in cleanup methods

**Files:**
- Modify: `golf-sync-swing/ViewModels/VideoPlayerViewModel.swift:38-51`
- Modify: `golf-sync-swing/ViewModels/ComparisonViewModel.swift:78-90`

Both ViewModels pause players but don't call `replaceCurrentItem(with: nil)`, leaving AVPlayerItems holding video asset references.

- [ ] **Step 1: Fix VideoPlayerViewModel cleanup and deinit**

Replace `cleanup()` (lines 44-51):
```swift
func cleanup() {
    player.pause()
    player.replaceCurrentItem(with: nil)
    if let observer = timeObserver {
        player.removeTimeObserver(observer)
        timeObserver = nil
    }
    cancellables.removeAll()
}
```

Also update deinit to call cleanup (replace lines 38-42):
```swift
deinit {
    if let observer = timeObserver {
        player.removeTimeObserver(observer)
    }
    cancellables.removeAll()
}
```

- [ ] **Step 2: Fix ComparisonViewModel cleanup**

Replace `cleanup()` (lines 83-90):
```swift
func cleanup() {
    player1.pause()
    player1.replaceCurrentItem(with: nil)
    player2.pause()
    player2.replaceCurrentItem(with: nil)
    synchronizer.stop()
    if let obs = timeObserver1 { player1.removeTimeObserver(obs); timeObserver1 = nil }
    if let obs = timeObserver2 { player2.removeTimeObserver(obs); timeObserver2 = nil }
    isPlaying = false
}
```

- [ ] **Step 3: Build to verify**

Run: build command
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add golf-sync-swing/ViewModels/VideoPlayerViewModel.swift golf-sync-swing/ViewModels/ComparisonViewModel.swift
git commit -m "fix: release AVPlayer items in cleanup to prevent resource leaks"
```

---

### Task 7: Fix ComparisonViewModel auto-play and swap logic

**Files:**
- Modify: `golf-sync-swing/ViewModels/ComparisonViewModel.swift:75,187-193`

Two issues: (1) `play()` in init auto-plays without user action, (2) `swapVideos()` negates offset but doesn't restart synchronizer with new player roles.

- [ ] **Step 1: Remove auto-play from init**

Change line 75 from `play()` to nothing — remove the line entirely. The ComparisonView should call `play()` via `.onAppear` if auto-play is desired.

- [ ] **Step 2: Fix swapVideos to restart synchronizer**

Replace `swapVideos()` (lines 187-193):
```swift
func swapVideos() {
    let wasPlaying = isPlaying
    if comparisonMode.isSynchronized { synchronizer.stop() }
    isSwapped.toggle()
    syncOffset = -syncOffset
    guard comparisonMode.isSynchronized else { return }
    startSynchronizer()
    synchronizer.resync(referenceTime: currentTime)
    if wasPlaying {
        effectivePlayer1.rate = playbackRate
        effectivePlayer2.rate = playbackRate
    }
}
```

- [ ] **Step 3: Add .onAppear auto-play to ComparisonView**

In `golf-sync-swing/Views/ComparisonView.swift`, find the main body and add an `.onAppear` that calls `viewModel.play()` if auto-play is desired. Read the file first to find the right location.

- [ ] **Step 4: Build to verify**

Run: build command
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add golf-sync-swing/ViewModels/ComparisonViewModel.swift golf-sync-swing/Views/ComparisonView.swift
git commit -m "fix: remove auto-play from init, restart synchronizer on video swap"
```

---

### Task 8: Fix force unwraps in services

**Files:**
- Modify: `golf-sync-swing/Services/Detection/WristRefinementService.swift:99`
- Modify: `golf-sync-swing/Services/Camera/CaptureSessionConfigurator.swift:154`
- Modify: `golf-sync-swing/Models/SwingVideo.swift:27`
- Modify: `golf-sync-swing/Services/VideoStorageService.swift:16`
- Modify: `golf-sync-swing/Services/ThumbnailService.swift:15`

Five force unwrap patterns that can crash.

- [ ] **Step 1: Fix WristRefinementService**

Replace line 99:
```swift
// From:
if lowestY == nil || y < lowestY! {
// To:
if lowestY.map({ y < $0 }) ?? true {
```

- [ ] **Step 2: Fix CaptureSessionConfigurator**

Replace line 154:
```swift
// From:
if bestFrameRateRange == nil || range.maxFrameRate > bestFrameRateRange!.maxFrameRate {
// To:
if bestFrameRateRange.map({ range.maxFrameRate > $0.maxFrameRate }) ?? true {
```

- [ ] **Step 3: Fix documentsDirectory force index (3 locations)**

In `SwingVideo.swift` line 27, `VideoStorageService.swift` line 16, and `ThumbnailService.swift` line 15, change:
```swift
// From:
FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
// To:
FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
```

Note: `.first!` is still a force unwrap, but `urls(for:in:)` with `.documentDirectory` and `.userDomainMask` is guaranteed to return at least one URL on iOS. This is a safe force unwrap — the iOS sandbox always provides a documents directory. Add a comment:
```swift
// Safe: iOS sandbox guarantees documentDirectory exists
FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
```

- [ ] **Step 4: Build to verify**

Run: build command
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add golf-sync-swing/Services/Detection/WristRefinementService.swift \
       golf-sync-swing/Services/Camera/CaptureSessionConfigurator.swift \
       golf-sync-swing/Models/SwingVideo.swift \
       golf-sync-swing/Services/VideoStorageService.swift \
       golf-sync-swing/Services/ThumbnailService.swift
git commit -m "fix: eliminate unsafe force unwraps in services and models"
```

---

## Chunk 3: Medium Priority Fixes

### Task 9: Fix FrameProcessingGate lock pattern

**Files:**
- Modify: `golf-sync-swing/ViewModels/Recording/FrameProcessingGate.swift:58-67`

The `recordFrame` method doesn't use `defer` for lock release, making it fragile.

- [ ] **Step 1: Add defer to recordFrame**

Replace lines 58-67:
```swift
func recordFrame(at cameraTime: TimeInterval) -> TimeInterval {
    lock.lock()
    defer { lock.unlock() }
    if _recordingStartTimestamp == nil {
        _recordingStartTimestamp = cameraTime
        AppLogger.camera.debug("RecordingVM: First frame at \(cameraTime)s")
    }
    _frameProcessedCount += 1
    let count = _frameProcessedCount
    let startTime = _recordingStartTimestamp ?? 0

    let relativeTime = cameraTime - startTime
    if count % 60 == 0 {
        AppLogger.camera.debug("RecordingVM: Processed \(count) frames, t=\(String(format: \"%.2f\", relativeTime))s")
    }
    return relativeTime
}
```

- [ ] **Step 2: Build to verify**

Run: build command
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/ViewModels/Recording/FrameProcessingGate.swift
git commit -m "fix: use defer for lock release in FrameProcessingGate.recordFrame"
```

---

### Task 10: Remove dead code

**Files:**
- Delete: `golf-sync-swing/Services/Sync/VideoFrameIterator.swift`
- Delete: `golf-sync-swing/Views/Components/AnalysisOverlayView.swift`
- Delete: `golf-sync-swing/Views/Recording/Components/PositioningGuideOverlay.swift`
- Delete: `golf-sync-swing/Views/Components/PremiumBadge.swift`
- Delete: `golf-sync-swing/Views/Components/VideoFloatingActionsView.swift`
- Delete: `golf-sync-swing/Views/Components/PlayerTopBarView.swift`
- Delete: `golf-sync-swing/Views/Components/SwingDetectionPanel.swift`
- Modify: `golf-sync-swing/Models/SwingVideo.swift` (remove unused computed properties)

- [ ] **Step 1: Verify each file is truly unused**

Use grep to confirm no references exist for each file's primary type. Skip any that ARE referenced.

- [ ] **Step 2: Delete confirmed dead files**

```bash
git rm golf-sync-swing/Services/Sync/VideoFrameIterator.swift
git rm golf-sync-swing/Views/Components/AnalysisOverlayView.swift
git rm golf-sync-swing/Views/Recording/Components/PositioningGuideOverlay.swift
git rm golf-sync-swing/Views/Components/PremiumBadge.swift
git rm golf-sync-swing/Views/Components/VideoFloatingActionsView.swift
git rm golf-sync-swing/Views/Components/PlayerTopBarView.swift
git rm golf-sync-swing/Views/Components/SwingDetectionPanel.swift
```

If the `Sync/` directory is now empty, remove it too.

- [ ] **Step 3: Remove unused SwingVideo properties**

In `golf-sync-swing/Models/SwingVideo.swift`, remove:
```swift
// Remove lines 78-86 (detectedImpactTime and hasHighConfidenceDetection)
```

- [ ] **Step 4: Build to verify nothing broke**

Run: build command
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove 7 dead code files and unused SwingVideo properties"
```

---

### Task 11: Fix VideoExportService silent audio failure

**Files:**
- Modify: `golf-sync-swing/Services/VideoExportService.swift:131,136`

Audio track insertion uses `try?` which silently drops audio on failure.

- [ ] **Step 1: Read the file to find exact lines**

Read `golf-sync-swing/Services/VideoExportService.swift` and locate the `try?` on audio track insertion.

- [ ] **Step 2: Replace try? with try and log on failure**

Change the audio insertion blocks to log errors instead of silencing them:
```swift
do {
    try compositionAudioTrack1.insertTimeRange(timeRange1, of: audioTrack1, at: video1StartTime)
} catch {
    AppLogger.storage.warning("Export: failed to add video1 audio: \(error.localizedDescription)")
}
```

Apply the same pattern for video2's audio track.

- [ ] **Step 3: Build to verify**

Run: build command
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add golf-sync-swing/Services/VideoExportService.swift
git commit -m "fix: log audio track export failures instead of silently swallowing"
```

---

### Task 12: Add accessibility labels to ComparisonView

**Files:**
- Modify: `golf-sync-swing/Views/ComparisonView.swift`

Circle buttons lack accessibility labels.

- [ ] **Step 1: Read the file to find circleButton usage**

Read `golf-sync-swing/Views/ComparisonView.swift` and locate where `circleButton` is defined and called.

- [ ] **Step 2: Add accessibilityLabel to each button**

Add `.accessibilityLabel()` to each circle button call site (close, swap, etc.).

- [ ] **Step 3: Build to verify**

Run: build command
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add golf-sync-swing/Views/ComparisonView.swift
git commit -m "fix: add accessibility labels to comparison view buttons"
```

---

### Task 13: Final build and test verification

- [ ] **Step 1: Full build**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run tests**

```bash
xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -20
```
Expected: All tests pass

- [ ] **Step 3: Grep for remaining force unwraps in production code**

```bash
grep -rn '!' golf-sync-swing/ --include='*.swift' | grep -v '#if DEBUG' | grep -v '// Safe:' | grep -v 'IBOutlet' | grep -v '@objc'
```

Review results — any new force unwraps should be documented or fixed.
