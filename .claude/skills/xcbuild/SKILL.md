---
name: xcbuild
description: Build and test the Golf Sync Swing iOS app on the iPhone 17 / iOS 26.1 simulator. Wraps xcodebuild with the project's required destination so the user can invoke /xcbuild build, /xcbuild test, or /xcbuild test <TestClass>/<testMethod>.
disable-model-invocation: true
---

# xcbuild

Run xcodebuild against the Golf Sync Swing project on the **iPhone 17** simulator (iOS 26.1) — the project's standard destination, NOT iPhone 16.

## Arguments

The user passes one of:

- `build` — build the app.
- `test` — run the full test suite.
- `test <TestClass>/<testMethod>` — run a single test (e.g. `test ImpactDetectorTests/testDetectsImpact`).
- `clean` — clean build folder, then build.

If no argument is given, default to `build`.

## What to run

Project base flags:

```
-project golf-sync-swing.xcodeproj -scheme golf-sync-swing -destination 'platform=iOS Simulator,name=iPhone 17'
```

| Argument | Command |
|---|---|
| `build` | `xcodebuild <base> build` |
| `test` | `xcodebuild <base> test` |
| `test X/Y` | `xcodebuild <base> -only-testing:golf-sync-swingTests/X/Y test` |
| `clean` | `xcodebuild <base> clean build` |

Use `xcbeautify` if installed (`command -v xcbeautify`) — pipe stdout through it for readable output. Otherwise pipe through `tail -100` so the model isn't drowned in noise; if the build fails, re-run without truncation and surface the error block.

## Expected destination quirks

- iOS Simulator does NOT support `VNDetectHumanBodyPoseRequest` — pose-dependent tests are gated with `.enabled(if: isPhysicalDevice)` and will skip. That is expected; do not flag skipped pose tests as failures.
- Expected baseline on simulator: 22 passed, 6 skipped, 0 failed.

## Reporting

After the run, report a one-line status:

- `✅ build OK` (build) or `✅ N passed, M skipped, 0 failed` (test)
- On failure, report the first failing test name + the error excerpt, and the full log path (`~/Library/Developer/Xcode/DerivedData/golf-sync-swing-*/Logs/Test`).
