# Export Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 3-step Export flow (aspect-ratio picker → editor with pinch/zoom/pan + per-video mute → export) that replaces the hardcoded SBS export from `ComparisonView`.

**Architecture:** SwiftUI shell with a UIKit-backed `ZoomableVideoTile` (lifted from video-collage), a pure-math `ExportLayoutRenderer` that maps preview transforms to export pixels, and a refactored `VideoExportService` parameterized by `VideoLayoutConfig`. No worktree — work on the current branch.

**Tech Stack:** SwiftUI, UIKit (gestures + AVPlayerLayer), AVFoundation, Swift Testing (`@Test`).

**Spec:** [`docs/superpowers/specs/2026-05-01-export-editor-design.md`](../specs/2026-05-01-export-editor-design.md)

**Build / test commands:**
- Build: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Test: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test`
- Single test: append `-only-testing:golf-sync-swingTests/<TestStruct>/<testFunc>`

**File structure (locked in):**
```
golf-sync-swing/
├── Models/Export/
│   ├── VideoArrangement.swift              (new — Task 1)
│   ├── VideoTransform.swift                (new — Task 2)
│   ├── ExportAspectRatio.swift             (new — Task 3)
│   └── VideoLayoutConfig.swift             (new — Task 4)
├── Services/Export/
│   └── ExportLayoutRenderer.swift          (new — Task 5)
├── Services/VideoExportService.swift       (modified — Task 6)
├── ViewModels/ExportEditorViewModel.swift  (new — Task 11)
└── Views/
    ├── ComparisonView.swift                (modified — Task 16)
    ├── Components/ExportProgressView.swift (modified — Task 14)
    └── Export/
        ├── ExportFlowCoordinator.swift     (new — Task 15)
        ├── AspectRatioPickerView.swift     (new — Task 13)
        ├── ExportEditorView.swift          (new — Task 12)
        └── Components/
            ├── ZoomableVideoContainerView.swift   (new — Task 7)
            ├── ZoomableVideoTile.swift            (new — Task 8)
            ├── EditorCanvas.swift                 (new — Task 10)
            └── MuteToggleButton.swift             (new — Task 9)

golf-sync-swingTests/
├── ExportAspectRatioTests.swift            (new — Task 3)
├── ExportLayoutRendererTests.swift         (new — Task 5)
└── ExportEditorViewModelTests.swift        (new — Task 11)
```

---

### Task 1: VideoArrangement enum

**Files:**
- Create: `golf-sync-swing/Models/Export/VideoArrangement.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  VideoArrangement.swift
//  golf-sync-swing
//

import Foundation

enum VideoArrangement: Equatable {
    case horizontal
    case vertical
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Models/Export/VideoArrangement.swift
git commit -m "feat(export): add VideoArrangement enum"
```

---

### Task 2: VideoTransform struct

**Files:**
- Create: `golf-sync-swing/Models/Export/VideoTransform.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  VideoTransform.swift
//  golf-sync-swing
//
//  Per-video transform state owned by the editor and read by the exporter.
//

import CoreGraphics

struct VideoTransform: Equatable {
    var scale: CGFloat = 1.0
    var offset: CGPoint = .zero
    var containerSize: CGSize = .zero
    var isMuted: Bool = false

    static let identity = VideoTransform()
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Models/Export/VideoTransform.swift
git commit -m "feat(export): add VideoTransform value type"
```

---

### Task 3: ExportAspectRatio enum (with tests)

**Files:**
- Create: `golf-sync-swing/Models/Export/ExportAspectRatio.swift`
- Test: `golf-sync-swingTests/ExportAspectRatioTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//
//  ExportAspectRatioTests.swift
//  golf-sync-swingTests
//

import Testing
import CoreGraphics
@testable import golf_sync_swing

struct ExportAspectRatioTests {

    @Test("Side-by-side is 16:9 horizontal")
    func sideBySideIsLandscape() {
        let preset = ExportAspectRatio.sideBySide
        #expect(preset.exportSize == CGSize(width: 1920, height: 1080))
        #expect(preset.arrangement == .horizontal)
        #expect(abs(preset.ratio - (16.0 / 9.0)) < 0.001)
    }

    @Test("Vertical TikTok is 9:16 vertical")
    func tikTokIsPortrait() {
        let preset = ExportAspectRatio.tikTokVertical
        #expect(preset.exportSize == CGSize(width: 1080, height: 1920))
        #expect(preset.arrangement == .vertical)
    }

    @Test("Square is 1:1 horizontal arrangement by default")
    func squareIsHorizontal() {
        let preset = ExportAspectRatio.square
        #expect(preset.exportSize == CGSize(width: 1080, height: 1080))
        #expect(preset.arrangement == .horizontal)
    }

    @Test("Arrangement derives from aspect: wide → horizontal, tall → vertical")
    func arrangementMatchesAspect() {
        for preset in ExportAspectRatio.allCases {
            if preset.exportSize.width > preset.exportSize.height {
                #expect(preset.arrangement == .horizontal, "Expected horizontal for \(preset.displayName)")
            } else if preset.exportSize.width < preset.exportSize.height {
                #expect(preset.arrangement == .vertical, "Expected vertical for \(preset.displayName)")
            } else {
                #expect(preset.arrangement == .horizontal, "Square defaults to horizontal")
            }
        }
    }

    @Test("Export sizes are even (codec-friendly)")
    func exportSizesEven() {
        for preset in ExportAspectRatio.allCases {
            #expect(Int(preset.exportSize.width) % 2 == 0, "\(preset.displayName) width odd")
            #expect(Int(preset.exportSize.height) % 2 == 0, "\(preset.displayName) height odd")
        }
    }

    @Test("All cases have non-empty display names")
    func displayNamesNotEmpty() {
        for preset in ExportAspectRatio.allCases {
            #expect(!preset.displayName.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails (compile error — type missing)**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:golf-sync-swingTests/ExportAspectRatioTests 2>&1 | tail -10`
Expected: Build error (`cannot find 'ExportAspectRatio' in scope`).

- [ ] **Step 3: Implement ExportAspectRatio**

```swift
//
//  ExportAspectRatio.swift
//  golf-sync-swing
//
//  Output aspect ratio presets for the export editor.
//  Lifted with adaptation from video-collage's AspectRatio enum.
//

import CoreGraphics

enum ExportAspectRatio: String, CaseIterable, Identifiable {
    case sideBySide        // 16:9 (also covers "Landscape")
    case tikTokVertical    // 9:16
    case square            // 1:1
    case instagramPortrait // 4:5
    case classicLandscape  // 4:3
    case classicPortrait   // 3:4
    case photoPortrait     // 2:3
    case photoLandscape    // 3:2
    case cinemascope       // 2.35:1
    case ultraWide         // 2:1
    case tallBanner        // 1:2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sideBySide:        return "Side-by-side"
        case .tikTokVertical:    return "Vertical (TikTok)"
        case .square:            return "Square"
        case .instagramPortrait: return "Instagram 4:5"
        case .classicLandscape:  return "Classic 4:3"
        case .classicPortrait:   return "Classic 3:4"
        case .photoPortrait:     return "Photo 2:3"
        case .photoLandscape:    return "Photo 3:2"
        case .cinemascope:       return "Cinemascope"
        case .ultraWide:         return "Ultra-wide"
        case .tallBanner:        return "Tall Banner"
        }
    }

    var exportSize: CGSize {
        switch self {
        case .sideBySide:        return CGSize(width: 1920, height: 1080)
        case .tikTokVertical:    return CGSize(width: 1080, height: 1920)
        case .square:            return CGSize(width: 1080, height: 1080)
        case .instagramPortrait: return CGSize(width: 1080, height: 1350)
        case .classicLandscape:  return CGSize(width: 1440, height: 1080)
        case .classicPortrait:   return CGSize(width: 1080, height: 1440)
        case .photoPortrait:     return CGSize(width: 1080, height: 1620)
        case .photoLandscape:    return CGSize(width: 1620, height: 1080)
        case .cinemascope:       return CGSize(width: 2540, height: 1080)
        case .ultraWide:         return CGSize(width: 2160, height: 1080)
        case .tallBanner:        return CGSize(width: 1080, height: 2160)
        }
    }

    var ratio: CGFloat { exportSize.width / exportSize.height }

    var arrangement: VideoArrangement {
        exportSize.width >= exportSize.height ? .horizontal : .vertical
    }

    var isPrimary: Bool {
        switch self {
        case .sideBySide, .tikTokVertical, .square: return true
        default: return false
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:golf-sync-swingTests/ExportAspectRatioTests 2>&1 | tail -20`
Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add golf-sync-swing/Models/Export/ExportAspectRatio.swift golf-sync-swingTests/ExportAspectRatioTests.swift
git commit -m "feat(export): add ExportAspectRatio enum with 11 presets + tests"
```

---

### Task 4: VideoLayoutConfig struct

**Files:**
- Create: `golf-sync-swing/Models/Export/VideoLayoutConfig.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  VideoLayoutConfig.swift
//  golf-sync-swing
//
//  The contract between the export editor and the exporter:
//  output aspect ratio + per-video transforms (always 2 entries in this app).
//

import Foundation

struct VideoLayoutConfig: Equatable {
    let aspectRatio: ExportAspectRatio
    let transforms: [VideoTransform]

    init(aspectRatio: ExportAspectRatio, transforms: [VideoTransform]) {
        precondition(transforms.count == 2, "VideoLayoutConfig must have exactly 2 transforms")
        self.aspectRatio = aspectRatio
        self.transforms = transforms
    }

    static func identity(aspectRatio: ExportAspectRatio) -> VideoLayoutConfig {
        var v1 = VideoTransform()
        var v2 = VideoTransform()
        v2.isMuted = true
        return VideoLayoutConfig(aspectRatio: aspectRatio, transforms: [v1, v2])
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Models/Export/VideoLayoutConfig.swift
git commit -m "feat(export): add VideoLayoutConfig contract"
```

---

### Task 5: ExportLayoutRenderer (pure render math, with tests)

**Files:**
- Create: `golf-sync-swing/Services/Export/ExportLayoutRenderer.swift`
- Test: `golf-sync-swingTests/ExportLayoutRendererTests.swift`

This task lifts the math from `VideoExportService.calculateTransform()` (lines 235–281 of the existing file) and extends it to honor user-applied scale + offset from the editor.

- [ ] **Step 1: Write the failing test**

```swift
//
//  ExportLayoutRendererTests.swift
//  golf-sync-swingTests
//

import Testing
import CoreGraphics
@testable import golf_sync_swing

struct ExportLayoutRendererTests {

    @Test("Identity transform: 1080x1920 video aspect-fit into 1080x960 cell yields contain")
    func identityAspectFit() {
        let videoSize = CGSize(width: 1080, height: 1920)
        let cellRect = CGRect(x: 0, y: 0, width: 1080, height: 960)
        let identity = VideoTransform()

        let t = ExportLayoutRenderer.transform(
            videoSize: videoSize,
            preferredTransform: .identity,
            cellRect: cellRect,
            userTransform: identity
        )

        // Aspect-fit scale = min(1080/1080, 960/1920) = 0.5
        #expect(abs(t.a - 0.5) < 0.001)
        #expect(abs(t.d - 0.5) < 0.001)

        // Center the scaled video (540×960) in the cell (1080×960):
        // x: (1080-540)/2 = 270; y: 0
        #expect(abs(t.tx - 270) < 0.5)
        #expect(abs(t.ty - 0) < 0.5)
    }

    @Test("User scale 2x doubles the effective scale of the transform")
    func userScaleMultipliesAspectFit() {
        let videoSize = CGSize(width: 1080, height: 1920)
        let cellRect = CGRect(x: 0, y: 0, width: 1080, height: 960)

        var user = VideoTransform()
        user.scale = 2.0
        user.containerSize = CGSize(width: 200, height: 178)

        let t = ExportLayoutRenderer.transform(
            videoSize: videoSize,
            preferredTransform: .identity,
            cellRect: cellRect,
            userTransform: user
        )

        // Aspect-fit (0.5) × user scale (2.0) = 1.0
        #expect(abs(t.a - 1.0) < 0.001)
        #expect(abs(t.d - 1.0) < 0.001)
    }

    @Test("User pan offset translates content within the cell")
    func userPanOffsetTranslates() {
        let videoSize = CGSize(width: 1080, height: 1920)
        let cellRect = CGRect(x: 0, y: 0, width: 1080, height: 960)

        var user = VideoTransform()
        user.offset = CGPoint(x: 50, y: 0) // 50pt right in preview
        user.containerSize = CGSize(width: 200, height: 178)

        let t = ExportLayoutRenderer.transform(
            videoSize: videoSize,
            preferredTransform: .identity,
            cellRect: cellRect,
            userTransform: user
        )

        // 50pt of 200pt preview = 25%, applied to 1080pt cell → 270pt right.
        // Identity baseline tx was 270 (centered); pan adds 270 → 540.
        #expect(abs(t.tx - 540) < 1.0)
    }

    @Test("Cell offset within render canvas is honored")
    func cellOriginIsRespected() {
        let videoSize = CGSize(width: 1080, height: 1920)
        // Bottom half of vertical TikTok layout
        let cellRect = CGRect(x: 0, y: 960, width: 1080, height: 960)
        let identity = VideoTransform()

        let t = ExportLayoutRenderer.transform(
            videoSize: videoSize,
            preferredTransform: .identity,
            cellRect: cellRect,
            userTransform: identity
        )

        // Vertical center of bottom cell = 960 + 480 = 1440. Aspect-fit centered there.
        // Y-translate should land scaled video centered in the bottom cell.
        // Scaled video height = 960; top of video at y=960; ty = 960.
        #expect(abs(t.ty - 960) < 1.0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails (type missing)**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:golf-sync-swingTests/ExportLayoutRendererTests 2>&1 | tail -10`
Expected: Compile error (`cannot find 'ExportLayoutRenderer' in scope`).

- [ ] **Step 3: Implement ExportLayoutRenderer**

```swift
//
//  ExportLayoutRenderer.swift
//  golf-sync-swing
//
//  Pure render math: maps editor transforms (preview-space points) to
//  AVMutableVideoCompositionLayerInstruction transforms (export pixels).
//
//  Math lifted from VideoExportService.calculateTransform() (aspect-fit + center)
//  and extended with user scale + pan from the editor.
//

import CoreGraphics
import AVFoundation

enum ExportLayoutRenderer {

    /// Returns the CGAffineTransform to feed into `AVMutableVideoCompositionLayerInstruction.setTransform`
    /// for one video, accounting for: rotation (preferredTransform), aspect-fit into the cell,
    /// user-applied pinch (scale), and user-applied pan (offset).
    static func transform(
        videoSize: CGSize,
        preferredTransform: CGAffineTransform,
        cellRect: CGRect,
        userTransform: VideoTransform
    ) -> CGAffineTransform {
        let displaySize = videoSize.applying(preferredTransform)
        let videoWidth = abs(displaySize.width)
        let videoHeight = abs(displaySize.height)

        let aspectFitScale = min(cellRect.width / videoWidth, cellRect.height / videoHeight)
        let totalScale = aspectFitScale * userTransform.scale

        var rotationOnly = preferredTransform
        rotationOnly.tx = 0
        rotationOnly.ty = 0

        var transform = CGAffineTransform.identity
        transform = transform.concatenating(rotationOnly)
        transform = transform.scaledBy(x: totalScale, y: totalScale)

        let bounding = boundingBox(of: videoSize, transformed: transform)

        let panInExport = panInExportPixels(
            userOffset: userTransform.offset,
            containerSize: userTransform.containerSize,
            cellRect: cellRect
        )

        let targetCenterX = cellRect.midX + panInExport.x
        let targetCenterY = cellRect.midY + panInExport.y

        transform.tx += targetCenterX - bounding.midX
        transform.ty += targetCenterY - bounding.midY

        return transform
    }

    private static func boundingBox(of videoSize: CGSize, transformed: CGAffineTransform) -> CGRect {
        let corners = [
            CGPoint.zero,
            CGPoint(x: videoSize.width, y: 0),
            CGPoint(x: videoSize.width, y: videoSize.height),
            CGPoint(x: 0, y: videoSize.height)
        ].map { $0.applying(transformed) }

        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func panInExportPixels(
        userOffset: CGPoint,
        containerSize: CGSize,
        cellRect: CGRect
    ) -> CGPoint {
        guard containerSize.width > 0 && containerSize.height > 0 else { return .zero }
        let scaleX = cellRect.width / containerSize.width
        let scaleY = cellRect.height / containerSize.height
        return CGPoint(x: userOffset.x * scaleX, y: userOffset.y * scaleY)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:golf-sync-swingTests/ExportLayoutRendererTests 2>&1 | tail -20`
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add golf-sync-swing/Services/Export/ExportLayoutRenderer.swift golf-sync-swingTests/ExportLayoutRendererTests.swift
git commit -m "feat(export): add ExportLayoutRenderer with pure render math + tests"
```

---

### Task 6: Refactor VideoExportService to accept VideoLayoutConfig

**Files:**
- Modify: `golf-sync-swing/Services/VideoExportService.swift`

This task adds a new `exportComparison(layoutConfig:...)` overload that uses `ExportLayoutRenderer` and honors `isMuted` per video. The existing `exportComparison(...)` keeps its signature for now (called from `ExportProgressView` until Task 14).

- [ ] **Step 1: Open the file**

Read: `golf-sync-swing/Services/VideoExportService.swift`

- [ ] **Step 2: Add the new overload**

Find the closing `}` of the `final class VideoExportService` (around line 326) and INSERT before it:

```swift
    // MARK: - Layout-config export (new)

    /// Export with explicit per-video transforms and an aspect-ratio-driven render size.
    static func exportComparison(
        layoutConfig: VideoLayoutConfig,
        video1URL: URL,
        video2URL: URL,
        syncOffset: TimeInterval,
        progress: @escaping (Float) -> Void,
        completion: @escaping (Result<URL, ExportError>) -> Void
    ) {
        Task {
            do {
                let outputURL = try await performLayoutExport(
                    layoutConfig: layoutConfig,
                    video1URL: video1URL,
                    video2URL: video2URL,
                    syncOffset: syncOffset,
                    progress: progress
                )
                await MainActor.run { completion(.success(outputURL)) }
            } catch let error as ExportError {
                await MainActor.run { completion(.failure(error)) }
            } catch {
                await MainActor.run { completion(.failure(.exportFailed(error.localizedDescription))) }
            }
        }
    }

    private static func performLayoutExport(
        layoutConfig: VideoLayoutConfig,
        video1URL: URL,
        video2URL: URL,
        syncOffset: TimeInterval,
        progress: @escaping (Float) -> Void
    ) async throws -> URL {
        let asset1 = AVURLAsset(url: video1URL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let asset2 = AVURLAsset(url: video2URL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        guard let track1 = try await asset1.loadTracks(withMediaType: .video).first,
              let track2 = try await asset2.loadTracks(withMediaType: .video).first else {
            throw ExportError.missingVideoTrack
        }

        let duration1 = try await asset1.load(.duration)
        let duration2 = try await asset2.load(.duration)

        let (v1Start, v2Start, effectiveDuration) = applySyncOffset(
            syncOffset: syncOffset, duration1: duration1, duration2: duration2
        )

        let composition = AVMutableComposition()
        guard let track1c = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let track2c = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.missingVideoTrack
        }
        try track1c.insertTimeRange(CMTimeRange(start: .zero, duration: duration1), of: track1, at: v1Start)
        try track2c.insertTimeRange(CMTimeRange(start: .zero, duration: duration2), of: track2, at: v2Start)

        // Audio per isMuted flag
        if !layoutConfig.transforms[0].isMuted,
           let audio1 = try await asset1.loadTracks(withMediaType: .audio).first,
           let audio1c = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audio1c.insertTimeRange(CMTimeRange(start: .zero, duration: duration1), of: audio1, at: v1Start)
        }
        if !layoutConfig.transforms[1].isMuted,
           let audio2 = try await asset2.loadTracks(withMediaType: .audio).first,
           let audio2c = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audio2c.insertTimeRange(CMTimeRange(start: .zero, duration: duration2), of: audio2, at: v2Start)
        }

        let renderSize = layoutConfig.aspectRatio.exportSize
        let videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
        videoComposition.renderSize = renderSize
        let frameRate1 = try await track1.load(.nominalFrameRate)
        let frameRate2 = try await track2.load(.nominalFrameRate)
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(frameRate1, frameRate2, 30)))

        let cells = cellRects(for: layoutConfig.aspectRatio)
        let size1 = try await track1.load(.naturalSize)
        let pref1 = try await track1.load(.preferredTransform)
        let size2 = try await track2.load(.naturalSize)
        let pref2 = try await track2.load(.preferredTransform)

        let layer1 = AVMutableVideoCompositionLayerInstruction(assetTrack: track1c)
        layer1.setTransform(
            ExportLayoutRenderer.transform(
                videoSize: size1, preferredTransform: pref1,
                cellRect: cells[0], userTransform: layoutConfig.transforms[0]
            ),
            at: .zero
        )
        let layer2 = AVMutableVideoCompositionLayerInstruction(assetTrack: track2c)
        layer2.setTransform(
            ExportLayoutRenderer.transform(
                videoSize: size2, preferredTransform: pref2,
                cellRect: cells[1], userTransform: layoutConfig.transforms[1]
            ),
            at: .zero
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: effectiveDuration)
        instruction.backgroundColor = UIColor.black.cgColor
        instruction.layerInstructions = [layer1, layer2]
        videoComposition.instructions = [instruction]

        return try await runExport(composition: composition, videoComposition: videoComposition, progress: progress)
    }

    /// Splits the export render canvas in half along the arrangement axis.
    private static func cellRects(for aspectRatio: ExportAspectRatio) -> [CGRect] {
        let size = aspectRatio.exportSize
        switch aspectRatio.arrangement {
        case .horizontal:
            let halfW = size.width / 2
            return [
                CGRect(x: 0,     y: 0, width: halfW, height: size.height),
                CGRect(x: halfW, y: 0, width: halfW, height: size.height)
            ]
        case .vertical:
            let halfH = size.height / 2
            return [
                CGRect(x: 0, y: 0,     width: size.width, height: halfH),
                CGRect(x: 0, y: halfH, width: size.width, height: halfH)
            ]
        }
    }

    private static func applySyncOffset(
        syncOffset: TimeInterval, duration1: CMTime, duration2: CMTime
    ) -> (v1Start: CMTime, v2Start: CMTime, effective: CMTime) {
        if syncOffset >= 0 {
            let v2 = CMTime(seconds: syncOffset, preferredTimescale: 600)
            return (.zero, v2, CMTimeMaximum(duration1, CMTimeAdd(v2, duration2)))
        } else {
            let v1 = CMTime(seconds: -syncOffset, preferredTimescale: 600)
            return (v1, .zero, CMTimeMaximum(CMTimeAdd(v1, duration1), duration2))
        }
    }

    private static func runExport(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        progress: @escaping (Float) -> Void
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_\(UUID().uuidString).mp4")
        var exportSucceeded = false
        defer {
            if !exportSucceeded { try? FileManager.default.removeItem(at: outputURL) }
        }

        var session: AVAssetExportSession?
        for preset in [AVAssetExportPreset1920x1080, AVAssetExportPresetHighestQuality, AVAssetExportPresetMediumQuality] {
            if let s = AVAssetExportSession(asset: composition, presetName: preset) {
                session = s
                break
            }
        }
        guard let exportSession = session else {
            throw ExportError.exportFailed("Could not create export session")
        }

        exportSession.videoComposition = videoComposition
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        let progressTask = Task {
            while !Task.isCancelled {
                await MainActor.run { progress(exportSession.progress) }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        await exportSession.export()
        progressTask.cancel()

        if exportSession.status == .completed {
            exportSucceeded = true
            return outputURL
        }
        let msg = exportSession.error?.localizedDescription ?? "Unknown error (status: \(exportSession.status.rawValue))"
        throw ExportError.exportFailed(msg)
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run all existing tests to confirm no regression**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -20`
Expected: Existing tests still pass; the 6+4 new tests from earlier tasks pass.

- [ ] **Step 5: Commit**

```bash
git add golf-sync-swing/Services/VideoExportService.swift
git commit -m "feat(export): add VideoLayoutConfig-driven export overload"
```

---

### Task 7: ZoomableVideoContainerView (UIKit)

**Files:**
- Create: `golf-sync-swing/Views/Export/Components/ZoomableVideoContainerView.swift`

Lifted from video-collage `Zoomable.swift` (gesture math), adapted to host an `AVPlayerLayer` and report transform changes via a closure.

- [ ] **Step 1: Create the file**

```swift
//
//  ZoomableVideoContainerView.swift
//  golf-sync-swing
//
//  UIKit container that renders a video via AVPlayerLayer and accepts
//  pinch-to-zoom + drag-to-pan gestures. Reports transform changes via
//  the `onChange` callback.
//
//  Gesture clamping logic ported from video-collage's Zoomable.swift.
//

import UIKit
import AVFoundation

final class ZoomableVideoContainerView: UIView {

    var player: AVPlayer? {
        didSet { playerLayer.player = player }
    }

    var transformState: VideoTransform {
        didSet { applyTransform() }
    }

    var onChange: ((VideoTransform) -> Void)?

    private let playerLayer = AVPlayerLayer()
    private let videoLayer = CALayer()

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    private var pinchStartScale: CGFloat = 1.0
    private var panStartOffset: CGPoint = .zero

    init(transform: VideoTransform = .identity) {
        self.transformState = transform
        super.init(frame: .zero)
        setupLayers()
        setupGestures()
        clipsToBounds = true
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setupLayers() {
        videoLayer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(videoLayer)
    }

    private func setupGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let panOne = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panOne.minimumNumberOfTouches = 1
        panOne.maximumNumberOfTouches = 1
        panOne.require(toFail: pinch)
        let panTwo = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panTwo.minimumNumberOfTouches = 2
        panTwo.maximumNumberOfTouches = 2

        addGestureRecognizer(pinch)
        addGestureRecognizer(panOne)
        addGestureRecognizer(panTwo)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoLayer.frame = bounds
        playerLayer.frame = bounds
        if transformState.containerSize != bounds.size {
            transformState.containerSize = bounds.size
            onChange?(transformState)
        }
        applyTransform()
    }

    private func applyTransform() {
        let scaleT = CGAffineTransform(scaleX: transformState.scale, y: transformState.scale)
        let translateT = CGAffineTransform(translationX: transformState.offset.x, y: transformState.offset.y)
        videoLayer.setAffineTransform(translateT.concatenating(scaleT))
    }

    @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
        switch gr.state {
        case .began:
            pinchStartScale = transformState.scale
        case .changed:
            let candidate = pinchStartScale * gr.scale
            transformState.scale = min(max(candidate, minScale), maxScale)
            transformState.offset = clampedOffset(transformState.offset, scale: transformState.scale)
            onChange?(transformState)
        case .ended, .cancelled:
            if transformState.scale <= 1.01 {
                UIView.animate(withDuration: 0.2) {
                    self.transformState.scale = 1.0
                    self.transformState.offset = .zero
                    self.applyTransform()
                }
                onChange?(transformState)
            }
        default: break
        }
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        switch gr.state {
        case .began:
            panStartOffset = transformState.offset
        case .changed:
            let translation = gr.translation(in: self)
            let scale = max(transformState.scale, 0.001)
            let candidate = CGPoint(
                x: panStartOffset.x + translation.x / scale,
                y: panStartOffset.y + translation.y / scale
            )
            transformState.offset = clampedOffset(candidate, scale: transformState.scale)
            onChange?(transformState)
        default: break
        }
    }

    private func clampedOffset(_ candidate: CGPoint, scale: CGFloat) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0, scale > 1.0 else { return .zero }
        let maxX = (bounds.width  * (scale - 1)) / (2 * scale)
        let maxY = (bounds.height * (scale - 1)) / (2 * scale)
        return CGPoint(
            x: min(max(candidate.x, -maxX), maxX),
            y: min(max(candidate.y, -maxY), maxY)
        )
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Views/Export/Components/ZoomableVideoContainerView.swift
git commit -m "feat(export): add ZoomableVideoContainerView (UIKit pinch+pan host)"
```

---

### Task 8: ZoomableVideoTile (SwiftUI bridge)

**Files:**
- Create: `golf-sync-swing/Views/Export/Components/ZoomableVideoTile.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  ZoomableVideoTile.swift
//  golf-sync-swing
//
//  SwiftUI bridge over ZoomableVideoContainerView. Binds VideoTransform
//  and the AVPlayer to the underlying UIKit container.
//

import SwiftUI
import AVFoundation

struct ZoomableVideoTile: UIViewRepresentable {
    let player: AVPlayer
    @Binding var transform: VideoTransform

    func makeUIView(context: Context) -> ZoomableVideoContainerView {
        let view = ZoomableVideoContainerView(transform: transform)
        view.player = player
        view.onChange = { newTransform in
            DispatchQueue.main.async {
                if transform != newTransform { transform = newTransform }
            }
        }
        return view
    }

    func updateUIView(_ uiView: ZoomableVideoContainerView, context: Context) {
        uiView.player = player
        if uiView.transformState != transform {
            uiView.transformState = transform
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Views/Export/Components/ZoomableVideoTile.swift
git commit -m "feat(export): add ZoomableVideoTile SwiftUI bridge"
```

---

### Task 9: MuteToggleButton

**Files:**
- Create: `golf-sync-swing/Views/Export/Components/MuteToggleButton.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  MuteToggleButton.swift
//  golf-sync-swing
//

import SwiftUI

struct MuteToggleButton: View {
    @Binding var isMuted: Bool

    var body: some View {
        Button { isMuted.toggle() } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(Circle().fill(.black.opacity(0.55)))
        }
        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Views/Export/Components/MuteToggleButton.swift
git commit -m "feat(export): add MuteToggleButton overlay"
```

---

### Task 10: EditorCanvas

**Files:**
- Create: `golf-sync-swing/Views/Export/Components/EditorCanvas.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  EditorCanvas.swift
//  golf-sync-swing
//
//  Arranges two zoomable tiles side-by-side or stacked, sized to fit
//  the chosen export aspect ratio inside the available preview area.
//

import SwiftUI
import AVFoundation

struct EditorCanvas: View {
    let aspectRatio: ExportAspectRatio
    let player1: AVPlayer
    let player2: AVPlayer
    @Binding var transform1: VideoTransform
    @Binding var transform2: VideoTransform

    var body: some View {
        GeometryReader { geo in
            let canvas = sizeFitting(aspectRatio: aspectRatio.ratio, into: geo.size)
            arrangedTiles(canvas: canvas)
                .frame(width: canvas.width, height: canvas.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func arrangedTiles(canvas: CGSize) -> some View {
        switch aspectRatio.arrangement {
        case .horizontal:
            HStack(spacing: 0) {
                tile(player: player1, transform: $transform1)
                tile(player: player2, transform: $transform2)
            }
        case .vertical:
            VStack(spacing: 0) {
                tile(player: player1, transform: $transform1)
                tile(player: player2, transform: $transform2)
            }
        }
    }

    private func tile(player: AVPlayer, transform: Binding<VideoTransform>) -> some View {
        ZStack(alignment: .bottomLeading) {
            ZoomableVideoTile(player: player, transform: transform)
            MuteToggleButton(isMuted: Binding(
                get: { transform.wrappedValue.isMuted },
                set: { transform.wrappedValue.isMuted = $0 }
            ))
            .padding(8)
        }
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

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Views/Export/Components/EditorCanvas.swift
git commit -m "feat(export): add EditorCanvas (HSTACK/VSTACK arrangement)"
```

---

### Task 11: ExportEditorViewModel (with tests)

**Files:**
- Create: `golf-sync-swing/ViewModels/ExportEditorViewModel.swift`
- Test: `golf-sync-swingTests/ExportEditorViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//
//  ExportEditorViewModelTests.swift
//  golf-sync-swingTests
//

import Testing
import CoreGraphics
@testable import golf_sync_swing

struct ExportEditorViewModelTests {

    @Test("Default transforms: video1 unmuted, video2 muted")
    func defaultMuteState() {
        let vm = ExportEditorViewModel.makeForTesting(aspectRatio: .tikTokVertical)

        #expect(vm.transforms[0].isMuted == false)
        #expect(vm.transforms[1].isMuted == true)
    }

    @Test("buildLayoutConfig returns current state")
    func buildLayoutConfigReflectsState() {
        let vm = ExportEditorViewModel.makeForTesting(aspectRatio: .square)

        vm.transforms[0].scale = 1.5
        vm.transforms[1].isMuted = false

        let config = vm.buildLayoutConfig()

        #expect(config.aspectRatio == .square)
        #expect(config.transforms.count == 2)
        #expect(abs(config.transforms[0].scale - 1.5) < 0.001)
        #expect(config.transforms[1].isMuted == false)
    }

    @Test("Toggle mute mutates the right transform only")
    func toggleMuteIsolated() {
        let vm = ExportEditorViewModel.makeForTesting(aspectRatio: .sideBySide)
        let initial1 = vm.transforms[0].isMuted

        vm.toggleMute(at: 1)

        #expect(vm.transforms[0].isMuted == initial1)
        #expect(vm.transforms[1].isMuted == false) // was true by default → toggled to false
    }
}
```

- [ ] **Step 2: Run test to verify it fails (type missing)**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:golf-sync-swingTests/ExportEditorViewModelTests 2>&1 | tail -10`
Expected: Compile error.

- [ ] **Step 3: Implement ExportEditorViewModel**

```swift
//
//  ExportEditorViewModel.swift
//  golf-sync-swing
//
//  Owns the editor's two AVPlayers, per-video transforms, and exposes
//  the methods the editor view binds to. Pure logic for transforms is
//  testable without spinning up real AVPlayers.
//

import Foundation
import AVFoundation
import Observation

@Observable
final class ExportEditorViewModel {

    let aspectRatio: ExportAspectRatio
    var transforms: [VideoTransform]
    var isPlaying: Bool = true

    private(set) var player1: AVPlayer?
    private(set) var player2: AVPlayer?

    private let video1URL: URL?
    private let video2URL: URL?
    private let swing1: SwingTimeRange?
    private let swing2: SwingTimeRange?
    private let syncOffset: TimeInterval

    private var loopObserver1: Any?
    private var loopObserver2: Any?

    init(
        aspectRatio: ExportAspectRatio,
        video1URL: URL,
        video2URL: URL,
        swing1: SwingTimeRange,
        swing2: SwingTimeRange,
        syncOffset: TimeInterval
    ) {
        self.aspectRatio = aspectRatio
        self.video1URL = video1URL
        self.video2URL = video2URL
        self.swing1 = swing1
        self.swing2 = swing2
        self.syncOffset = syncOffset
        self.transforms = Self.defaultTransforms()
    }

    /// Test-only init — no AVPlayers, just transforms.
    private init(aspectRatio: ExportAspectRatio) {
        self.aspectRatio = aspectRatio
        self.video1URL = nil
        self.video2URL = nil
        self.swing1 = nil
        self.swing2 = nil
        self.syncOffset = 0
        self.transforms = Self.defaultTransforms()
    }

    static func makeForTesting(aspectRatio: ExportAspectRatio) -> ExportEditorViewModel {
        ExportEditorViewModel(aspectRatio: aspectRatio)
    }

    private static func defaultTransforms() -> [VideoTransform] {
        var v1 = VideoTransform()
        var v2 = VideoTransform()
        v2.isMuted = true
        return [v1, v2]
    }

    func setupPlayers() {
        guard let url1 = video1URL, let url2 = video2URL,
              let s1 = swing1, let s2 = swing2 else { return }
        let p1 = AVPlayer(url: url1)
        let p2 = AVPlayer(url: url2)
        seek(player: p1, to: s1.startTime)
        seek(player: p2, to: s2.startTime)
        installLoopObservers(p1: p1, p2: p2, s1: s1, s2: s2)
        self.player1 = p1
        self.player2 = p2
        play()
    }

    func play() {
        player1?.play()
        player2?.play()
        isPlaying = true
    }

    func pause() {
        player1?.pause()
        player2?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func toggleMute(at index: Int) {
        guard transforms.indices.contains(index) else { return }
        transforms[index].isMuted.toggle()
    }

    func buildLayoutConfig() -> VideoLayoutConfig {
        VideoLayoutConfig(aspectRatio: aspectRatio, transforms: transforms)
    }

    func cleanup() {
        if let o = loopObserver1 { player1?.removeTimeObserver(o); loopObserver1 = nil }
        if let o = loopObserver2 { player2?.removeTimeObserver(o); loopObserver2 = nil }
        player1?.pause(); player2?.pause()
        player1 = nil; player2 = nil
    }

    private func seek(player: AVPlayer, to time: TimeInterval) {
        let cm = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func installLoopObservers(p1: AVPlayer, p2: AVPlayer, s1: SwingTimeRange, s2: SwingTimeRange) {
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        loopObserver1 = p1.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak p1] _ in
            guard let self, let player = p1 else { return }
            if player.currentTime().seconds >= s1.endTime - 0.01 {
                self.seek(player: player, to: s1.startTime)
                if let p2 = self.player2 { self.seek(player: p2, to: s2.startTime) }
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:golf-sync-swingTests/ExportEditorViewModelTests 2>&1 | tail -20`
Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add golf-sync-swing/ViewModels/ExportEditorViewModel.swift golf-sync-swingTests/ExportEditorViewModelTests.swift
git commit -m "feat(export): add ExportEditorViewModel + tests"
```

---

### Task 12: ExportEditorView

**Files:**
- Create: `golf-sync-swing/Views/Export/ExportEditorView.swift`

- [ ] **Step 1: Create the file**

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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                topBar
                canvas
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { viewModel.setupPlayers() }
        .onDisappear { viewModel.cleanup() }
    }

    private var topBar: some View {
        HStack {
            Button { onCancel() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            Spacer()
            Text(viewModel.aspectRatio.displayName)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var canvas: some View {
        if let p1 = viewModel.player1, let p2 = viewModel.player2 {
            EditorCanvas(
                aspectRatio: viewModel.aspectRatio,
                player1: p1,
                player2: p2,
                transform1: $viewModel.transforms[0],
                transform2: $viewModel.transforms[1]
            )
        } else {
            Spacer()
            ProgressView().tint(.white)
            Spacer()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Text("Pinch to zoom · Drag to position · Tap speaker to mute")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Button { onExport(viewModel.buildLayoutConfig()) } label: {
                Text("Export")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Views/Export/ExportEditorView.swift
git commit -m "feat(export): add ExportEditorView"
```

---

### Task 13: AspectRatioPickerView

**Files:**
- Create: `golf-sync-swing/Views/Export/AspectRatioPickerView.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  AspectRatioPickerView.swift
//  golf-sync-swing
//

import SwiftUI

struct AspectRatioPickerView: View {
    let onSelect: (ExportAspectRatio) -> Void
    let onCancel: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                topBar
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        section(title: "Popular", presets: ExportAspectRatio.allCases.filter(\.isPrimary))
                        section(title: "More", presets: ExportAspectRatio.allCases.filter { !$0.isPrimary })
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button { onCancel() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            Spacer()
            Text("Choose Format")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func section(title: String, presets: [ExportAspectRatio]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(presets) { preset in
                    AspectRatioCard(preset: preset) { onSelect(preset) }
                }
            }
        }
    }
}

private struct AspectRatioCard: View {
    let preset: ExportAspectRatio
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                preview
                Text(preset.displayName)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var preview: some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(0.15))
            arrangementShape
        }
        .aspectRatio(preset.ratio, contentMode: .fit)
        .frame(height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var arrangementShape: some View {
        switch preset.arrangement {
        case .horizontal:
            HStack(spacing: 2) {
                Rectangle().fill(Color.green.opacity(0.6))
                Rectangle().fill(Color.blue.opacity(0.6))
            }
        case .vertical:
            VStack(spacing: 2) {
                Rectangle().fill(Color.green.opacity(0.6))
                Rectangle().fill(Color.blue.opacity(0.6))
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Views/Export/AspectRatioPickerView.swift
git commit -m "feat(export): add AspectRatioPickerView with primary + more sections"
```

---

### Task 14: Modify ExportProgressView to accept VideoLayoutConfig

**Files:**
- Modify: `golf-sync-swing/Views/Components/ExportProgressView.swift`

- [ ] **Step 1: Add `layoutConfig` parameter**

Open the file. Find the property block (around lines 8–13):

```swift
struct ExportProgressView: View {
    let viewModel: ComparisonViewModel
    @Binding var isExporting: Bool
    @Binding var progress: Float
    let onDismiss: () -> Void
```

Change to:

```swift
struct ExportProgressView: View {
    let viewModel: ComparisonViewModel
    let layoutConfig: VideoLayoutConfig?
    @Binding var isExporting: Bool
    @Binding var progress: Float
    let onDismiss: () -> Void

    init(
        viewModel: ComparisonViewModel,
        layoutConfig: VideoLayoutConfig? = nil,
        isExporting: Binding<Bool>,
        progress: Binding<Float>,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.layoutConfig = layoutConfig
        self._isExporting = isExporting
        self._progress = progress
        self.onDismiss = onDismiss
    }
```

- [ ] **Step 2: Update startExport() to honor layoutConfig**

Find `startExport()` (around lines 236–265). Replace its body with:

```swift
    func startExport() {
        guard let url1 = viewModel.video1.validLocalURL,
              let url2 = viewModel.video2.validLocalURL else {
            errorMessage = "One or both video files are missing. Please re-import the videos."
            return
        }

        isExporting = true
        progress = 0
        errorMessage = nil

        if let config = layoutConfig {
            VideoExportService.exportComparison(
                layoutConfig: config,
                video1URL: url1,
                video2URL: url2,
                syncOffset: viewModel.syncOffset,
                progress: { p in Task { @MainActor in progress = p } },
                completion: handleExportResult
            )
        } else {
            let config = VideoExportService.ExportConfiguration(resolution: selectedQuality.resolution)
            VideoExportService.exportComparison(
                video1URL: url1,
                video2URL: url2,
                syncOffset: viewModel.syncOffset,
                config: config,
                progress: { p in Task { @MainActor in progress = p } },
                completion: handleExportResult
            )
        }
    }

    func handleExportResult(_ result: Result<URL, VideoExportService.ExportError>) {
        isExporting = false
        switch result {
        case .success(let url): exportedURL = url
        case .failure(let error): errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 3: Hide the quality picker when layoutConfig is provided**

Find `preExportView` (around line 63). Replace the body with:

```swift
    var preExportView: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(layoutConfig != nil
                 ? "Export at \(layoutConfig!.aspectRatio.displayName) (\(Int(layoutConfig!.aspectRatio.exportSize.width))×\(Int(layoutConfig!.aspectRatio.exportSize.height)))"
                 : "Export side-by-side comparison video")
                .font(.headline)
                .multilineTextAlignment(.center)

            if layoutConfig == nil {
                qualityPicker
            }

            exportButton
        }
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run all tests to confirm no regression**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -20`
Expected: All previously passing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add golf-sync-swing/Views/Components/ExportProgressView.swift
git commit -m "feat(export): ExportProgressView accepts VideoLayoutConfig"
```

---

### Task 15: ExportFlowCoordinator

**Files:**
- Create: `golf-sync-swing/Views/Export/ExportFlowCoordinator.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  ExportFlowCoordinator.swift
//  golf-sync-swing
//
//  Hosts the 3-step export flow: aspect picker → editor → progress.
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

    @State private var step: Step = .picker
    @State private var selectedAspect: ExportAspectRatio?
    @State private var pendingConfig: VideoLayoutConfig?
    @State private var isExporting = false
    @State private var progress: Float = 0

    enum Step: Equatable {
        case picker
        case editor(ExportAspectRatio)
        case progress(VideoLayoutConfig)
    }

    var body: some View {
        Group {
            switch step {
            case .picker:
                AspectRatioPickerView(
                    onSelect: { aspect in
                        selectedAspect = aspect
                        step = .editor(aspect)
                    },
                    onCancel: onDismiss
                )
            case .editor(let aspect):
                editor(aspect: aspect)
            case .progress(let config):
                progressSheet(config: config)
            }
        }
    }

    private func editor(aspect: ExportAspectRatio) -> some View {
        let vm = ExportEditorViewModel(
            aspectRatio: aspect,
            video1URL: video1URL,
            video2URL: video2URL,
            swing1: swing1,
            swing2: swing2,
            syncOffset: syncOffset
        )
        return ExportEditorView(
            viewModel: vm,
            onCancel: { step = .picker },
            onExport: { config in
                pendingConfig = config
                step = .progress(config)
            }
        )
    }

    private func progressSheet(config: VideoLayoutConfig) -> some View {
        ExportProgressView(
            viewModel: comparisonViewModel,
            layoutConfig: config,
            isExporting: $isExporting,
            progress: $progress,
            onDismiss: onDismiss
        )
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **` (Task 14 already added the `layoutConfig:` parameter to `ExportProgressView`).

- [ ] **Step 3: Commit**

```bash
git add golf-sync-swing/Views/Export/ExportFlowCoordinator.swift
git commit -m "feat(export): add ExportFlowCoordinator (3-step host)"
```

---

### Task 16: Modify ComparisonView to launch ExportFlowCoordinator

**Files:**
- Modify: `golf-sync-swing/Views/ComparisonView.swift`

- [ ] **Step 1: Replace the export sheet with ExportFlowCoordinator**

Find the `exportSheet` computed view in the file (likely an extension below the body). Open the file and locate it via:

```bash
grep -n "exportSheet\|showExportSheet" golf-sync-swing/Views/ComparisonView.swift
```

The sheet content currently presents `ExportProgressView` directly. Replace its body to present `ExportFlowCoordinator` instead. The exact edit:

Find the block (most likely a computed `var exportSheet: some View` or inline `.sheet { ... }` content) and change it so the sheet body becomes:

```swift
    @ViewBuilder
    var exportSheet: some View {
        if let viewModel,
           let url1 = video1.validLocalURL,
           let url2 = video2.validLocalURL {
            ExportFlowCoordinator(
                video1URL: url1,
                video2URL: url2,
                swing1: swing1,
                swing2: swing2,
                syncOffset: viewModel.syncOffset,
                comparisonViewModel: viewModel,
                onDismiss: { showExportSheet = false }
            )
        } else {
            Text("Videos unavailable")
                .padding()
                .onAppear { showExportSheet = false }
        }
    }
```

If `exportSheet` does not currently exist as a named computed property, add the above as an extension below the body and reference it from `.sheet(isPresented: $showExportSheet) { exportSheet }` (which the file already has at line 44).

- [ ] **Step 2: Rename the trigger button text from "Export Video" to "Save & Export"**

Find line ~46:

```swift
            Button("Export Video") { showExportSheet = true }
```

Change to:

```swift
            Button("Save & Export") { showExportSheet = true }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run all tests**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -20`
Expected: All tests still pass (no test directly drives ComparisonView).

- [ ] **Step 5: Commit**

```bash
git add golf-sync-swing/Views/ComparisonView.swift
git commit -m "feat(export): wire ComparisonView to new ExportFlowCoordinator"
```

---

### Task 17: End-to-end manual verification (simulator)

**Files:**
- (No file changes; runtime verification.)

- [ ] **Step 1: Boot simulator and run the app**

Run: `xcodebuild -project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5` (verify build succeeds).

Then in Xcode (manual): cmd+R to launch the app on iPhone 17 simulator. (Pose detection isn't exercised here — the simulator limitation noted in CLAUDE.md does not block the export editor.)

- [ ] **Step 2: Verify entry flow**

In the app: pick two existing recorded swings → Compare → tap close (X) → confirmation dialog → tap **Save & Export**.

Expected: AspectRatioPickerView appears with "Popular" section (Side-by-side, Vertical TikTok, Square) and "More" section (the other 8 presets).

- [ ] **Step 3: Verify each primary aspect ratio**

For each of the 3 primary presets (Side-by-side, Vertical TikTok, Square):

1. Tap the preset card.
2. Verify the editor appears, both videos play synced, and the canvas matches the chosen aspect ratio (HSTACK for SBS / Square, VSTACK for Vertical).
3. Pinch one video to ~2× and verify it stays clipped to its tile and snaps back if released near 1×.
4. Drag a zoomed video and verify the pan is bounded inside the tile.
5. Tap the speaker icon on each video and verify the icon flips between speaker.wave.2.fill and speaker.slash.fill.
6. Tap **Export** → ExportProgressView appears with the chosen aspect ratio's resolution displayed.
7. Tap **Export** in ExportProgressView → progress bar advances → success state.
8. Tap **Save to Photos** → confirm save in Photos app.

- [ ] **Step 4: Verify "More" section**

Pick one preset from "More" (e.g., Cinemascope or Instagram Portrait) and run through the same verification (steps 3–7 above), focusing on the canvas aspect ratio looking correct.

- [ ] **Step 5: No commit needed (verification step)**

If any verification fails, file a follow-up bug report or fix on the spot. Manual verification is checked off only when all steps pass.

---

## Self-Review

(Performed at plan-write time; revise inline if issues found.)

**Spec coverage:**
- ✅ "Pre-export aspect-ratio picker" → Task 13
- ✅ "Per-video pinch-to-zoom + drag-to-position" → Tasks 7, 8
- ✅ "Per-video mute toggle" → Task 9
- ✅ "Synced playback during edit" → Task 11 (loop observer)
- ✅ "Export pipeline that translates editor transforms to pixels" → Tasks 5, 6
- ✅ "Existing premium gating untouched" → Task 14 leaves the quality picker in place when no `layoutConfig` is supplied (legacy fallback) and ExportProgressView's existing paywall logic stays unchanged
- ✅ Aspect ratios match spec table (Task 3 enum has all 11)
- ✅ "Side-by-side / Landscape merged" → single `.sideBySide` case
- ✅ Default mute (video1 unmuted, video2 muted) → `defaultTransforms()` in Task 11

**Placeholder scan:** None. All steps have actual code or commands.

**Type consistency:** `VideoTransform`, `VideoLayoutConfig`, `ExportAspectRatio`, `VideoArrangement`, `ExportLayoutRenderer` referenced consistently across tasks. The new `exportComparison(layoutConfig:...)` overload signature matches its usage in Task 14.

**Known caveats:**
- Manual verification step (Task 17) cannot be automated; flagged as such.
