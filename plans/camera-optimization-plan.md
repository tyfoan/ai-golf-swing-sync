# Camera & Production Optimization Plan

## Executive Summary

After deep research using Apple's latest AVFoundation documentation and analyzing the current codebase, I've identified **8 critical issues**, **12 performance optimizations**, and **9 production readiness items** that need to be addressed before the app is ready for the App Store.

---

## Sources Referenced

- [Apple Developer Documentation - AVCaptureSession](https://developer.apple.com/documentation/AVFoundation/AVCaptureSession)
- [AVCam: Building a Camera App (WWDC)](https://developer.apple.com/documentation/AVFoundation/avcam-building-a-camera-app)
- [Create a More Responsive Camera Experience - WWDC23](https://developer.apple.com/videos/play/wwdc2023/10105/)
- [iOS 18 New Camera APIs](https://zoewave.medium.com/ios-18-17-new-camera-apis-645f7a1e54e8)
- [Detecting Human Body Poses in Images](https://developer.apple.com/documentation/Vision/detecting-human-body-poses-in-images)
- [Setting Up a Capture Session](https://developer.apple.com/documentation/avfoundation/setting-up-a-capture-session)
- [Handling Audio Interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions)

---

## CRITICAL Issues (Must Fix)

### 1. ❌ No App Lifecycle Handling
**File:** `CameraService.swift`, `RecordingView.swift`
**Problem:** Camera session doesn't pause when app backgrounds, causing:
- Battery drain
- Potential crashes when iOS reclaims resources
- Recording corruption if user switches apps

**Fix:**
```swift
// In CameraService.swift - add notifications
NotificationCenter.default.addObserver(
    self,
    selector: #selector(sessionWasInterrupted),
    name: .AVCaptureSessionWasInterrupted,
    object: captureSession
)

NotificationCenter.default.addObserver(
    self,
    selector: #selector(sessionInterruptionEnded),
    name: .AVCaptureSessionInterruptionEnded,
    object: captureSession
)

// In RecordingView.swift - add scene phase handling
@Environment(\.scenePhase) private var scenePhase
.onChange(of: scenePhase) { oldPhase, newPhase in
    switch newPhase {
    case .background:
        viewModel.cameraService.pauseSession()
    case .active:
        viewModel.cameraService.resumeSession()
    case .inactive:
        break
    @unknown default:
        break
    }
}
```

### 2. ❌ No Audio Session Configuration
**File:** `CameraService.swift`
**Problem:** Missing `AVAudioSession` setup causes:
- Audio conflicts with other apps (music stops)
- Potential recording failures
- No handling for phone call interruptions

**Fix:**
```swift
func configureAudioSession() throws {
    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
    try audioSession.setActive(true)
}
```

### 3. ❌ Pixel Format Inefficiency
**File:** `CameraService.swift:136-138`
**Problem:** Using `kCVPixelFormatType_32BGRA` for video output requires color conversion overhead.

**Current:**
```swift
videoOutput.videoSettings = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
]
```

**Fix:** Use `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange` for camera processing (Vision framework handles both formats):
```swift
videoOutput.videoSettings = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
]
```

### 4. ❌ Session Preset + Active Format Conflict
**File:** `CameraService.swift:89, 220`
**Problem:** Setting both `sessionPreset` AND `activeFormat` can cause undefined behavior. Apple docs say: "Setting a format resets sessionPreset to inputPriority."

**Fix:** Choose one approach:
- **Option A:** Use `sessionPreset` only (simpler)
- **Option B:** Use `activeFormat` only with `sessionPreset = .inputPriority` (more control)

```swift
// Option B (recommended for frame rate control):
captureSession.sessionPreset = .inputPriority
// Then set device.activeFormat manually
```

### 5. ❌ Missing Interruption Handling
**File:** `CameraService.swift`
**Problem:** Phone calls, Siri, alarms, etc. interrupt recording with no handling.

**Fix:**
```swift
@objc private func sessionWasInterrupted(_ notification: Notification) {
    guard let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
          let interruptionReason = AVCaptureSession.InterruptionReason(rawValue: reason) else { return }

    switch interruptionReason {
    case .videoDeviceNotAvailableInBackground:
        // App went to background
        break
    case .audioDeviceInUseByAnotherClient:
        // Phone call or other audio app
        DispatchQueue.main.async { self.onSessionInterrupted?(.audioInUse) }
    case .videoDeviceInUseByAnotherClient:
        // Another camera app
        DispatchQueue.main.async { self.onSessionInterrupted?(.videoInUse) }
    @unknown default:
        break
    }
}
```

### 6. ❌ No Permission State Monitoring
**File:** `CameraService.swift`
**Problem:** User can revoke camera permission in Settings while app is running.

**Fix:**
```swift
// Check permission state before starting session
func checkPermissionState() -> AVAuthorizationStatus {
    return AVCaptureDevice.authorizationStatus(for: .video)
}

// Add observer for permission changes in iOS 17+
// Or check on each app foreground
```

### 7. ❌ No Disk Space Validation
**File:** `CameraService.swift:269`
**Problem:** Starting recording without checking available disk space can cause silent failures.

**Fix:**
```swift
func availableDiskSpace() -> Int64 {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    if let values = try? paths.first?.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
       let capacity = values.volumeAvailableCapacityForImportantUsage {
        return capacity
    }
    return 0
}

// Require at least 500MB for 1 minute of 1080p30
let minimumRequired: Int64 = 500 * 1024 * 1024
guard availableDiskSpace() > minimumRequired else {
    throw CameraError.insufficientStorage
}
```

### 8. ❌ Memory Leak Risk in Vision Processing
**File:** `LivePoseDetector.swift:271-287`
**Problem:** If Vision `perform()` throws, pixel buffer reference may be retained. Also, creating new `VNImageRequestHandler` for each frame adds memory pressure.

**Fix:**
```swift
// Reuse request handler where possible
// Ensure autoreleasepool wraps processing
autoreleasepool {
    let handler = VNImageRequestHandler(ciImage: scaledImage, options: [:])
    do {
        try handler.perform([poseRequest])
        // Process results...
    } catch {
        // Explicitly clear to help with memory
        poseRequest.results = nil
    }
}
```

---

## Performance Optimizations

### 9. ⚠️ Add Multitasking Camera Support (iPad)
**File:** `CameraService.swift`
**Benefit:** Allows camera to work in Split View/Slide Over on iPad.

```swift
if captureSession.isMultitaskingCameraAccessSupported {
    captureSession.isMultitaskingCameraAccessEnabled = true
}
```

### 10. ⚠️ Use Enhanced Video Stabilization
**File:** `CameraService.swift:285-287`
**Current:** Using `.auto` stabilization mode.
**Better:** Use `.cinematicExtendedEnhanced` when available (iOS 17+).

```swift
if connection.isVideoStabilizationSupported {
    if connection.isVideoStabilizationModeSupported(.cinematicExtendedEnhanced) {
        connection.preferredVideoStabilizationMode = .cinematicExtendedEnhanced
    } else if connection.isVideoStabilizationModeSupported(.cinematic) {
        connection.preferredVideoStabilizationMode = .cinematic
    } else {
        connection.preferredVideoStabilizationMode = .auto
    }
}
```

### 11. ⚠️ Enable Auto Frame Rate for Low Light
**File:** `CameraService.swift`
**Benefit:** Better exposure in indoor/low-light conditions.

```swift
if device.isAutoVideoFrameRateSupported {
    device.isAutoVideoFrameRateEnabled = true
}
```

### 12. ⚠️ Replace Timer with Frame Timestamps
**File:** `CameraService.swift:342-346`
**Problem:** Using `Timer` for duration is inaccurate and wasteful.
**Better:** Track duration from actual frame timestamps.

```swift
private var recordingStartTimestamp: CMTime?

func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

    if recordingStartTimestamp == nil {
        recordingStartTimestamp = timestamp
    }

    let duration = CMTimeSubtract(timestamp, recordingStartTimestamp!).seconds
    DispatchQueue.main.async {
        self.recordedDuration = duration
    }
}
```

### 13. ⚠️ Optimize CIImage Scaling
**File:** `LivePoseDetector.swift:265-268`
**Problem:** Creating CIImage and scaling every frame is CPU-intensive.
**Better:** Use Metal-backed CIContext or vImage for scaling.

```swift
// Already using Metal CIContext, but could add:
private lazy var scalingFilter = CIFilter(name: "CILanczosScaleTransform")

// Or use vImage for faster scaling
```

### 14. ⚠️ Add Thermal State Monitoring
**File:** `CameraService.swift` (new)
**Benefit:** Prevents app from contributing to device overheating.

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(thermalStateChanged),
    name: ProcessInfo.thermalStateDidChangeNotification,
    object: nil
)

@objc private func thermalStateChanged(_ notification: Notification) {
    let state = ProcessInfo.processInfo.thermalState
    switch state {
    case .nominal, .fair:
        // Normal operation
        break
    case .serious:
        // Reduce frame rate, lower resolution
        reduceProcessingLoad()
    case .critical:
        // Pause non-essential processing, warn user
        pauseNonEssentialProcessing()
    @unknown default:
        break
    }
}
```

### 15. ⚠️ Pre-warm Vision Model on Launch
**File:** `LivePoseDetector.swift:199-222`
**Status:** ✅ Already implemented with `warmup()` method.
**Note:** Ensure it's called early in app launch, not just on view appear.

### 16. ⚠️ Add Frame Drop Detection
**File:** `CameraService.swift`
**Benefit:** Monitor capture health and alert user.

```swift
extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var mode: CMAttachmentMode = 0
        if let reason = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: &mode) {
            print("⚠️ Dropped frame: \(reason)")
            DispatchQueue.main.async {
                self.droppedFrameCount += 1
            }
        }
    }
}
```

### 17. ⚠️ Optimize Audio Buffer Processing
**File:** `AudioImpactDetector.swift:100-128`
**Issue:** Converting Int16 to Float on every buffer is expensive.
**Better:** Request float format directly if available, or process less frequently.

### 18. ⚠️ Use Dedicated Video Data Output Queue QoS
**File:** `CameraService.swift:35`
**Current:** Default QoS
**Better:** Set explicit QoS for real-time performance.

```swift
private let videoOutputQueue = DispatchQueue(
    label: "com.golfsync.camera.videoOutput",
    qos: .userInteractive,
    attributes: [],
    autoreleaseFrequency: .workItem  // Important for memory
)
```

### 19. ⚠️ Add Preview Layer Optimization
**File:** `CameraPreviewView.swift`
**Benefit:** Reduce preview rendering overhead.

```swift
previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
previewLayer.connection?.isVideoMirrored = (position == .front)
// Set specific mirroring instead of letting it auto-detect
```

### 20. ⚠️ Configure Movie Output Fragment Duration
**File:** `CameraService.swift`
**Benefit:** More frequent file writes = less data loss on crash.

```swift
movieOutput.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 1)
```

---

## Production Readiness Items

### 21. 📦 Add Error Recovery UI
Show user-friendly messages for:
- Camera permission denied
- Microphone permission denied
- Disk space low
- Device overheating
- Recording interrupted

### 22. 📦 Add Crash/Analytics Reporting
Integrate Firebase Crashlytics or similar to track:
- Crash reports
- Recording completion rates
- Swing detection accuracy
- Device/iOS version distribution

### 23. 📦 Add App Transport Security Exception (if needed)
For any future cloud features, ensure proper ATS configuration.

### 24. 📦 Add Privacy Manifest
iOS 17+ requires privacy manifest for camera/microphone usage.
```xml
<!-- PrivacyInfo.xcprivacy -->
<key>NSPrivacyAccessedAPITypes</key>
<array>
    <dict>
        <key>NSPrivacyAccessedAPIType</key>
        <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
        <key>NSPrivacyAccessedAPITypeReasons</key>
        <array>
            <string>C617.1</string>
        </array>
    </dict>
</array>
```

### 25. 📦 Add Background Task for Video Processing
If user leaves app during save, complete processing in background.

```swift
var backgroundTask: UIBackgroundTaskIdentifier = .invalid

backgroundTask = UIApplication.shared.beginBackgroundTask {
    UIApplication.shared.endBackgroundTask(backgroundTask)
}

// After save completes:
UIApplication.shared.endBackgroundTask(backgroundTask)
```

### 26. 📦 Add Export Quality Options
Let users choose between:
- High quality (original resolution)
- Medium quality (720p, smaller files)
- Low quality (480p, share-friendly)

### 27. 📦 Add Haptic Feedback
For swing detection events, recording start/stop:
```swift
let generator = UIImpactFeedbackGenerator(style: .medium)
generator.impactOccurred()
```

### 28. 📦 Add Accessibility Support
- VoiceOver labels for camera controls
- Dynamic Type support
- Reduce Motion support (disable auto-play replays)

### 29. 📦 Optimize App Launch Time
- Defer Vision model warmup slightly
- Lazy load non-essential services
- Profile with Instruments Time Profiler

---

## Implementation Priority

### Phase 1: Critical Fixes (Before Beta)
1. [ ] App lifecycle handling (#1)
2. [ ] Audio session configuration (#2)
3. [ ] Interruption handling (#5)
4. [ ] Disk space validation (#7)
5. [ ] Memory leak fix (#8)

### Phase 2: Performance (Before Release)
6. [ ] Pixel format optimization (#3)
7. [ ] Session preset fix (#4)
8. [ ] Frame timestamp duration (#12)
9. [ ] Thermal monitoring (#14)
10. [ ] Frame drop detection (#16)

### Phase 3: Polish (Post-Launch)
11. [ ] Enhanced video stabilization (#10)
12. [ ] Auto frame rate (#11)
13. [ ] Multitasking support (#9)
14. [ ] Audio buffer optimization (#17)
15. [ ] All production items (#21-29)

---

## Testing Checklist

- [ ] Record for 5+ minutes without memory growth
- [ ] Background app during recording - verify recovery
- [ ] Receive phone call during recording - verify handling
- [ ] Fill disk to <100MB - verify error message
- [ ] Use in low light - verify frame rate adaptation
- [ ] Use on iPad in Split View
- [ ] Test on oldest supported device (iPhone XS / iOS 17)
- [ ] Test on latest device (iPhone 15 Pro / iOS 18)
- [ ] Profile with Instruments: Time Profiler, Allocations, Leaks
