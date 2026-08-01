# Onboarding page 3: show what export produces

**Status:** approved 2026-07-30

## Problem

Onboarding page 3 reads "Frame-by-Frame Tools — 8× slow-mo, pro library, HD export."
Export is *mentioned* and never *shown*, so the two things a user would actually share —
a highlight reel of every detected swing, and a side-by-side against a pro — arrive as
words in a list. Neither is legible as an outcome worth paying for.

## Decision

Rework page 3 rather than add a fourth. Onboarding length is a conversion cost
(`CLAUDE.md`: "time to paywall — show value first, but don't wait too long"), and page 3
is currently a grab-bag rather than a single idea. Page count stays at three.

## Copy

| | Before | After |
|---|---|---|
| Title | Frame-by-Frame Tools | **Share Your Best Swings** |
| Subtitle | 8× slow-mo, pro library, HD export. | **Export a highlight reel or a side-by-side, in HD.** |
| CTA | Get Started | unchanged |

Slow-mo and the pro library lose their onboarding mention. Accepted: page 1 already sells
the pro comparison, and an outcome the user can post beats a feature list.

## Hero: `ExportShareMockup`

`OnboardingPageView` wraps `feature.heroBuilder()` in `PhoneFrameView`, so this component
is the inner content only. Usable canvas is **228 × 328** (260 × 360 less the frame's 16pt
inset).

Structure mirrors the mockup it replaces exactly: `VStack(spacing: 16) { stage; chip }`,
stage `RoundedRectangle(cornerRadius: 12)` filled `onboardingMidGreen.opacity(0.4)`,
height `200`.

**Beat 1 — 0 to 1.5s — the reel.** Four clip cards (`RoundedRectangle` r6, solid
`onboardingMidGreen`, each holding `figure.golf` at 18pt in `onboardingGold.opacity(0.7)`)
sit apart with a slight ±3° rotation. The gaps collapse to 2pt and the rotation goes to
zero, so the cards read as clips being stitched into one strip. A gold playhead sweeps
left to right across the joined strip.

**Beat 2 — 1.5 to 3.0s — the comparison.** The strip dissolves into two panes filling the
stage, split by a 1.5pt gold vertical. Each pane holds a golfer silhouette, labelled `YOU`
and `PRO` (`.caption2.weight(.bold)`, white at 0.5). Both panes pulse once in sync
(scale 1.0 → 1.04 → 1.0) against the gold divider — the visual claim is *aligned at
impact*, which is the product's whole premise.

The loop crossfades back to beat 1 at 3.0s. Period 3.0s,
`.repeatForever(autoreverses: false)` — the same curve family the existing heroes use.

**Chip.** A copy of `SlowMoToolsMockup.speedChip` down to the numbers:
`.caption2.weight(.bold)`, `onboardingGold`, padding 10/4, capsule fill
`onboardingGold.opacity(0.15)`, stroke `onboardingGold.opacity(0.4)` at 1pt. Text `HD`,
bottom-right. "HD" is not translated.

## Design tokens this must not deviate from

Taken from the current code, not from eyeballing:

- Title `.system(size: 28, weight: .bold)`, tracking `-0.4`, white, shadow `black 0.45, r10, y2`
- Subtitle `.system(size: 15)`, `white.opacity(0.68)`, lineSpacing `3`, maxWidth `290`,
  shadow `black 0.35, r6, y1`
- Title-to-subtitle gap `8`; horizontal padding `32`
- Phone frame `260×360`, corner radius `28`, gradient `onboardingDark → onboardingDeepGreen`,
  stroke `white.opacity(0.12)` at 1.5, shadow `black 0.4, r20, y8`, content inset `16`

## Accessibility

The new hero honours `\.accessibilityReduceMotion`: with it on, the composed end state is
drawn once and nothing animates. The three existing heroes ignore it; they are out of
scope here and are not being changed.

## Files

- NEW `golf-sync-swing/Views/Onboarding/HeroMockup/ExportShareMockup.swift`
- EDIT `golf-sync-swing/Views/Onboarding/OnboardingFeature.swift` — page 3 title, subtitle, `heroBuilder`
- EDIT `golf-sync-swing/Localizable.xcstrings` — add `Share Your Best Swings`,
  `Export a highlight reel or a side-by-side, in HD.`, `YOU`, `PRO` across the 12
  non-English locales; prune `Frame-by-Frame Tools` and `8× slow-mo, pro library, HD export.`
- DELETE `golf-sync-swing/Views/Onboarding/HeroMockup/SlowMoToolsMockup.swift` — its only
  reference was page 3

## Verification

Build, run in the simulator, screenshot page 3 and compare it against pages 1 and 2 for
typographic consistency. A browser mockup cannot settle this — only the app renders the
app's type.
