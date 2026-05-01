# Export & Comparison Redesign — Design Spec

**Date:** 2026-05-01
**Status:** Draft (awaiting user approval)
**Branch:** fix/tier-1-bug-audit (work continues here)
**Supersedes parts of:** `docs/superpowers/specs/2026-05-01-export-editor-design.md`

## Problem

The current comparison + export experience has accumulated four bugs and three confusing concepts. Users opening a recorded video from history find a top-right share button that does nothing (`Button { }` placeholder in `PlayerTopBarView`). Users in the comparison view cannot reach export from the top bar — the only path is a "DONE" button at the bottom, which presents a confirmation dialog. The four comparison modes (`Side-By-Side`, `Synced`, `Onion Skin`, `Overlay`) conflate two orthogonal concerns (layout and timing) and are missing a "play one then the other" mode that users naturally expect. Additionally, the recently-shipped Export Editor (see prior spec) ships an 11-aspect-ratio picker as a separate step, which is over-configured for the current need.

## Goals

- Single, consistent export entry point (top-right icon) on both Single Video and Comparison screens.
- Three comparison modes that each map to one mental model.
- WYSIWYG export: whatever the user is currently watching is what gets exported, with one quick aspect toggle.
- Working "Export Swings Only" path from history view that concatenates a video's swings into one merged clip.
- Reduced configuration surface — drop the standalone aspect-ratio picker, drop the "DONE → Save & Export" detour.

## Non-goals

- No changes to swing detection, recording, or pose pipeline.
- No changes to monetization product/SKU mapping (RevenueCat). Premium feature flag set is reorganized but the entitlement string stays the same.
- No new export quality tiers (HD/4K gating remains as-is).

## Architecture overview

```
HistoryView ──▶ SingleVideoPlayerView ──▶ [↑ Export]
                                              │
                                              ▼
                                  SingleVideoExportSheet
                                  (no editor, native aspect,
                                   honors playback mode)
                                              │
                                              ▼
                                       Photos library

HomeView ──▶ ComparisonView ──▶ [↑ Export]
                                    │
                                    ▼
                       ExportEditorView (mode-aware)
                       (per-video framing + aspect toggle)
                                    │
                                    ▼
                           ExportProgressView ──▶ Photos
```

Two parallel export paths share a single backend service (`VideoExportService`) but are entered through their own UI flows, sized to the complexity of each surface.

## 1. Comparison modes (3, replacing 4)

### 1.1 The new modes

| Case | Free / Paid | Behavior | Aspect arrangements |
|------|-------------|----------|---------------------|
| `.sideBySide` | Free | Both videos visible, **always synced at impact**. Each loops within its swing window. | 16:9 → HSTACK; 9:16 → VSTACK; 1:1 → HSTACK |
| `.stacked` | Paid | Both videos overlaid full-canvas, opacity slider 0–100% controls video 2 transparency. (Onion-skin = set opacity ~30%.) | Single canvas, no arrangement axis |
| `.sequential` | Paid | Plays swing A start-to-end, then swing B start-to-end, loops. | Single canvas, no arrangement axis |

### 1.2 What's deleted

- `ComparisonMode.sideBySideSynced` — folded into `.sideBySide`. Sync is no longer optional.
- `ComparisonMode.onionSkin` — folded into `.stacked` (low-opacity preset emerges from slider).
- `ComparisonMode.overlay` — folded into `.stacked` (50/50 preset emerges from slider).

### 1.3 Premium gating

- Drop the three `synchronizedPlayback` / `onionSkinMode` / `overlayMode` premium feature flags.
- Add one new flag: `advancedComparisonModes`. Gates `.stacked` and `.sequential`.
- Existing `FeatureAccess.isUnlocked(.synchronizedPlayback)` call sites collapse to `FeatureAccess.isUnlocked(.advancedComparisonModes)`.
- RevenueCat entitlement string `"Golf Swing Sync Premium"` unchanged. The mapping from entitlement → feature flag updates internally.

## 2. ComparisonView layout

```
┌───────────────────────────────────────────┐
│ [✕]                            [↑ Share]  │  ← top bar
│                                           │
│           (video area)                    │
│                                           │
│                            [↔ Swap]       │  ← floating overlay, bottom-right
├───────────────────────────────────────────┤
│ [timeline]                                │
│ [sync offset strip — sideBySide only]     │
│ [▼ Mode: Side-by-Side]                    │
│ [opacity slider — stacked only]           │
│ [play / scrub / speed controls]           │
└───────────────────────────────────────────┘
```

Changes:
- **Top-right Export icon** added (`square.and.arrow.up`).
- **Swap arrows moved** from top-right to a floating circle button, bottom-right of the video area, ~16pt from edges.
- **DONE button removed** from the controls panel — its only useful action (Save & Export) is now the top-right icon, and dismiss is already covered by the top-left ✕.
- **Sync offset strip** still appears for `.sideBySide` (since it's now always synced). Hides for `.stacked` and `.sequential`.

## 3. SingleVideoPlayerView layout

No layout changes — only the broken share button gets wired:

- `PlayerTopBarView` line 71: `Button { }` becomes `Button { onExport() }`.
- `SingleVideoPlayerView` adds `@State private var showExportSheet = false` and presents `SingleVideoExportSheet` as a `.sheet(isPresented:)`.
- The mode picker (`Swings Only` / `Full Video`) is unchanged.

## 4. Comparison export flow (option B — editor only)

Tap top-right Export →

```
ExportEditorView (full-screen sheet)
├─ Header: ✕ cancel · "Export"
├─ Aspect toggle: [16:9] [9:16] [1:1]
│
├─ Editor canvas (matches current mode):
│   • .sideBySide   → 2 tiles arranged HSTACK or VSTACK per aspect
│   • .stacked      → 2 tiles overlaid full-canvas, video 2 at editor's
│                     `stackedOpacity` from the comparison view
│   • .sequential   → 1 full-canvas tile + segmented "Swing 1 / Swing 2"
│                     toggle to switch which swing's framing is being edited
│
├─ Per-video pinch/zoom/pan (Zoomable.swift, unchanged)
├─ Per-video mute toggle
├─ Trim-to-swing toggle (existing)
│
└─ [Export] → progress sheet → Photos save
```

The current `AspectRatioPickerView.swift` is deleted; the aspect toggle lives inline in the editor's header. `ExportFlowCoordinator` shrinks from 3 steps to 2 (editor → progress).

`VideoLayoutConfig` extends:

```swift
struct VideoLayoutConfig {
    let aspectRatio: ExportAspectRatio
    let mode: ComparisonMode               // NEW: drives compositor branch
    let stackedOpacity: CGFloat?           // NEW: only used when mode == .stacked
    let transforms: [VideoTransform]       // always size 2 (one per swing, all modes)
}
```

The editor's currently-selected sequential swing is local UI state on `ExportEditorViewModel` — it does not affect the export and does not belong on `VideoLayoutConfig`. At export time, both `transforms[0]` and `transforms[1]` are baked regardless of mode.

For `.sequential`, the editor renders one tile at a time. The user toggles which swing they're framing via a small segmented control above the tile. Each swing's `VideoTransform` (scale, offset, mute, container size) is preserved across toggles.

## 5. Single-video export flow (option C — sheet only, no editor)

Tap top-right Export → bottom sheet:

```
┌────────────────────────────────────────────┐
│   ✕                                        │
│                                            │
│   Export Swings Only                       │  ← when mode == .swingsOnly
│   3 swings · ~9 seconds total              │
│                                            │
│                  OR                        │
│                                            │
│   Export Full Video                        │  ← when mode == .fullVideo
│   Duration: 0:42                           │
│                                            │
│   [Export to Photos]                       │
└────────────────────────────────────────────┘
```

No aspect picker, no editor. Saves in the source video's native aspect. Justification: there's no composition decision (single source), so the configuration surface is minimal.

### 5.1 Swings-Only export composition

For `mode == .swingsOnly`:
- Iterate `video.swings` in chronological order.
- For each swing: insert `(start, end - start)` slice of the source video into a single composition track at the next available time.
- Audio: insert the corresponding audio slice from the source.
- No transitions, no labels, no separator (keeps expectations low and matches "highlight reel" feel).
- If `video.swings` is empty, the export icon is disabled (won't be tappable).

### 5.2 Full-Video export

For `mode == .fullVideo`:
- Insert the full source video into a composition track (effectively a copy).
- This goes through the export pipeline rather than a direct file-copy because we still want to standardize file format (MP4) and strip metadata that Photos doesn't need.

## 6. Backend changes

### 6.1 `VideoExportService`

New entry point for single-video paths:

```swift
static func exportSingleVideo(
    videoURL: URL,
    swings: [SwingTimeRange]?,             // nil → full video; non-nil → concatenate slices
    progress: @escaping (Float) -> Void,
    completion: @escaping (Result<URL, ExportError>) -> Void
)
```

Existing `exportComparison(layoutConfig:)` updated to honor the new `mode` field on `VideoLayoutConfig`. Implementation switches on layout:

- `.sideBySide` — current path (custom compositor, per-cell crop).
- `.stacked` — both cells set to full canvas, custom compositor branches on `stackedOpacity` to render video 2 with reduced alpha and composite over video 1.
- `.sequential` — bypasses the custom compositor entirely. Builds a single composition track with the two swing slices inserted back-to-back. Standard `AVMutableVideoComposition.videoComposition(withPropertiesOf:)` works fine since there's no overlap, no per-cell clipping needed.

### 6.2 `CollageVideoCompositor`

`configureShared(...)` extends to take a `layoutMode: CompositorLayout` parameter (`.sideBySide` | `.stacked`). The render path branches on that mode:

- `.sideBySide`: identity behavior — per-cell aspect-fit, transforms, then `cropped(to: cellRect)`.
- `.stacked`: cells are passed in with `cellRect == fullCanvas` for both. Per-cell crop becomes a no-op (the crop rect equals the canvas). Video 2 gets `applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])` before compositing over video 1.

Sequential mode never reaches the custom compositor (uses standard `videoComposition(withPropertiesOf:)` because there's no overlap between the two slices in time).

### 6.3 `ComparisonViewModel`

- Property rename: `onionSkinOpacity` → `stackedOpacity`.
- New property: `currentSequentialSwing: Int` (0 or 1) — which swing is currently playing in `.sequential` mode.
- All `if isSynchronized` branches deleted — `.sideBySide` always syncs at impact.
- Sync offset strip visibility: tied to `mode == .sideBySide` only.

## 7. Files retired or renamed

| File | Action |
|------|--------|
| `Views/Export/AspectRatioPickerView.swift` | Deleted — aspect toggle inline in editor |
| `ComparisonMode.sideBySideSynced` | Removed (folded into `.sideBySide`) |
| `ComparisonMode.onionSkin` | Removed (folded into `.stacked`) |
| `ComparisonMode.overlay` | Removed (folded into `.stacked`) |
| `PremiumFeature.synchronizedPlayback` | Removed |
| `PremiumFeature.onionSkinMode` | Removed |
| `PremiumFeature.overlayMode` | Removed |
| `PremiumFeature.advancedComparisonModes` | Added |

## 8. Migration

No persisted `ComparisonMode` exists — it's runtime-only state on `ComparisonViewModel`. The `ComparisonSession` SwiftData model holds only `video1`, `video2`, `syncOffset`, `createdAt` (and is currently unused — see model comment). No data migration needed; the enum rewrite is a pure compile-time change.

## 9. Testing strategy

### Unit (Swift Testing)

- `VideoExportService.exportSingleVideo(swings:nil)` — smoke test: full-video path produces a non-zero MP4.
- `VideoExportService.exportSingleVideo(swings:[...])` — smoke test: 3-swing concatenation produces an MP4 with duration ≈ sum of swing durations.
- `VideoLayoutConfig` — extended type validates all three `mode` cases construct cleanly.
- `CollageVideoCompositor` stacked path — verify that when `layoutMode == .stacked`, the configured `stackedOpacity` flows into the CIColorMatrix `inputAVector.w` parameter for video 2's render step (test the parameter construction, not actual pixel rendering — that requires a real `AVVideoCompositionRenderContext`).

### Manual (physical device, can't simulate compositor on simulator reliably)

- Single video, Full Video mode: export → check Photos has the original duration.
- Single video, Swings Only mode (3+ swings): export → check Photos has concatenated swings, no transitions.
- Comparison Side-by-Side mode: export at 16:9 and 9:16, verify cell clipping (no overlap when zoomed).
- Comparison Stacked mode: export at slider 30% and 70%, verify opacity is baked into the output.
- Comparison Sequential mode: export, verify swing A plays then swing B with no overlap.
- Swap button (bottom-right): tap, confirm videos exchange.

## 10. Risks and open questions

- **Sequential editor UX**: the segmented "Swing 1 / Swing 2" toggle is the simplest design but switches the visible video instantly. Alternative: thumbnail strip with both swings, tap to edit. Deferred to v2 if v1 confuses users.
- **Stacked export with opacity**: video 2's audio is muted by default in the editor (existing behavior); for `.stacked` mode that means the user only hears video 1 unless they toggle. Acceptable for v1.
- **Aspect ratios on sequential mode**: 16:9 source videos exported as 9:16 will letterbox unless the user pinches/pans to fill. The editor's per-swing pinch/pan addresses this; if confused, the docs should call it out.
- **DONE button removal**: a confirmation-dialog DONE button has been there since v1. Some users might rely on the explicit "Done" affordance. Mitigation: the top-left ✕ icon is the universal close pattern; if telemetry shows users hunting for a Done button, add one back.

## 11. Out of scope (future work)

- Sharing destinations beyond Photos (Messages, AirDrop, etc.) — covered by iOS share sheet on the saved file.
- Watermark customization — premium feature flag exists but is hard-coded to one watermark style.
- Per-swing labels in Sequential mode ("Swing 1", "Swing 2") — could be added in v2 if requested.
- Aspect ratio for Single Video export — kept native in v1; revisit if users ask for cropped exports of single videos.
