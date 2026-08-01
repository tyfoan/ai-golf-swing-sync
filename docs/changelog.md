# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Changed (cold-start latency, 2026-08-01)
- **Camera bring-up is two orders of magnitude faster**: the capture graph now comes up
  in two phases. The preview pass builds only what a live frame needs (video input +
  video-data output — no microphone, no movie output, no AVAudioSession activation);
  the recording half is installed during the 5-second countdown against the already-
  running session. On-device probe: configure 56 ms + `startRunning` 217 ms (previously
  measured 7.2 s + 15.5–21.5 s on a cold launch), arm pass 350 ms hidden behind the
  first tick.
- **The CoreML classifier load is genuinely lazy**: `SwingClassifier` no longer starts
  the model load at construction (i.e. at tab mount, where the one-time ANE
  specialization competed with the camera bring-up); the load kicks off from the record
  tap only.
- **The idle preview no longer holds the microphone**: the mic joins the graph only for
  a take, and a cancelled or backgrounded countdown hands it straight back — the orange
  privacy indicator now appears during a take, not on the ready screen.
- **Onboarding page 3 hero swapped**: the export/share mockup replaces the slow-mo
  tools mockup, per the 2026-07-26 export-hero spec.

### Fixed (cold-start latency, 2026-08-01)
- **A failed `startRunning` no longer strands the screen on "Preparing camera…"
  forever**: the bring-up result is finally consumed — one silent retry a second later,
  then an alert whose OK re-attempts the bring-up. The failure also counts in analytics
  now (`camera_config_failed: start_running`); it was invisible in production.
- **Countdown tail feedback**: the ticks run while the recording pipeline installs; if
  the install outlives them, the digit no longer sits mute at "1" — the "Getting the
  camera ready…" caption covers the wait.
- **An arm failure's specific error is no longer clobbered** by the countdown's generic
  "Camera could not start" message.
- **A failed arm leaves the graph exactly as it found it**: previously a rejected movie
  output stranded an orphan microphone input in the session with no path that could
  ever remove it.

### Fixed (audit close-out, 2026-07-29)
- **The "off-main" save copy actually ran on the main thread**: under this project's
  `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` + `NonisolatedNonsendingByDefault` build
  settings, `nonisolated async` runs on the *caller's* actor and the unannotated
  `VideoStorageService` was implicitly `@MainActor` — so the whole-file copy still froze
  the UI. Now `@concurrent` + an explicitly `nonisolated` copy path (and a `nonisolated`
  `AppLogger`), genuinely off-main.
- **Post-restore heal duplicated every pro swing**: the record-exists-but-file-missing
  branch fell through to a fresh insert. It now heals the existing record in place —
  no more 19 duplicate rows after an iCloud restore.
- **`DetectionOrchestrator.stop()` no longer blocks the main thread** on an in-flight
  Vision pass: session-ID'd frames + delivery-time guards preserve the
  no-callback-after-stop invariant without the `processingQueue.sync` barrier.
- **String catalog caught up with the code**: the replay/paywall keys added in the last
  pass existed only in code; all now live in the catalog with translations for the 12
  non-English locales (paywall restore reuses the existing human-translated plural key).

### Fixed (adversarial review, 2026-07-29 — 27 confirmed findings, all addressed)
- **Stale recording delivery could kill and delete a live recording**: a slow finalize
  from a cancelled clip arriving mid-next-recording passed the discard check and was
  handled as the *current* recording (session paused, file deleted). Deliveries are now
  rejected on URL identity before both the error and success branches.
- **Capture screen had no exit in `.idle`/`.reviewing`**: as a full-screen modal, every
  failure path (zero-swing discard, Photos denied, paywall declined, persistence error)
  stranded the user. The close button now renders in all non-blocking states; the
  finalize watchdog also covers `.saving`, and save retries no longer duplicate clips
  in Photos.
- **Foreground/interruption handling**: returning to the app resumes the paused session
  (previously: dead preview until the user fiddled); the countdown aborts on session
  interruption instead of recording into a paused session.
- **`bringUpSession` reported success on configuration failure**, starting an empty
  session under a 5-second countdown to a black screen. Failure now propagates to the
  existing camera-error UI, and a failed reconfigure can no longer leave a detached
  movie output behind.
- **Pro-swing seeding and orphaned-export cleanup still hopped back to the main actor**
  (same implicit-`@MainActor` trap as the save copy). Seeding is now split-actor: file
  I/O and thumbnail decodes run `@concurrent`, only SwiftData mutations run on main;
  overlapping seed passes are serialized.
- **Sequential-mode export cropped (Standard) or letterboxed (HD) the output**: the
  render pipeline now builds explicit per-segment aspect-fit instructions instead of
  `videoComposition(withPropertiesOf:)` with a render-size override; also fixes the
  Square-aspect mismatch.
- **Revenue reporting**: the 48 h anti-replay window silently dropped renewals and
  trial→paid conversions observed later — it now applies only to the first-ever report
  on an install; `is_renewal` derives from subscription state (not device-local
  history); paid introductory offers are no longer reported at full standard price.
- **Skeleton overlay was horizontally flipped on the front camera**: mirroring now
  follows the preview-vs-buffer parity (`position == .front) != isVideoMirrored`).
- **Smaller ones**: comparison rebuilds drop stale results via a build-generation token
  and re-derive layout from live mode/swap state on install; MetricKit payloads are
  processed off-main and hop to the main actor only for analytics; preview-layer detach
  no longer blocks dismissal against an in-flight bring-up; `deactivate()` is wired into
  screen teardown (was dead code); export-quality subtitles and remaining new strings
  landed in the catalog for all 13 languages.

### Fixed (device round 4, 2026-07-30)
- **Comparison was completely broken** — every pair, not just new recordings: `"Couldn't load these
  videos…"`. Root cause proven by an A/B harness against real clips, and it was NOT the save-path
  change it looked like: `AVAssetTrack.asset` is a **weak** back-reference, so the earlier switch to
  async `loadTracks()` returned tracks whose `AVURLAsset` deallocated on return. The orphaned track
  still answers questions about itself, but `insertTimeRange` fails with `-11800` on every range,
  valid ones included — and a `try?` swallowed it into a bare nil. `SourceTracks` now keeps the
  assets alive for the build. Nothing on device needs recovering: paths and markers were always
  written correctly. The builder also returns a typed failure now (missing file / no video track /
  range outside video / alignment collapsed) instead of nil, logged and sent to the probe timeline.
- **The skeleton could not draw legs or head.** `BodyJointMap.connections` referenced `.leftKnee`,
  `.rightKnee` and `.nose` — none of which `PoseDetector.trackedJoints` extracted — so five bones
  were structurally undrawable. Two independent literals in two files had drifted; they now share a
  single source of truth. A joint dot is also drawn only where a bone landed on it, so a partially
  detected golfer no longer renders as a scatter of unconnected white spots.
- **The tab bar sat on top of the capture screen** through the countdown, the recording and the
  replay. Now hidden for the whole take as a pure function of state (so every exit path restores it),
  with `.reviewing` and `.saved` deliberately excluded — a finished take is a decision the user may
  walk away from, and the paywall itself tells them to go free a library slot.
- **Replay encode moved off the capture queue.** It ran inline in `captureOutput`, so replay
  resolution was capped by the detector's 33 ms frame budget rather than by the hardware. The capture
  callback now only memcpys into an app-owned bounded pool (3 slots, drops the oldest pending frame
  if the encoder falls behind, never blocks and never grows); scale + JPEG happen on a separate
  `.userInitiated` queue. Detection is strictly better off than before, and quality went 640 → 720px.
  Colour attachments are propagated with the copy, or the replay would render in a different colour
  space than the preview beside it.
- **Loading state is now a real progress bar** — black surface, white bar driven by actual frame
  readiness (`hasFrames(through:)`) with a deadline that degrades to a partial pull, not a spinner
  and not a fake animation. Shows on every detection, including later swings in the same take.

### Added (capture screen, 2026-07-29)
- **Swing replay on the capture screen, with a swappable picture-in-picture.** After a swing is
  detected the main surface loops a replay of it while the live camera moves into a 120×160 tile;
  tapping the tile swaps them. Settings → Recording chooses which surface holds the swing by default.
  Both surfaces are fed by a new in-memory `SwingFrameBuffer` (6 s ring, frames downscaled and
  JPEG-encoded inline in the capture callback, ~2–3 MB) — deliberately **not** from the in-progress
  recording file (opening it with `AVURLAsset` makes iOS terminate the capture) and **not** from a
  second `AVCaptureVideoPreviewLayer` (that is what blacked out the preview twice this week). The
  single preview layer stays mounted full-screen and never moves; a mode swap only changes what is
  drawn over it. Playback decodes on demand with a 6-frame cache, so peak bitmap memory (~3 MB) is
  lower than the old 240px eager decode despite double the resolution.
- **Preview is blurred while the camera comes up**, so the stuttering first frames of a cold
  bring-up no longer read as a broken picture; it clears when the session goes live.
- **Skeleton restyled**: 4pt white strokes with a glow and 6pt joints over a thin dark underlay, so
  it stays readable against sky, windows and white walls. The pose subscription is now released
  whenever the overlay is hidden — the default replay mode was paying 30 main-actor writes/sec for
  an overlay nothing drew.
- **On-device diagnostics harness** (`scripts/device-probe.sh`, DEBUG-only `DeviceProbe`): the app
  records a JSON timeline plus UI snapshots and real camera-frame JPEGs into its container, driven
  by a self-running scenario, and the host pulls them with `devicectl`. Every event carries
  `frames_seen`/`last_frame_age_s`, which mechanically separates "preview not attached" from "no
  frames arriving" — the ambiguity that cost three debugging rounds. UI snapshots cannot capture the
  camera preview (it is a render-server surface), so each carries `ui_excludes: camera_preview` and
  the frame JPEG is the only camera evidence. See `docs/device-debugging.md`.

### Changed (capture flow rebuilt, 2026-07-29 — from a device screen recording)
A 66-second screen recording made the cause unambiguous: every black preview coincided with a
**second `AVCaptureVideoPreviewLayer` being attached to the already-running session** — first the
capture screen's layer over the still-attached ready-screen layer (12 s of black with a frozen
countdown, while the preview *behind* it worked), then the PiP tile's layer at the first detected
swing (main preview blacked out, timer froze at 0:06.7).
- **One screen, one preview layer.** `CaptureScreen` is gone; the Camera tab is the capture UI, with
  chrome driven by state. Start Recording runs the countdown **in place** — nothing is presented and
  no layer is ever re-attached. This is what the user asked for: "if the camera is already on, tapping
  should just start the countdown."
- **PiP tile deleted** (with `DetectionBorderView`, `PipDisplayMode` and the replay/swap plumbing). It
  was hardcoded to `.liveCamera`, i.e. it showed the same feed as the full-screen preview behind it —
  it cost a second preview layer and bought nothing. Swing-count badge and detection flash remain.
- **Recordings save into the app, not the camera roll.** The automatic path no longer requests Photos
  authorization or runs a per-swing export — that export loop was the 18+ seconds of "Saving video…".
  A take is now copied into app storage with its swing markers in SwiftData, the same path imported
  videos already use. `PhotosSaveService` deleted. The explicit share/export action in the player is
  untouched and remains the only thing that asks for Photos permission. The library-cap gate still applies.
- **Tab bar is now reachable during a take** (the full-screen cover used to hide it), so leaving the
  Camera tab was re-specified per state: `.recording` stops through the normal finalize→save route
  instead of being abandoned running; `.reviewing` **preserves** the take (it previously deleted it —
  reachable by the exact path the paywall recommends: go to History, free a slot, come back);
  post-save navigation only fires if the user is still on the tab.
- Also fixed while in here: foreground no longer relights the camera while the user is on another tab
  (green privacy indicator + audio-route hijack), and camera authorization is re-read on every
  foreground so granting it in Settings takes effect without a relaunch.

### Fixed (third device test, 2026-07-29: 22.7s bring-up, black capture screen, silent discard)
Device CAMPERF evidence: `configureSession 7193ms` + `startRunning 15479ms` on first launch,
against `161ms` for the same session restarted warm. Root causes and fixes:
- **The black capture screen was self-inflicted**: the `isSessionRunning` gate added to
  `CameraPreviewView` earlier the same day meant `previewLayer.session` was never
  assigned while the session came up — an empty layer, not a stale frame. Gate deleted;
  the attach was already non-blocking via `sessionQueue`.
- **The countdown wait was unbounded** — this branch had replaced HEAD's 3 s bound with a
  bare `await`. Restored an 8 s deadline (polling the main-written mirror, never the
  session object), falling back to the existing retry prompt. `CountdownView` also
  animated its digit to `opacity 0` within 0.8 s and only re-animated on a count change,
  so a stalled countdown rendered as a black screen with *no digit at all*.
- **Start Recording is disabled until the session is running** ("Preparing camera…"),
  so the capture screen is never presented over a session that is still coming up — the
  wait now happens on the ready screen, which has a live preview to look at.
- **Session teardown moved off `onDisappear`**: presenting the capture screen fires
  `onDisappear` on the presenting view and SwiftUI does not order that against the
  `isCapturing` write — device logs caught it stopping the session under the capture
  screen. Now driven by `router.selectedTab`, which the tab bar writes synchronously.
- **`automaticallyConfiguresApplicationAudioSession = false`**: it was never set, so
  `AVCaptureSession` duplicated the app's own audio-session work inside `startRunning`
  (the 15.5 s phase; `FigAudioSession` errors bracket exactly that window). All five
  `startRunning` paths now route through one helper that establishes the audio session
  first, and the configured-flag is cleared wherever iOS invalidates it (pause, media
  services reset, interruption end).
- **Dead `AVCaptureAudioDataOutput` removed** along with its `.userInteractive` queue and
  delegate: `onAudioCaptured` was never assigned anywhere — the output received and
  dropped samples for the whole of every recording. The microphone *input* stays (the
  movie's audio track is consumed by export/comparison/Photos).
- **Format choice now takes the slowest sufficient frame rate** instead of the fastest,
  then pins 30 fps — previously it selected a high-frame-rate format only to clamp it,
  paying setup cost and risking silent stabilization downgrade. Plus `sessionQueue` at
  `.userInitiated`, `stopSession` refusing to disarm a live recording, `resumeSession`
  re-syncing its mirror, and per-phase timing probes inside the configurator.
- **Classifier warm-up moved out of `App.init`** into `activate()`: on device the CoreML
  load finished *after* `startRunning`, i.e. it had lengthened the very window it was
  added to protect.
- **The zero-swing silent delete is gone.** A take with no detected swing showed
  "Saving Video…" and then deleted the file, leaving a black screen — indistinguishable
  from a crash, and the guaranteed outcome of any indoor test. It now lands in review
  with "No swing detected" and the existing Save/Delete choice, emits an analytics event,
  and no longer triggers the App Store review prompt.

### Fixed (second device test, 2026-07-29: black preview at recording start)
- **Whole preview went black the moment recording began**: the PiP tile mounts exactly
  when `isRecording` flips, and its preview layer attached to the RUNNING session inline
  on the main thread — concurrently with the movie-output bootstrap mutating the same
  session graph on `sessionQueue`. Attach is now sequenced through `sessionQueue` (the
  mirror of the existing deferred detach), so live-session graph mutations are ordered.
- **Video stabilization moved to configure time**: setting it per-recording on a running
  session's connection rebuilds the capture pipeline at the exact moment recording
  starts (preview blanks). Now set once inside `begin/commitConfiguration`.
- **Live camera on the ready screen** (user request — matches Golf Swing Cam): the
  Camera tab now brings the session up on appear (async, session-queue only) and shows
  the preview under the framing guide; it stops on tab exit and pauses/resumes with
  scenePhase. Side effect: by the time the user taps Start Recording the session is
  already running, so the countdown ticks immediately — the cold bring-up happens
  behind the ready screen instead of behind a black countdown.

### Fixed (first-open camera contention, 2026-07-29 device test)
Device report: first capture open after install → black for seconds, ~5 fps preview,
one "Camera could not start", History lag; second open smooth. Diagnosis: one-time
first-launch work colliding with the camera's cold bring-up — the swing classifier's
first `MLModel.load` pays an on-device ANE specialization (cached afterwards) and it
fired exactly at first capture open; the preview-layer attach on the main thread also
raced the in-flight configure (CA fence timeout in the log). Hardened:
- **Classifier warm-up moved to `App.init`** (`SwingClassifier.warmUp()`): the one-time
  CoreML compile now runs while the user is on onboarding/Home, not during the first
  camera bring-up.
- **Preview attach deferred until the session is running**: `CameraPreviewView` no
  longer sets `previewLayer.session` while `sessionQueue` may be mid-configure — the
  attach happens when `isSessionRunning` flips true and the queue is quiet (instant).
- **Countdown now says "Getting the camera ready…"** while the session is still
  starting, instead of a digit frozen at 5 over a black screen.
- **Bring-up failure message now points at the working retry** ("Tap Start Recording to
  try again" — state returns to `.idle` and a second attempt usually succeeds) instead
  of telling the user to relaunch the app.

### Removed (2026-07-29)
- **The entire test suite** (`golf-sync-swingTests`, `golf-sync-swingUITests`, including
  the GolfDB fixtures and golden snapshots) — owner's decision; the project verifies by
  building and exercising the app. CLAUDE.md updated accordingly. The two test targets
  remain as empty entries in `project.pbxproj` (their folders are gone) and should be
  deleted in Xcode.

### Fixed (audit 2026-07-28 — see `docs/audit-2026-07-28.md`)
- **First-cold-launch freeze on "Start Recording" (the reported bug)**: compound fix.
  `AVCaptureSession` serializes all API access on an internal lock, and the main thread
  touched the session in four places while `sessionQueue` ran a slow first bring-up —
  preview-layer attach via identity-keyed rebuilds, `resumeSession`'s CAMPERF read of
  `inputs`/`outputs`, and `ensureSessionRunning`'s 100 ms `isRunning` poll. Now: all
  session access (including the diagnostics) lives on `sessionQueue`; `prepareAndStartSession`
  configures-if-needed + starts and *returns when running* (no polling); configuration is
  idempotent for identical params (the pre-warm/capture-screen double rebuild is gone);
  the preview passes `configurationId` as data instead of `.id(...)` so the layer is
  attached exactly once; the onboarding pre-warm was removed outright (it also left the
  camera running — green privacy dot — behind screens with no preview); pro-swing seeding
  moved off the launch path to the Compare tab's first appearance (its 59 MB of copies +
  19 thumbnail decodes contended with camera bring-up on disk/mediaserverd); and
  `SwingClassifier` now loads its CoreML model once per process at `.utility` instead of
  per-`RecordingViewModel`-construction at `.userInitiated`.
- **Library-cap paywall destroyed the recording it interrupted (critical)**: presenting
  the `requiresLibraryUpgrade` paywall fires `CaptureScreen.onDisappear`, whose teardown
  called `cancel()` unconditionally — deleting the just-recorded video while the user was
  being asked to pay to keep it. Teardown now routes through
  `handleScreenDisappeared()`, which no-ops while the paywall is presented.
- **Recordings that finish "with error" but a playable file** (max duration, disk full,
  interruption — `AVErrorRecordingSuccessfullyFinishedKey`) now run the success path
  instead of being discarded; genuinely failed recordings now delete their unusable file.
- **Save no longer lies**: a SwiftData persistence failure after the Photos write
  surfaces an error and returns to Review (previously the UI claimed `.saved` while the
  clip silently never appeared in History); the recording copy into app storage moved off
  the main actor (it froze the UI under the saving overlay for long clips).
- **30-minute cap wired**: `onMaximumDurationReached` had no assignee, so recording ran
  until the disk filled. It now stops through the view model's normal finalize→save flow.
- **Backgrounding mid-countdown** aborts the countdown instead of recording against the
  paused session (the `abortCountdown()` fix existed but had zero production callers).
- **Comparison screen**: composition building no longer parses both movies synchronously
  on the main thread (async `loadTracks`, deprecated API removed), and a build failure now
  shows an error with Try Again instead of a silent black screen with dead controls.
- **Pro swings self-heal after device restore**: the seeded-check now requires media files
  on disk, not just SwiftData records (files are excluded from backup by design, so a
  restore brought back records pointing at nothing, permanently).
- **Export HD gate resurrected**: the quality picker now renders in the live export flow,
  locked rows are tappable (paywall + `feature_gate_hit` fire), and the render size
  actually follows the gated quality — previously every export rendered at full
  resolution free of charge.
- **Revenue correctness**: non-trial purchases were double-counted (paywall + entitlement
  stream); the paywall no longer records revenue directly. Sandbox/TestFlight
  transactions are excluded; a 48 h recency window stops reinstalls/second devices from
  re-reporting old renewals. `PurchaseService`'s `@Observable` state is now written on
  the main actor.
- **Paywall close button** is inert while a purchase is in flight (was: dismissed +
  purchased fired for the same transaction, `onDismiss` ran twice).
- **Gate attribution**: pro-swing comparison and 3-swing library gates now fire
  `feature_gate_hit` like the other gates.
- **Path migration** retries up to 3 launches on save failure instead of giving up
  forever after one transient error.
- **Single-video player** no longer tears down on sheet presentation (pause-only
  `onDisappear`, teardown in `deinit` — same shape as the ComparisonView fix).
- **Localization**: paywall error/status strings, replay error strings and export quality
  copy now go through the string catalog instead of hardcoded English.
- **Detection teardown**: `stop()` flags inactive before the queue barrier, so queued
  frames bail instead of running a full Vision pass the barrier then waits out.
### Added (audit 2026-07-26 — see `docs/audit-2026-07-26.md`)
- **Live skeleton overlay on the capture screen**, toggleable via `SkeletonToggleButton`. `DetectionOrchestrator.onPoseDetected` publishes each analysed frame's pose (emitted above the cooldown/window guards, or the overlay would freeze for the 4s cooldown after every swing); `RecordingViewModel.isSkeletonEnabled` subscribes/unsubscribes so there is no per-frame main-queue traffic while hidden. New `PoseOverlayGeometry` isolates the Y-flip, `.resizeAspectFill` centre-crop and mirroring, with 7 unit tests. Mirroring and aspect ratio read from `connection.isVideoMirrored` and the post-rotation buffer ratio. **Skeleton alignment is unverified — Vision body pose returns zero joints on the simulator (re-confirmed empirically), so it needs a device.**
- **PiP on the capture screen with a border that traces green when a swing is locked in** (wires up the previously-orphaned `RecordingPiPView` + `DetectionBorderView`). Stays on the live camera deliberately: opening an `AVURLAsset` on the in-progress recording makes iOS terminate the capture.
- **Production error tracking**: `CrashDiagnosticsReporter` (MetricKit, no new dependency) forwards crashes, **hangs**, CPU and disk-write exceptions into the analytics seam. Plus failure-side events `app_launched`, `camera_config_failed`, `recording_stopped` and `recording_finalize_timeout` — `recording_started` without a matching `recording_stopped` would have exposed the finalize freeze months ago. Note MetricKit payloads arrive at most once per ~24h on a *later* launch from real devices only; Xcode Organizer → Crashes remains the real-time route.

### Fixed (audit follow-up 2026-07-27)
- **Data race on the capture callbacks**: `onFrameCaptured` / `onAudioCaptured` / `onRecordingFinished` were plain stored properties on an `@Observable` class, read on the capture queues at 30–60 fps while written from the main actor — both an unsynchronised closure read/write and `ObservationRegistrar` bookkeeping driven from a background thread at frame rate. Now `@ObservationIgnored` behind `callbackLock`, with copy-out getters so the closure is invoked outside the lock.
- **Black preview after a fast tab switch**: resume was gated on the `isSessionRunning` `@Observable` mirror, which is written via `DispatchQueue.main.async` and lags the session. The mirror could still read `true` after `pauseSession()` had stopped the session, so resume was skipped and the preview never recovered. Both gates now read `captureSession.isRunning`.
- **Lost `mediaServicesWereReset` recovery**: the guard read `isSessionRunning` on `sessionQueue` — off-main and possibly stale — which could silently drop the recovery and leave the camera dead. Now read on the main actor before hopping to `sessionQueue`.
- **Temp `.mov` leaked on every cancel-during-recording**: `AVCaptureMovieFileOutput` keeps writing after `stopRecording()` returns, but `cancel()` cleared `recordingURL` immediately so nothing deleted the file. Now split by case — recording → deferred discard consumed by the delegate (matched on URL identity, so a stale flag can never destroy a later recording); not recording → deleted inline, since no delegate callback will arrive.
- **Swing-marking slider stalled and jittered backwards**: `SwingEditorSheet` built a fresh `AVURLAsset` + `AVAssetImageGenerator` per drag tick with zero tolerance and never cancelled, so dozens of concurrent exact-frame decodes raced and whichever finished last won. Now one reused generator, previous request cancelled, stale results dropped, and generation cancelled on dismiss.
- **100 Hz SwiftUI invalidation during playback**: `VideoPlayerViewModel`'s periodic observer wrote the `@Observable` `currentTime` every 0.01 s. The observer still ticks at 100 Hz so the swing-loop bound stays exact (bounds now take the tick value directly), but `currentTime` publishes at ~30 Hz; `pause()` and `seek()` re-sync exactly so frame-stepping stays frame-accurate.

### Fixed (audit 2026-07-26 — see `docs/audit-2026-07-26.md`)
- **PiP tile expanded to fill the screen**: `.frame(120×160)` was applied to `content` while the ZStack also held an infinitely-flexible `Color.clear`. Latent — the view had never been rendered.
- **Recording freeze (critical)**: `RecordingView`'s `@State private var viewModel = RecordingViewModel()` caused SwiftUI to build and discard extra view models on every tab switch; each discarded instance's `deinit` cleared `CameraService.shared.onRecordingFinished`, whose callback is the only exit from `.finalizingVideo`. Stopping a recording therefore hung on the finalizing overlay forever. Shared-camera ownership moved out of `init`/`deinit` into `activate()` / `deactivate()`, driven by the view lifecycle. Proven with init/deinit logging on device-class runs (3 inits, 1 deinit for a single tab switch) and locked down by `RecordingViewModelCallbackOwnershipTests`.
- **Finalize watchdog**: `.finalizingVideo` now recovers into `.reviewing` after 20s instead of stranding the UI if the callback is ever lost again.
- **Comparison screen went permanently black**: `ComparisonView.onDisappear` tore down the AVPlayer, but `onViewAppear` is guarded on `viewModel == nil` so it never rebuilt — reachable just by opening the export sheet or the paywall. Now pauses instead; the time observer is released in `deinit`, where it belongs.
- **App Store review prompt never fired**: its only caller lived in `RecordingSaveService`, which is dead code. Now invoked from `RecordingViewModel.finalizeSave`.
- **Main thread blocked on camera setup**: `makePreviewRotationSubject` used `sessionQueue.sync`, so entering the Camera tab or switching cameras blocked the UI for the whole of `configureSession` (stopRunning + add inputs/outputs + `AVAudioSession.setActive`). `currentVideoDevice` now has its own lock.
- **Spurious "Camera session is not running."**: leaving the tab mid-countdown let the countdown finish and record against a paused session. Added `abortCountdown()`.
- **Revenue never reached Amplitude**: `CustomPaywallView` only recorded revenue in the non-trial branch, and every plan offers a trial, so the branch was dead. New `SubscriptionRevenueReporter` reports from the RevenueCat entitlement stream, de-duplicated on `latestPurchaseDate`, so trial→paid conversions and renewals are captured too.
- **Launch path**: pro-swing seeding (19 clip copies + 19 synchronous `AVAssetImageGenerator` passes) and the orphaned-export sweep moved off `App.init()`; `ProSwingSeeder` is no longer `@MainActor` so it runs genuinely off-main.
- **Seeder I/O**: now checks the SwiftData record *and* the file before copying, instead of unconditionally re-copying ~59 MB; `Documents/Videos/Pros` excluded from iCloud backup (it was duplicating bundled content into the user's iCloud quota).
- **Path migration could re-run forever**: the completion flag was only set on a successful save, so one failure meant a full fetch + mutation of every video on the main thread at every launch.

### Added
- **Funnel analytics (Amplitude)**: ~11-event funnel instrumented end-to-end — onboarding started/completed, paywall shown/dismissed/purchased (with source), main-app-reached, recording started, swing detected, video imported, comparison opened (with mode), feature-gate hits (advanced modes + HD export), export completed (aspect ratio + HD) — via a protocol-based `AnalyticsTracking` seam, a typed `AnalyticsEvent` taxonomy, an `AmplitudeAnalytics` wrapper (IDFV-only, session autocapture), and a `NoOpAnalytics` default. SDK isolated to a single file.
- **Analytics identity linking**: Amplitude user id set from the RevenueCat App User ID so app events join RevenueCat's server-sent monetization events
- **Amplitude-Swift SPM dependency** (1.18.5)
- **Curated pro swing library expansion**: Bundled 19 dataset-derived pro reference clips trimmed from local GolfDB/YouTube labels with 2s setup/follow-through context
- **Pro swing asset builder**: Added `scripts/build_pro_swing_assets.py` to regenerate bundled pro clips from local labeled training assets
- **Pro swing 16:9 backups**: Preserved original generated wide clips under `backups/pro-swings-original-16x9/` before cropping app assets
- **Onboarding flow**: 3-page onboarding (Welcome, Auto-Sync, Pro Benefits) with animated icons, highlight lists, page indicators, skip button
- **Custom paywall**: Full-screen paywall with animated hero, feature list, weekly/annual subscription options, savings badge, free trial detection
- **OnboardingService**: First-launch detection and onboarding completion state via UserDefaults
- **ReviewPromptService**: StoreKit review prompt after 3rd swing detection, once per app version
- **Feature gate paywall triggers**: Tapping locked comparison modes or HD export now presents paywall instead of being disabled
- **PremiumBadge component**: Reusable "PRO" badge for locked features
- **FeatureGateModifier**: Reusable view modifier for presenting paywall on premium feature access
- **Legal links in Settings**: Terms of Use (Apple EULA) and Privacy Policy links
- **Debug: Reset Onboarding**: Debug-only button in Settings to re-show onboarding

### Changed
- **PrivacyInfo.xcprivacy**: Declares analytics data collection — Usage Data (Product Interaction) + Device ID, both anonymous (not linked) and not tracking, purpose Analytics; IDFV-only so no App Tracking Transparency prompt
- **Pro swing video framing**: Bundled pro clips now use bbox-aware 3:2 landscape crops, with earlier 16:9 and 4:5 generated sets retained under `backups/`
- **Pro swing cards**: Carousel thumbnails now fit the full contact frame over a blurred background instead of center-cropping off-edge players
- **App entry point**: Shows OnboardingView on first launch, MainTabView on subsequent launches
- **SettingsView paywall**: Now uses custom AppPaywallView instead of RevenueCatUI default PaywallView
- **ComparisonView mode picker**: Locked modes now open paywall instead of being disabled
- **ExportProgressView**: Locked quality options now open paywall on tap
- **PurchaseService API key**: Conditional compilation for DEBUG vs RELEASE keys
- **PrivacyInfo.xcprivacy**: Added file timestamp API declaration (C617.1)

- **RevenueCat integration**: PurchaseService singleton with `customerInfoStream` observation, PaywallView, CustomerCenterView
- **SettingsView**: New Settings tab with subscription management, restore purchases, app version display
- **PrivacyInfo.xcprivacy**: Privacy manifest declaring UserDefaults API usage (required for App Store submission)
- **Skeleton overlay**: BodyJointMap, PosePublisher, SkeletonOverlayView, SkeletonToggleButton for real-time pose visualization
- **Detection border**: DetectionBorderView visual feedback during swing detection
- **GolfSwingClassifier v3 model tracked in git**: Previously untracked `.mlmodel` now version-controlled

### Changed
- **FeatureAccess delegates to RevenueCat**: `isUnlocked()` and `isPremiumUser` now check `PurchaseService.shared.isPremium` instead of returning hardcoded `true`
- **MainTabView**: Added 4th tab (Settings) with `gearshape.fill` icon
- **PoseExtractor thresholds hardened**: `minimumJointConfidence` 0.1→0.35, `minimumJointCount` 5→8 (prevents garbage data reaching classifier)
- **App startup resilience**: Replaced `fatalError` in ModelContainer init with graceful in-memory fallback + user-facing error alert

### Fixed
- **PhaseClassifier crash on shape mismatch**: Added guard validating all frame shapes match before CoreML prediction
- **fatalError on corrupted persistent store**: App no longer crashes — falls back to in-memory storage with user notification

### Added (previous)
- **Synced comparison mode**: New `sideBySideSynced` comparison mode — both videos loop aligned at impact point
- **`ComparisonMode.isSynchronized`**: Distinguishes free (independent loops) vs synced (drift-corrected) playback
- **`PremiumFeature.synchronizedPlayback`**: Premium gate for synced comparison modes

### Changed
- **Comparison default = synced + auto-play**: ComparisonView opens with both videos playing in sync at impact, looping within swing bounds
- **SwingTimeRange passed to comparison**: HomeView passes full `SwingTimeRange` (start, contact, end) instead of just contact times; sync offset calculated once from pre-detected swings — no re-analysis
- **ComparisonViewModel rewrite**: Swing-bound playback with per-player time observers, dual looping modes, drift correction (40ms threshold), removed Combine dependency
- **ComparisonVideoAreaView simplified**: Removed auto-sync overlay/confirmation banners; handles `sideBySideSynced` layout
- **ComparisonTimelineSlider**: Shows `displayTime` (relative to swing start) instead of absolute video time
- **VideoSyncEngine simplified**: Only uses `VideoFrameIterator` + `ActionClassifierDetector`; removed TempoAnalyzer, SyncStrategySelector, CrossCorrelationRefiner collaborators

### Removed
- **SwingNet pipeline (fully removed)**: SwingNetDetector, PersonCropper, RGBFrameBuffer, SwingNetPredictor, SwingValidationPipeline, 5 validation rules (ImpactConfidenceRule, EdgeArtifactRule, NoEventDominanceRule, TemporalOrderRule, MultiEventCorroborationRule)
- **MotionGateService**: Was only used by SwingNet
- **DetectorFactory**: No longer needed with single detector
- **Sync collaborators**: TempoAnalyzer, SyncStrategySelector, CrossCorrelationRefiner (effectively dead code)
- **Tempo sync UI**: Removed `tempoSyncEnabled`, `video2TempoAdjustment`, tempo toggle from ComparisonView
- **`PremiumFeature.tempoSync`**: Replaced by `synchronizedPlayback`
- **`seekToImpact` method**: Replaced by init-time sync offset calculation
- **Auto-sync overlay**: Sync progress banner and confirmation banner removed from ComparisonVideoAreaView

### Fixed (previous)
- **Data loss on reinstall**: SwingVideo now stores relative paths instead of absolute paths; container UUID changes no longer break video references
- **Race conditions in detectors**: Added NSLock synchronization to PersonCropper and MotionGateService; wrapped all mutable state mutations in SwingNetDetector and ActionClassifierDetector
- **Save-before-delete**: RecordingSaveService and VideoImportService now call `modelContext.save()` before deleting source files
- **Notification leak in SwingReplayView**: Loop observer stored as `@State`, removed in `onDisappear`
- **savedVideo never cleared**: RecordingView fullScreenCover now clears `savedVideo` on dismiss
- **seekToImpact ignoring contactTime2**: ComparisonViewModel now uses both contact times to set sync offset
- **ComparisonViewModel resource leak**: Players paused and Combine subscriptions cancelled in `deinit`
- **Export temp files accumulate**: Export temp files deleted after successful save to Photos; orphaned exports cleaned at launch
- **Force unwraps in CrossCorrelationRefiner**: Replaced `window1.last!`/`window1.first!` with guard
- **Duration timer on wrong thread**: RecordingCoordinator timer now scheduled on main run loop
- **FeatureAccess always false in Release**: All features now unlocked until paywall is implemented

### Added
- **AppLogger**: Unified logging via `os.Logger` with 6 subsystem categories (detection, storage, camera, sync, general, ui)
- **VideoPathMigrationService**: One-time migration converting absolute paths to relative paths at app launch
- **@MainActor on ViewModels**: VideoPlayerViewModel and ComparisonViewModel formalize main thread isolation

### Changed
- Replaced all 39 `print()` calls across 15 files with `AppLogger` (debug/info stripped in Release builds)

### Removed
- **SwingPlaybackManager.swift**: Unused dead code
- **CountdownManager.swift**: Unused dead code

### Fixed (previous)
- **Favorites lost on save**: RecordingSaveService now copies `isFavorite` from SwingClip to SwingMarker
- **Re-analysis wipes live-detected swings**: Videos saved with swings now marked `hasBeenAnalyzed = true` to skip redundant auto-detection
- **No navigation after save**: Recording save now opens SingleVideoPlayerView via `fullScreenCover(item:)` instead of showing a confirmation dialog
- **Comparison ignores selected swing**: HomeView passes selected swing contact times to ComparisonView for precise sync offset
- **HomeView date grouping sorts wrong**: Changed from string-based sort to `Calendar.startOfDay` + `Date` comparison
- **Swing replay doesn't loop**: `enforceSwingBounds` now seeks back to start and resumes playback instead of pausing
- **PiP shows wrong swing after swap**: `swapMainAndPip` preserves existing `replayingSwingIndex` instead of always resetting to last
- **SpeedButton non-functional**: Added `onTap` callback, wired `cyclePlaybackSpeed()` with [0.25x, 0.5x, 1.0x] speeds through PiP to SwingReplayView
- **DateFormatter created per render**: Extracted to `static let dateFormatter` in HistoryView
- **Timeline swing markers at wrong position**: Added `.frame(width: width)` to inner ZStack so offset calculations reference correct center
- **Countdown lag on cancel→re-start**: Stored countdown Task reference; `cancel()` now cancels the running Task immediately instead of waiting for the next 1-second sleep to complete
- **Bloated swing bounds**: Reduced pre/post swing buffers from 1.5s→0.8s across all 4 impact detection strategies; added `maxHalfDuration=2.0s` cap to prevent swing bounds exceeding ~4s total (real golf swings are 1.5-3s)
- **Wasted bottom space in SwingDetectionPanel**: Removed `Spacer()` that pushed swing list upward, leaving empty space below

### Changed
- **SingleVideoPlayerView layout**: Removed 16:9 aspect ratio constraint — video fills available space, reduced spacing for compact layout
- **PlaybackControlsView**: Smaller buttons (40/48px), subtler backgrounds, transport left-aligned with speed pill right-aligned
- **SwingDetectionPanel**: Split EDIT MANUALLY into separate EDIT (pencil, for selected swing) and ADD (plus, for new swing) actions
- **SwingThumbnailView**: Shrunk from 100x140 to 72x96, right-aligned with auto-scroll to selected thumbnail
- **Redundant save confirmation removed**: Recording save flow goes directly to video player instead of showing dialog

### Added
- **Sandi Metz OOP Decomposition**: Major refactoring of 11 files exceeding 200-line class limit
  - 41 new focused files created, all under 200 lines
  - Strategy pattern: 4 impact detection strategies as polymorphic chain of responsibility
  - Composite pattern: 5 swing validation rules in pipeline
  - Facade pattern: CameraService delegates to 5 collaborators
  - Orchestrator pattern: VideoSyncEngine, RecordingViewModel delegate to focused collaborators
- **New Services**: PoseExtractor, PhaseClassifier, PoseFrameBuffer, RGBFrameBuffer, PersonCropper, SwingNetPredictor, ImpactDetectionChain, SwingValidationPipeline, FrameProcessingGate, RecordingSaveService, VideoImportService, CameraNotificationHandler
- **New Camera Collaborators**: CameraPermissionManager, CaptureSessionConfigurator, RecordingCoordinator, CameraError (extracted)
- **New Sync Collaborators**: TempoAnalyzer, CrossCorrelationRefiner, SyncStrategySelector, VideoFrameIterator (extracted)
- **New View Components**: SwingDetectionPanel, ComparisonTimelineSlider, ComparisonControlsView, RecordingTopBar, RecordingControlsView, RecordingPiPView, RecordingOverlayView
- **DetectorFactory**: Centralized detector instantiation
- **SyncTypes.swift**: Extracted model types (SwingDetectionResult, SyncResult, etc.)
- **RecordingTypes.swift**: RecordingState enum moved from RecordingViewModel
- **GolfSwingClassifier v3**: Retrained 4-class model with fixed phase boundaries (backswing=toe_up→top, longer no_swing windows)
- **Positioning Guide Overlay**: Full-screen dark overlay with best practice rules shown on camera during idle state
  - 4 rules with SF Symbol icons: full body in frame, no other people, face light source, keep phone steady
  - Automatically dismissed when recording starts
- **Swing Replay Controls**: Play/pause + mute floating buttons on SwingReplayView during recording
  - 32pt circular buttons with `.ultraThinMaterial` background
  - Pause stops looping; play resumes it
- **4-Strategy Swing Detection**: Expanded ActionClassifierDetector from 2 to 4 detection strategies
  - Strategy 1: downswing→follow_through phase transition (best accuracy)
  - Strategy 2: backswing→follow_through fallback (downswing too brief)
  - Strategy 3: downswing→no_swing decay (follow_through not detected, common from front camera)
  - Strategy 4: backswing→no_swing decay with residual swing signal (very fast swings)
- **v3 Training Pipeline**: `scripts/prepare_golfdb_v3_training_data.py` for GolfDB data preparation
- **SwingNet ML Model**: GolfDB-pretrained SwingNet replaces heuristic detection for offline video analysis
  - 64-frame sliding window with 9-event classification (address → impact → finish)
  - ImageNet normalization for correct model input
  - 6-layer validation pipeline: confidence, edge filter, noEvent dominance, temporal order, corroboration
- **Pose-Based Person Crop**: VNDetectHumanBodyPoseRequest runs every 60 frames (~2x/sec)
  - Computes bounding box from skeleton keypoints, expands 30% for club arc
  - Crops frames before 160x160 resize — boosts model confidence from ~30% to ~35%
  - Graceful fallback to full frame when no pose detected
- **MotionGateService**: Lightweight motion detection gate for adaptive processing
  - Compares frame luminance to detect idle/active/peak motion states
  - Adaptive classification stride: idle=30, active=8, peak=5 frames
- **Multi-Swing Detection**: `analyzeAllSwings()` scans entire video, returns all detected swings
  - `detectedSwings` array accumulates validated swings during analysis
  - SingleVideoPlayerView shows count of detected swings
  - Old auto-detected markers removed before adding new ones
- **Top-of-Backswing Extraction**: `topOfBackswingTime`/`topOfBackswingConfidence` for sync enrichment
- **Frame Processing Gate**: Prevents OutOfBuffers by dropping frames when processing queue is busy
- **PiP Animation**: Spring animation on PiP appearance during recording
- **isMotionDetected**: Added to `RealTimeSwingDetector` protocol for UI feedback

### Changed
- **ActionClassifierDetector**: Decomposed from 667→187 lines; orchestrates PoseExtractor, PhaseClassifier, PoseFrameBuffer, ImpactDetectionChain
- **SwingNetDetector**: Decomposed from 693→233 lines; orchestrates RGBFrameBuffer, PersonCropper, SwingNetPredictor, SwingValidationPipeline
- **CameraService**: Decomposed from 824→313 lines; facade over CameraPermissionManager, CaptureSessionConfigurator, RecordingCoordinator, CameraNotificationHandler
- **VideoSyncEngine**: Decomposed from 796→248 lines; orchestrates VideoFrameIterator, TempoAnalyzer, SyncStrategySelector, CrossCorrelationRefiner
- **RecordingViewModel**: Decomposed from 579→263 lines; delegates to FrameProcessingGate, RecordingSaveService
- **RecordingView**: Decomposed from 593→203 lines; uses RecordingTopBar, RecordingControlsView, RecordingPiPView, RecordingOverlayView
- **ComparisonView**: Decomposed from 366→194 lines; extracted ComparisonTimelineSlider, ComparisonControlsView
- **SingleVideoPlayerView**: Decomposed from 339→204 lines; extracted SwingDetectionPanel
- **HomeView/HistoryView**: Duplicate `importVideo` replaced with VideoImportService
- **ActionClassifierDetector**: Upgraded from v2 to v3 model, removed v2 model from bundle
- **RecordingView**: Replaced CameraTipsOverlay with PositioningGuideOverlay in idle state
- **SwingNetDetector**: Complete rewrite of detection pipeline
  - Person detection switched from `VNDetectHumanRectanglesRequest` to `VNDetectHumanBodyPoseRequest`
  - Frame buffer uses `ContiguousArray<UInt8>` instead of `[Float]` (memory + perf)
  - ImageNet normalization deferred to `buildMLInput()` (normalize once, not per-frame)
  - Impact confidence threshold: 20% → 30% (person crop restores confidence)
  - Pose detection interval: 30 → 60 frames (less frequent, amortized ~0.25ms/frame)
- **VideoSyncEngine**: `analyzeAndMarkSwing()` → `analyzeAllSwings()` returning array
  - Top-of-backswing time now extracted from SwingNet analysis
- **RecordingViewModel**: Swing replay shows in PiP instead of replacing main camera view
  - Recording continues seamlessly after swing detection (no `processingSwing` state)
- **RecordingView**: Removed `processingSwingOverlay`, PiP border color logic updated

### Fixed
- **OutOfBuffers**: Added `_isProcessingFrame` gate to prevent camera buffer pool exhaustion
- **Camera Recording**: Full recording workflow with countdown and real-time pose detection
- **CameraService**: AVCaptureSession management with video/audio capture
- **LivePoseDetector**: Real-time body pose detection on camera frames
- **LiveSwingDetector**: Real-time swing detection using wrist velocity analysis
- **RecordingView**: Recording UI with pose overlay, countdown, and PiP replay
- **Camera Tab**: New Camera tab in MainTabView for recording
- **Camera Permissions**: Added camera and microphone usage descriptions
- **Fast Swing Detection Plan**: Documented approach for <500ms swing detection
- **Camera Optimization Plan**: Comprehensive production-ready camera plan (`plans/camera-optimization-plan.md`)
- **App Lifecycle Handling**: Camera session pauses on background, resumes on foreground
- **Session Interruption Handling**: Handles phone calls, Siri, other camera apps
- **Disk Space Validation**: Checks for 500MB+ free space before recording
- **Thermal State Monitoring**: Detects device overheating conditions
- **Audio Session Configuration**: Proper AVAudioSession setup for video recording
- **Permission State Monitoring**: Checks permission status before session start
- **Interruption Overlay UI**: Shows user-friendly message when recording interrupted

### Changed
- **ML-Only Swing Detection**: Removed heuristic velocity-based detector, now exclusively uses Core ML Action Classifier
  - Simplified frame processing pipeline
  - Removed audio impact detector (ML model doesn't need audio confirmation)
  - Cleaner codebase with single detection path
- **Tab Navigation**: Reordered tabs to Camera, History, Compare
- **LiveSwingDetector**: Rewritten for immediate impact detection (~300ms latency)
  - Fires at velocity peak confirmation (2-3 frames) instead of waiting for follow-through
  - Velocity smoothing with moving average filter for noise reduction
  - Dual wrist tracking - auto-detects which hand is swinging
  - Estimates end time instead of waiting for it
- **LivePoseDetector**: Added adaptive frame processing
  - Processes every frame during active swing tracking
  - Falls back to every-2nd-frame when idle (battery saving)
  - Added `leftWristPosition` and `rightWristPosition` properties
  - Wrapped Vision processing in autoreleasepool to prevent memory leaks
- **RecordingViewModel**: Background pose processing for speed
  - Dedicated processing queue avoids main thread blocking
  - Passes both wrist positions to swing detector
  - UI updates on main thread only
  - Handles optional URL from startRecording() for error cases
- **CameraService**: Complete rewrite for production readiness
  - Prioritizes highest resolution format supporting target FPS
  - Uses YUV420 pixel format instead of BGRA (more efficient)
  - Session preset set to `.inputPriority` to avoid conflicts
  - Added CameraError enum with all error cases and user-friendly descriptions
  - Added background task management for recording completion
  - Movie fragment interval set to 5 seconds (less data loss on crash)
- **RecordingView**: Added scene phase handling and error alerts
  - `.id(swing.id)` modifier to fix swing switching in replay
- **ML Swing Detection**: Added Core ML Action Classifier for swing phase detection
  - GolfSwingClassifier.mlmodel trained with 81% training / 79% validation accuracy
  - MLSwingDetector service with fallback to heuristic detection
  - `useMLDetection` toggle to switch between ML and velocity-based detection
- **Tab Switching Performance**: Optimized camera pause/resume for fast tab switching
  - Uses `pauseSession()`/`resumeSession()` instead of full session reconfiguration
  - Tracks tab visibility to avoid resuming camera when on other tabs
  - Session configured only once, then paused/resumed on tab switches

### Fixed
- **Recording Camera Position**: Front camera now used during countdown so users can see themselves to position correctly, then switches to back camera for recording
- **Swing Replay**: When swing detected, main view shows looping replay while PiP shows live recording continuing
- **Swing Timestamps**: Now correctly file-relative by tracking recording start time
- **Skeleton Mirroring**: PoseOverlayView now correctly mirrors skeleton on front camera
- **Save/Delete Dialog**: Always shows after stopping recording (not just when swings detected)
- **Swing Switching**: Can now switch between multiple detected swings in replay view
- **Memory Leak in Vision**: Fixed potential memory leak by adding autoreleasepool
- **Tap Area on Swing Cards**: Added `.contentShape(Rectangle())` for better tap handling
- **Tab Switching Lag**: Camera tab no longer freezes when switching between tabs

---

## [0.3.0] - 2026-01-30

### Added
- **Auto-Detection Service**: SwingDetector using Vision framework body pose estimation
- **Video Sync Engine**: VideoSyncEngine for automatic sync offset calculation
- **Body Pose Analysis**: Tracks 8 key joints (wrists, elbows, shoulders, hips) for swing detection
- **Audio Impact Detection**: Analyzes audio waveform for ball impact sound spikes
- **Hybrid Detection**: Combines pose velocity + audio analysis for ~80-85% accuracy
- **Auto-Detect UI**: "AUTO-DETECT" button in SingleVideoPlayerView with progress indicator
- **Auto-Sync UI**: "Auto-Sync" button in ComparisonView to align videos at impact
- **Detection Confidence**: Shows confidence badge (High/Medium/Low) on auto-detected swings
- **Research Documentation**: Comprehensive milestone-2-research.md with algorithm details

### Changed
- **SwingMarker Model**: Added `isAutoDetected`, `detectionConfidence` properties
- **SwingVideo Model**: Added `hasBeenAnalyzed`, `analysisDate`, helper properties
- **ComparisonViewModel**: Added `setSyncOffset()` method for auto-sync
- **SingleVideoPlayerView**: Redesigned with AUTO-DETECT and MANUAL buttons
- **ComparisonView**: Added sync controls section with Auto-Sync button and reset

---

## [0.2.0] - 2026-01-30

### Added
- **Video Import**: PHPicker integration for importing videos from photo library
- **Video Playback**: Single video player with play/pause, speed controls, and timeline scrubbing
- **Side-by-Side Comparison**: ComparisonView with synchronized dual video playback
- **Manual Swing Marking**: Three-handle slider for marking swing start (green), ball contact (orange), and swing end (green)
- **Swing Editor Sheet**: Full UI for adding, editing, and deleting swing markers
- **History Tab**: List of all recordings with swing counts, tap to view/edit swings
- **Video Export**: Side-by-side video composition export to Photos library
- **Data Models**: SwingVideo, SwingMarker, ComparisonSession with SwiftData persistence
- **Services**: VideoStorageService, ThumbnailService, VideoExportService
- **Tab Navigation**: MainTabView with Compare and Recordings tabs
- Photo Library usage descriptions in project settings

### Changed
- Replaced Xcode template ContentView/Item with custom app architecture
- Updated SwiftData schema to use SwingVideo, SwingMarker, ComparisonSession

---

## [0.1.0] - 2026-01-30

### Added
- CLAUDE.md with project overview, build commands, and architecture guidance
- Code principles: Sandi Metz rules (adapted for Swift), atomic architecture, service extraction
- Monetization principles: Adam Lyttle onboarding/paywall patterns
- Documentation structure: project_spec.md, architecture.md, changelog.md, project_status.md
- Complete project specification with PRD and engineering design
- Initial Xcode project scaffolding
- SwiftData model setup
