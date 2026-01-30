# Milestone 3: Recording & Annotations

**Goal**: Complete capture-to-analysis workflow

**Status**: Not Started

**Depends on**: Milestone 2

---

## Tasks

### 3.1 Camera Service
- [ ] Create `CameraService` with AVCaptureSession
- [ ] Request camera & microphone permissions
- [ ] Support back camera (primary for golf)
- [ ] Support front camera (for selfie mode)
- [ ] Configure for 60fps and 120fps recording
- [ ] Handle device orientation

### 3.2 Recording View
- [ ] Create `RecordVideoView`
- [ ] Live camera preview
- [ ] Countdown timer (3, 5, 10 second options)
- [ ] Visual countdown overlay
- [ ] Record button with recording indicator
- [ ] Stop recording button
- [ ] Flip camera button
- [ ] Timer duration picker

### 3.3 Recording Flow
- [ ] Start countdown on tap
- [ ] Audio beeps during countdown (optional)
- [ ] Auto-start recording when countdown ends
- [ ] Show recording duration
- [ ] Save to app library on stop
- [ ] Option to re-record or keep
- [ ] Auto-run phase detection after save

### 3.4 Drawing Tools
- [ ] Create `DrawingCanvasView` overlay
- [ ] Line tool (straight line between two points)
- [ ] Circle tool (drag to size)
- [ ] Angle tool (three points, show degrees)
- [ ] Freehand drawing tool

### 3.5 Drawing UI
- [ ] Create `DrawingToolbar`
- [ ] Tool selector (line, circle, angle, freehand)
- [ ] Color picker (preset colors)
- [ ] Line thickness control
- [ ] Undo button
- [ ] Redo button
- [ ] Clear all button
- [ ] Done/exit drawing mode

### 3.6 Annotation Persistence
- [ ] Create `Annotation` model
- [ ] Anchor annotations to specific frame timestamp
- [ ] Store annotations in ComparisonSession
- [ ] Re-render annotations when scrubbing to that frame
- [ ] Support annotations on left video, right video, or both
- [ ] Include annotations in export

---

## Technical Notes

### Camera Configuration
```swift
// Recommended settings
captureSession.sessionPreset = .hd1920x1080
videoOutput.videoSettings = [
    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
]
// For slow-mo: AVCaptureDevice.Format with 120fps
```

### Drawing Architecture
```
ComparisonView
└── ZStack
    ├── VideoPlayerView (left)
    ├── VideoPlayerView (right)
    └── DrawingCanvasView
        ├── Rendered annotations (for current frame)
        └── In-progress drawing (touch handling)
```

### Annotation Storage
```swift
struct Annotation: Codable {
    var id: UUID
    var type: AnnotationType
    var points: [CGPoint]  // Normalized 0-1 coordinates
    var color: String
    var lineWidth: CGFloat
    var frameTimestamp: TimeInterval
    var videoIndex: Int  // 0=left, 1=right, 2=both
}
```

---

## Definition of Done
- [ ] User can record video with countdown timer
- [ ] Recording saved and auto-analyzed
- [ ] User can draw lines, circles, angles on paused frame
- [ ] Annotations persist when scrubbing
- [ ] Annotations included in exported video
- [ ] Undo/redo works correctly
