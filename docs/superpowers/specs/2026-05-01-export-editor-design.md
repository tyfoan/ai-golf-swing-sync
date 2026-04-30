# Export Editor — Design Spec

**Date:** 2026-05-01
**Status:** Draft (awaiting user approval)
**Branch:** fix/tier-1-bug-audit (will move to dedicated branch on implementation)

## Problem

Today, exporting a golf-swing comparison from `ComparisonView` produces a single hardcoded side-by-side 16:9 layout. Users cannot:

1. Choose an aspect ratio suited to their target platform (TikTok 9:16, Instagram square 1:1, etc.).
2. Reposition or zoom either video within its tile, so impacts of different framings are forced into a generic crop.
3. Mute one video's audio (currently both audio tracks are mixed; double-thwack at impact is jarring).

The companion project at `~/Desktop/test/video-collage/` solves these problems for general-purpose video collages with a robust pinch-zoom-pan editor and a render pipeline backed by a custom `AVVideoCompositing`. We will adapt and integrate this capability into Golf Sync Swing as a dedicated **Export Editor** flow.

## Goals

- Pre-export aspect-ratio picker with the named primary presets — Side-by-side / Landscape (merged into a single 16:9 preset since both render identically), Vertical TikTok, Square — plus the additional ratios from video-collage.
- Per-video pinch-to-zoom + drag-to-position inside each tile.
- Per-video mute toggle (single button overlay).
- Synced playback during edit so the user sees what they will export.
- Export pipeline that translates editor transforms (preview points) into pixel-accurate output transforms.
- Existing premium gating (`exportHD`, `exportNoWatermark`) untouched; the editor itself is free.

## Non-goals

- Trim editing (already handled by `SwingTimeRange`).
- Drawing / annotation overlays.
- Overlay or onion-skin export (those are existing comparison modes — out of scope here).
- Watermark configuration UI (uses existing flag).
- Photo-only collage mode from video-collage.

## User flow

```
ComparisonView
  └─ "Save & Export" button   (replaces the existing "Export Video" entry in done dialog)
       └─ ExportFlowCoordinator (full-screen sheet)
            ├─ Step 1  AspectRatioPickerView      (pick one preset)
            ├─ Step 2  ExportEditorView           (pinch/pan + mute, both players synced)
            └─ Step 3  ExportProgressView (existing, repurposed) → Photos save
```

## Architecture

### New types

| Path | Purpose | LoC target |
|------|---------|-----------|
| `Models/Export/ExportAspectRatio.swift` | Enum of presets. Each case carries `displayName`, `ratio: CGFloat`, `exportSize: CGSize`, `arrangement: VideoArrangement`. Auto-derives arrangement: wide (≥1.0) → HSTACK, tall (<1.0) → VSTACK, exact 1.0 → HSTACK. | ≤ 120 |
| `Models/Export/VideoArrangement.swift` | `enum VideoArrangement { case horizontal, vertical }` — derived from aspect ratio. | ≤ 20 |
| `Models/Export/VideoTransform.swift` | `struct VideoTransform { var scale: CGFloat = 1.0; var offset: CGPoint = .zero; var containerSize: CGSize = .zero; var isMuted: Bool = false }`. Pure value type. | ≤ 30 |
| `Models/Export/VideoLayoutConfig.swift` | `struct VideoLayoutConfig { let aspectRatio: ExportAspectRatio; let transforms: [VideoTransform] }` — the contract between editor and exporter. Always has 2 transforms in this app. | ≤ 30 |
| `Views/Export/ExportFlowCoordinator.swift` | Hosts the 3 steps; owns `ExportFlowState` (selected aspect, in-progress transforms). | ≤ 150 |
| `Views/Export/AspectRatioPickerView.swift` | Scrollable grid of preset cards. The 4 named primary on top, additional ratios below under "More". Tap = select + advance. | ≤ 140 |
| `Views/Export/ExportEditorView.swift` | TopBar (close, aspect name, "Export" button) + EditorCanvas + bottom hint. | ≤ 120 |
| `Views/Export/Components/EditorCanvas.swift` | Picks HSTACK or VSTACK based on `arrangement`; sizes each tile to fill its half. Reserves space respecting the chosen aspect ratio inside the screen. | ≤ 80 |
| `Views/Export/Components/ZoomableVideoTile.swift` | `UIViewRepresentable` wrapping the UIKit class below; binds `VideoTransform`. | ≤ 80 |
| `Views/Export/Components/ZoomableVideoContainerView.swift` | UIKit `UIView` with `UIPinchGestureRecognizer` + 1-finger and 2-finger `UIPanGestureRecognizer`s; hosts `AVPlayerLayer`. Clamp `[1.0, 5.0]`, scale-aware pan bounds, snap-back at ≤1.01. **Lifted from video-collage `Zoomable.swift`**, adapted for our binding. | ≤ 190 |
| `Views/Export/Components/MuteToggleButton.swift` | Speaker icon overlay; binds `Bool`. | ≤ 30 |
| `ViewModels/ExportEditorViewModel.swift` | Owns 2 AVPlayers, synchronizer, `[VideoTransform]`, mute state. | ≤ 180 |
| `Services/Export/ExportLayoutRenderer.swift` | Pure render math: maps `VideoTransform` (preview coords) → `CGAffineTransform` (export pixels). Lifted formula: `panX = offset.x * scale * (mediaInExport / mediaInScreen)` + Y-flip. | ≤ 80 |

### Modified files

| File | Change |
|------|--------|
| `Services/VideoExportService.swift` | Replace hardcoded SBS layout with a `VideoLayoutConfig` parameter. Delete in-line `calculateTransform()`; delegate to new `ExportLayoutRenderer`. The audio mix loop reads `transform.isMuted` instead of muting video2 by default. Net: ~326 → ~150 LoC after extracting the renderer. |
| `Views/Recording/ComparisonView.swift` | Rename "Export Video" → "Save & Export"; replace direct sheet to `ExportProgressView` with a sheet to `ExportFlowCoordinator`. |
| `Views/ExportProgressView.swift` | Accept `VideoLayoutConfig` as init param (instead of generating a default internally); paywall + progress logic unchanged. |

## Data flow

1. `ComparisonView` passes `(video1URL, video2URL, swing1, swing2, syncOffset)` into `ExportFlowCoordinator`.
2. Picker step → coordinator state: `selectedAspect`. Default per-video transforms = identity (`scale=1, offset=.zero`). Default mute: `video1.isMuted=false`, `video2.isMuted=true` (single clean impact sound from reference clip).
3. Editor `onAppear`: `ExportEditorViewModel` builds two `AVPlayer` instances (loaded with `validLocalURL`), seeks each to `swing.startTime`, starts `ManualPlaybackSynchronizer` with offset `swing1.contactTime - swing2.contactTime`. Loops within swing bounds via existing pattern.
4. Pinch/pan gestures from each `ZoomableVideoContainerView` mutate `[VideoTransform]` via `Binding`. UI updates via SwiftUI invalidation; the `AVPlayerLayer` transform is also applied immediately inside the UIKit container so playback visuals update without a SwiftUI round-trip.
5. Tap "Export" → coordinator captures final `VideoLayoutConfig`, transitions to Step 3 (`ExportProgressView`) with that config.
6. `ExportProgressView` calls `VideoExportService.exportComparison(layoutConfig:)`.
7. Service builds `AVMutableComposition` (2 trimmed video tracks; sync offset applied as track insertion offset; audio per `isMuted` flags). Builds `AVMutableVideoComposition` with `renderSize = config.aspectRatio.exportSize`, custom layer instructions using `ExportLayoutRenderer.transform(forVideo:in:)`. Exports via `AVAssetExportSession`.
8. Saves to Photos via existing `saveToPhotos()` path. Cleans up temp files on completion.

### Sync & playback during edit

- Both `AVPlayer`s play synchronized using existing `ManualPlaybackSynchronizer` (40 ms drift correction). The user sees both videos playing in sync while panning/zooming.
- Loop within each swing's time range (existing logic in `ComparisonViewModel`, mirrored here).

## Render math (lifted from video-collage)

Given preview-time per-cell state `(scale: CGFloat, offset: CGPoint, containerSize: CGSize)` and export-time `cellRect: CGRect` in the export canvas, the render-time transform is:

```
contentOffsetX = offset.x * scale
contentOffsetY = offset.y * scale

panX =  contentOffsetX * (mediaSizeInExport.width  / mediaSizeInScreen.width)
panY = -contentOffsetY * (mediaSizeInExport.height / mediaSizeInScreen.height)   // Y-flip

flippedY = renderSize.height - cellRect.origin.y - cellRect.height

desiredCenter = (cellRect.origin.x + cellRect.width / 2 + panX,
                 flippedY            + cellRect.height / 2 + panY)

translation = desiredCenter - imageCenter
```

Where:

- `mediaSizeInScreen` = the source video's displayed size inside its tile in the editor preview, after aspect-fit into `containerSize` (e.g., a 1920×1080 source aspect-fit into a 200×356 portrait tile yields `mediaSizeInScreen = (200, 113)`).
- `mediaSizeInExport` = the same source aspect-fit into the cell's export-pixel rect (e.g., the same 1920×1080 source into a 1080×1920 cell yields `mediaSizeInExport = (1080, 608)`).
- `cellRect` = the cell's rect in export-canvas coordinates (UIKit-style top-left origin before the flip).
- `imageCenter` = the post-scale source image's geometric center inside the rendered frame, used as the reference point for translation.

The Y-flip is required because Core Image / Metal use a bottom-left-origin coordinate system, inverted from the UIKit space the editor draws in.

## Aspect ratio presets

| Preset | Ratio | Export size | Arrangement | Group |
|--------|-------|-------------|-------------|-------|
| Side-by-side | 16:9 | 1920×1080 | HSTACK | Primary (= Landscape — single preset) |
| Vertical TikTok | 9:16 | 1080×1920 | VSTACK | Primary |
| Square | 1:1 | 1080×1080 | HSTACK | Primary |
| Instagram Portrait | 4:5 | 1080×1350 | VSTACK | More |
| Classic Landscape | 4:3 | 1440×1080 | HSTACK | More |
| Classic Portrait | 3:4 | 1080×1440 | VSTACK | More |
| Photo Portrait | 2:3 | 1080×1620 | VSTACK | More |
| Photo Landscape | 3:2 | 1620×1080 | HSTACK | More |
| Cinemascope | 2.35:1 | 2540×1080 | HSTACK | More |
| Ultra-Wide | 2:1 | 2160×1080 | HSTACK | More |
| Tall Banner | 1:2 | 1080×2160 | VSTACK | More |

(iPhone 5.5"/5.8" device-specific presets from video-collage are excluded — legacy.)

The "Side-by-side" and "Landscape" labels in the original brief are merged into a single 16:9 HSTACK preset to avoid two presets that would render identically.

## Premium gating

Matches existing app pattern, no new gates introduced:

- Editor itself + all aspect ratios = **free** (drives engagement, showcases the app).
- HD/4K export quality + no-watermark = **premium** (existing `.exportHD` and `.exportNoWatermark` checked inside `ExportProgressView`).

## Error handling

- Aspect picker: no error states (selection only).
- Editor: `AVPlayer` load failure → alert + dismiss flow (existing pattern).
- Export: existing `ExportProgressView` error UI handles the `ExportError` cases (`.cancelled`, `.failed(reason)`, `.photosPermissionDenied`).
- Temp files: existing `cleanupOrphanedExports()` on completion and on app launch.

## Testing

### Unit
- `ExportAspectRatio.exportSize` width/height match declared ratio (within rounding tolerance — even pixels for codec compatibility).
- `VideoTransform` clamping: `scale` clamps to `[1.0, 5.0]`; pan bounds stay within `(±containerSize * (scale - 1)) / (2 * scale)`.
- `ExportLayoutRenderer.transform(forVideo:in:)`: given known `(scale=2, offset=(50,0))` on a `(1080, 1920)` canvas with a `(540, 960)` cell, expected `CGAffineTransform` matches the formula.

### Integration / VM
- `ExportEditorViewModel`: mutate transforms; `buildLayoutConfig()` returns a `VideoLayoutConfig` whose transforms reflect the latest edits.
- Mute toggle survives across edit session and is honored in the exported audio mix.

### Manual / device
- Each primary aspect ratio (4) renders correctly on physical iPhone (Vision pose deps not used here, so simulator may also work; physical device for AV pipeline confidence).
- Zoomed-in pan stays within bounds; snap-back at `scale ≤ 1.01`.
- Mute on video 2 → exported clip has no audio from video 2 source.

## CLAUDE.md compliance

- Every new file ≤ 200 LoC (largest is `ZoomableVideoContainerView` at ~190).
- All methods ≤ 15 LoC (gesture handlers split by phase: began / changed / ended).
- Composition over inheritance: `EditorCanvas` composes `ZoomableVideoTile`; coordinator composes 3 step views.
- Dependency injection: VM takes `synchronizer:` and `playerFactory:` for tests.
- `VideoExportService` shrinks (extracts `ExportLayoutRenderer`) — net codebase health improvement, not regression.

## Out of scope (future work, not this spec)

- Watermark customization UI (existing flag stays as-is).
- Reorderable video roles (always treats `video1` as reference).
- Background color or border styling per cell (video-collage feature, unused for golf comparisons).
- 4-up / N-video collages (this app only ever compares 2 swings).
- Cinemascope letterboxing options.

## Appendix — file paths reference

- Donor project gesture file: `~/Desktop/test/video-collage/video-collage/Extensions/Zoomable.swift`
- Donor project compositor: `~/Desktop/test/video-collage/video-collage/Services/Export/CollageVideoCompositor.swift`
- Donor project export service: `~/Desktop/test/video-collage/video-collage/Services/Export/CollageExportService.swift`
- Existing exporter: `golf-sync-swing/Services/VideoExportService.swift`
- Existing progress UI: `golf-sync-swing/Views/ExportProgressView.swift`
- Existing comparison entry: `golf-sync-swing/Views/Recording/ComparisonView.swift`
