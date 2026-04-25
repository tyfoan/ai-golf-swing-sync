# PiP Replay Fixes Implementation Plan

> **For Claude:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 3 bugs in the recording PiP replay: slow-mo default speed, broken tap-to-swap, and unnecessary loading delay.

**Architecture:** Targeted fixes in RecordingViewModel (speed default), RecordingPiPView (tap handling), and SwingReplayView (loading delay). No new files, no architectural changes.

**Tech Stack:** Swift, SwiftUI, AVKit

---

## Chunk 1: All Fixes

### Task 1: Fix default replay speed (1.0x instead of 0.5x)

**Files:**
- Modify: `golf-sync-swing/ViewModels/RecordingViewModel.swift:80`

**Context:** When a swing is detected, `onSwingDetected` callback sets `playbackSpeed = 0.5`, making the PiP replay play in slow motion. The user wants normal speed by default. The speed cycling button (0.25x → 0.5x → 1.0x) remains available for manual slow-mo.

- [ ] **Step 1: Change default detection speed**

In `RecordingViewModel.swift`, inside `init()`, change line 80:

```swift
// BEFORE:
self.playbackSpeed = 0.5

// AFTER:
self.playbackSpeed = 1.0
```

- [ ] **Step 2: Build to verify no compile errors**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/ViewModels/RecordingViewModel.swift
git commit -m "fix: default PiP replay to 1.0x speed instead of slow-mo"
```

---

### Task 2: Fix PiP tap-to-swap (transparent overlay captures taps above VideoPlayer)

**Files:**
- Modify: `golf-sync-swing/Views/Recording/Components/RecordingPiPView.swift:28-41`

**Context:** The `.onTapGesture` is on the parent ZStack, and `SwingReplayView` has `.allowsHitTesting(false)`. However, AVKit's `VideoPlayer` wraps a UIKit `AVPlayerViewController` whose gesture recognizers operate at a lower level than SwiftUI's hit testing system, swallowing taps before they reach the SwiftUI gesture. Fix: add a `Color.clear.contentShape(Rectangle())` overlay inside the ZStack that sits above the content and reliably captures taps.

- [ ] **Step 1: Replace onTapGesture placement with overlay approach**

In `RecordingPiPView.swift`, replace the body's ZStack and tap gesture:

```swift
// BEFORE (lines 28-41):
ZStack(alignment: .topLeading) {
    content
        .frame(width: 120, height: 160)

    badge
        .padding(8)
}
.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
.overlay(
    RoundedRectangle(cornerRadius: cornerRadius)
        .stroke(pipDisplayMode == .lastSwingReplay ? Color.sand : Color.fairwayGreen, lineWidth: 2)
)
.shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
.onTapGesture(perform: onTap)

// AFTER:
ZStack(alignment: .topLeading) {
    content
        .frame(width: 120, height: 160)

    badge
        .padding(8)

    Color.clear
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
}
.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
.overlay(
    RoundedRectangle(cornerRadius: cornerRadius)
        .stroke(pipDisplayMode == .lastSwingReplay ? Color.sand : Color.fairwayGreen, lineWidth: 2)
)
.shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
```

The key change: `Color.clear.contentShape(Rectangle())` creates an invisible layer that SwiftUI treats as fully tappable. Because it's a native SwiftUI view (not a UIKit wrapper), its `.onTapGesture` fires reliably regardless of what's below it.

- [ ] **Step 2: Remove now-unnecessary `.allowsHitTesting(false)` from content**

In the same file, in the `content` computed property (line 57), remove `.allowsHitTesting(false)` from the SwingReplayView — it's no longer needed since the clear overlay captures all taps:

```swift
// BEFORE:
SwingReplayView(videoURL: url, startTime: swing.startTime, endTime: swing.endTime, playbackSpeed: playbackSpeed, showControls: false)
    .id(swing.id)
    .allowsHitTesting(false)

// AFTER:
SwingReplayView(videoURL: url, startTime: swing.startTime, endTime: swing.endTime, playbackSpeed: playbackSpeed, showControls: false)
    .id(swing.id)
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add golf-sync-swing/Views/Recording/Components/RecordingPiPView.swift
git commit -m "fix: use clear overlay for reliable PiP tap handling over VideoPlayer"
```

---

### Task 3: Reduce loading delay in SwingReplayView

**Files:**
- Modify: `golf-sync-swing/Views/Recording/SwingReplayView.swift:126,32`

**Context:** `loadVideo()` has a 100ms initial sleep and 300ms retry delays. The initial sleep is unnecessary — the video URL is already available when the view appears. The retry delay can be reduced to 150ms to halve perceived latency on retries. Keep the retry mechanism (video file may still be growing during recording) but make it faster.

- [ ] **Step 1: Remove initial delay**

In `SwingReplayView.swift`, remove line 126:

```swift
// BEFORE (line 125-126):
private func loadVideo() async {
    // Small initial delay
    try? await Task.sleep(for: .milliseconds(100))

// AFTER:
private func loadVideo() async {
```

- [ ] **Step 2: Reduce retry delay from 300ms to 150ms**

In `SwingReplayView.swift`, change line 32:

```swift
// BEFORE:
private let retryDelay: UInt64 = 300_000_000 // 300ms in nanoseconds

// AFTER:
private let retryDelay: UInt64 = 150_000_000 // 150ms in nanoseconds
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add golf-sync-swing/Views/Recording/SwingReplayView.swift
git commit -m "fix: remove unnecessary loading delay and speed up retry in SwingReplayView"
```
