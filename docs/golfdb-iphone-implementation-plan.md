# GolfDB → iPhone Implementation Plan

> **Date**: February 21, 2026
> **Synthesized from**: 4 expert research streams (ML, CoreML, iOS, Biomechanics)

---

## Executive Summary

GolfDB's SwingNet achieves **98.4% impact detection accuracy** using a MobileNetV2+BiLSTM architecture (5.38M params, ~5MB quantized). Its killer feature is **per-frame probability output** — impact frame = `argmax(probs[:, 5])` — eliminating the need for probability curve heuristics, threshold tuning, and the entire ImpactDetectionChain.

**Recommended approach**: Reimplement the SwingNet architecture in PyTorch, train on GolfDB data with your own weights (avoids CC-BY-NC license restriction), convert to CoreML, and integrate as an offline video analyzer replacing the current ActionClassifierDetector for recorded video analysis.

---

## 1. Architecture Comparison: Current vs Proposed

### Current (Broken)
```
Recorded Video
    → AVAssetReader (frame extraction)
    → Vision Pose (18 joints per frame)
    → Create ML Action Classifier (4-class, clip-level)
    → ImpactDetectionChain (4 strategies, threshold heuristics)
    → Impact frame estimate (~100-200ms accuracy, often 0 detections)
```

### Proposed (SwingNet-based)
```
Recorded Video
    → AVAssetReader (frame extraction, 160x160 crops)
    → Vision Person Detection (bounding box)
    → SwingNet CoreML (MobileNetV2+BiLSTM, per-frame output)
    → argmax(probs[:, 5]) = impact frame
    → ±33ms accuracy (1 frame @30fps, within perceptual threshold)
```

**What gets removed**: ImpactDetectionChain, PhaseClassifier, all 4 detection strategies, PoseFrameBuffer probability analysis. Replaced by a single argmax call.

---

## 2. Step-by-Step Implementation

### Phase 1: Model Training (GPU Machine, ~1 week)

**Why train from scratch?** The pre-trained SwingNet weights are CC-BY-NC 4.0 (non-commercial). The GolfDB **dataset** is separate and freely available. The **architecture** (MobileNetV2+BiLSTM) is standard — no license restriction on reimplementation.

#### 1a. Set Up Training Environment
```bash
# Requirements
pip install torch torchvision coremltools scipy pandas

# Clone GolfDB repo (for dataset tools, not the model weights)
git clone https://github.com/wmcnally/golfdb.git
cd golfdb
```

#### 1b. Download & Prepare GolfDB Dataset
- Download preprocessed 160x160 videos from the Google Drive link in GolfDB README
- Run `generate_splits.py` to create 4-fold cross-validation splits
- Videos are already trimmed to swing duration, annotated with 8 event frame indices

#### 1c. Reimplement SwingNet Architecture
```python
import torch
import torch.nn as nn
from torchvision.models import mobilenet_v2

class SwingNetReimpl(nn.Module):
    """MobileNetV2 + BiLSTM for golf swing event detection.

    Reimplemented from the GolfDB paper architecture.
    5.38M params, outputs per-frame probabilities for 9 classes.
    """

    def __init__(self, num_classes=9, lstm_hidden=256):
        super().__init__()
        # MobileNetV2 backbone (first 19 layers, ImageNet pretrained)
        mobilenet = mobilenet_v2(pretrained=True)
        self.cnn = nn.Sequential(*list(mobilenet.features.children()))
        self.pool = nn.AdaptiveAvgPool2d(1)

        # Bidirectional LSTM
        self.lstm = nn.LSTM(
            input_size=1280,
            hidden_size=lstm_hidden,
            num_layers=1,
            batch_first=True,
            bidirectional=True
        )

        # Classification head
        self.fc = nn.Linear(lstm_hidden * 2, num_classes)

    def forward(self, x):
        # x shape: (batch, seq_len, 3, 160, 160)
        batch_size, seq_len = x.shape[0], x.shape[1]

        # Extract per-frame features
        x = x.view(batch_size * seq_len, 3, 160, 160)
        x = self.cnn(x)           # (B*T, 1280, 5, 5)
        x = self.pool(x)          # (B*T, 1280, 1, 1)
        x = x.view(batch_size, seq_len, 1280)

        # Temporal modeling
        x, _ = self.lstm(x)       # (B, T, 512)

        # Per-frame classification
        x = self.fc(x)            # (B, T, 9)
        return x
```

#### 1d. Training Configuration (from GolfDB paper)
| Parameter | Value |
|-----------|-------|
| Optimizer | Adam, lr=0.001 |
| LR schedule | ×0.1 after 5,000 iterations |
| Total iterations | 7,000 per fold |
| Batch size | 22 |
| Sequence length | 64 frames |
| Loss | Weighted cross-entropy (events=1.0, no-event=0.1) |
| Frozen layers | First 10 MobileNetV2 layers |
| Augmentation | Random flip, ±5° rotation/shear, random start frame |

#### 1e. Validate
- Run 4-fold cross-validation
- Target: ≥95% PCE on impact (event 5)
- Expected: ~98% if architecture is correct

### Phase 2: CoreML Conversion (~2-3 days)

#### 2a. Export PyTorch Model
```python
import coremltools as ct

model = SwingNetReimpl()
model.load_state_dict(torch.load("best_model.pth"))
model.eval()

# Trace with fixed sequence length (will handle variable later)
example_input = torch.randn(1, 64, 3, 160, 160)
traced_model = torch.jit.trace(model, example_input)

# Convert to CoreML with flexible sequence length
mlmodel = ct.convert(
    traced_model,
    inputs=[ct.TensorType(
        name="frames",
        shape=ct.Shape(shape=(1, ct.RangeDim(1, 512), 3, 160, 160))
    )],
    minimum_deployment_target=ct.target.iOS17
)

# Quantize to reduce size (~20MB → ~5MB)
mlmodel_quantized = ct.models.neural_network.quantization_utils.quantize_weights(
    mlmodel, nbits=8
)
mlmodel_quantized.save("SwingNet.mlpackage")
```

#### 2b. Chunked Inference Strategy
Since BiLSTM processes full sequences, handle long videos:
```
Video (300 frames) → Process in overlapping 64-frame chunks
→ Average probabilities in overlap regions
→ Concatenate → (300, 9) probability matrix
→ argmax column 5 = impact frame
```

#### 2c. Validation on Device
- Load model in Xcode, run on simulator + physical device
- Verify output shape matches PyTorch
- Compare impact predictions with PyTorch reference on same videos
- Measure inference latency (target: <2s for 5s video on iPhone 13+)

### Phase 3: iOS Integration (~1 week)

#### 3a. New SwingNetDetector Service
Replace ActionClassifierDetector with a new SwingNetDetector:

```swift
// golf-sync-swing/Services/Detection/SwingNetDetector.swift

protocol SwingEventDetector {
    func detectEvents(in videoURL: URL) async throws -> SwingEvents
}

struct SwingEvents {
    let impactFrame: Int
    let impactTime: CMTime
    let confidence: Float
    let allEvents: [SwingEvent]  // All 8 events with frame indices
}

struct SwingEvent {
    let type: SwingEventType  // address, toeUp, midBackswing, top, midDownswing, impact, midFollowThrough, finish
    let frame: Int
    let time: CMTime
    let confidence: Float
}

final class SwingNetDetector: SwingEventDetector {
    private let model: SwingNet  // CoreML generated class

    func detectEvents(in videoURL: URL) async throws -> SwingEvents {
        // 1. Extract frames (160x160, person-cropped)
        let frames = try await extractFrames(from: videoURL)

        // 2. Run inference in 64-frame chunks
        let probabilities = try await runInference(frames: frames)

        // 3. argmax per event column
        let events = findEvents(probabilities: probabilities)

        return events
    }
}
```

#### 3b. Frame Extraction Pipeline
```swift
// AVAssetReader → CMSampleBuffer → CVPixelBuffer → 160x160 crop

func extractFrames(from url: URL) async throws -> [CVPixelBuffer] {
    let asset = AVURLAsset(url: url)
    let reader = try AVAssetReader(asset: asset)
    let videoTrack = try await asset.loadTracks(withMediaType: .video).first!

    let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 160,
        kCVPixelBufferHeightKey as String: 160
    ])
    reader.add(output)
    reader.startReading()

    // Extract all frames
    var frames: [CVPixelBuffer] = []
    while let sampleBuffer = output.copyNextSampleBuffer() {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            frames.append(pixelBuffer)
        }
    }
    return frames
}
```

#### 3c. Person Detection (Preprocessing)
SwingNet expects person-cropped 160x160 input:
```swift
// Use Vision framework for person bounding box
let request = VNDetectHumanRectanglesRequest()
// Run on first frame, use bounding box for all frames (golfer is mostly stationary)
// Apply crop before feeding to SwingNet
```

#### 3d. Integration with VideoSyncEngine
```swift
// VideoSyncEngine changes:
// Replace: ActionClassifierDetector + ImpactDetectionChain pipeline
// With: SwingNetDetector.detectEvents(in:) → SwingEvents.impactTime

// In VideoSyncEngine:
let detector = SwingNetDetector()
let events = try await detector.detectEvents(in: videoURL)
let impactTime = events.impactTime  // Direct result, no post-processing needed

// Sync offset calculation remains the same:
// syncOffset = swing1.impactTime - swing2.impactTime
```

#### 3e. What Gets Removed
- `ImpactDetectionChain.swift` — replaced by argmax
- `PhaseClassifier.swift` — replaced by SwingNet's 9-class output
- `BackswingToFollowThroughStrategy.swift` — no longer needed
- `DownswingToFollowThroughStrategy.swift` — no longer needed
- `BackswingDecayStrategy.swift` — no longer needed
- `DownswingDecayStrategy.swift` — no longer needed
- `PoseFrameBuffer.swift` probability analysis — no longer needed
- All threshold constants and tuning parameters

---

## 3. Performance Expectations

| Metric | Current | Proposed |
|--------|---------|----------|
| Impact accuracy | ~100-200ms (often 0 detections) | ±33ms (98.4% PCE) |
| Detection rate | Poor (0 on calibration videos) | ~98% of videos |
| Processing time | ~1-3s (pose + classifier) | ~2-4s (frame extraction + CNN + LSTM) |
| Model size | 100-500KB | ~5MB (quantized) |
| Code complexity | 4 strategies + chain + thresholds | Single detector + argmax |
| Sync quality | Requires manual adjustment | Automatic, reliable |

---

## 4. Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| CoreML BiLSTM conversion fails | Medium | Use ONNX intermediate format; or split model (CNN CoreML + LSTM in Swift) |
| Training doesn't reproduce 98.4% | Low | Architecture is well-documented; use exact same hyperparameters |
| Person cropping fails on some videos | Medium | Use generous bounding box; fallback to full-frame (slight accuracy loss) |
| Memory issues on older iPhones | Low | Process in 64-frame chunks; use float16 |
| GolfDB dataset not representative of user videos | Medium | Fine-tune on user-submitted videos over time |

---

## 5. Alternative: Quick Win While Training (Parallel Track)

While SwingNet training is in progress, improve the current system:

1. **Disable the no-swing dominance pre-filter** (line 212 in ActionClassifierDetector) — likely root cause of 0 detections
2. **Lower probability thresholds** from 0.25-0.50 to 0.10-0.15
3. **Fix class label mismatch** — 6-class uses "noswing" vs "no_swing"

This costs 1-2 hours and may restore basic detection while SwingNet is being built.

---

## 6. Timeline

| Week | Activity |
|------|----------|
| **Week 1** | Set up training environment, download GolfDB, reimplement SwingNet, start training |
| **Week 2** | Validate training results, CoreML conversion, quantization |
| **Week 3** | iOS integration: SwingNetDetector, frame extraction, person cropping |
| **Week 3** | Remove ImpactDetectionChain, integrate with VideoSyncEngine |
| **Week 4** | Testing on real user videos, edge cases, performance optimization |

**Parallel**: Quick fix to current detector (disable no-swing filter) in Week 1, Day 1.

---

## 7. Key Decisions Required

1. **GPU access for training**: Need NVIDIA GPU for ~7,000 iterations of training. Options: local GPU, Google Colab Pro, AWS/GCP spot instance
2. **Person detection approach**: Full VNDetectHumanRectangles per frame vs single detection + tracking
3. **Offline-only scope**: BiLSTM requires full video — confirm this is acceptable (no real-time detection during recording)
4. **Model size budget**: ~5MB quantized — acceptable in app bundle?
5. **Minimum iOS version**: CoreML BiLSTM support requires iOS 15+ (current target is iOS 26+, so fine)

---

## Sources

- [GolfDB Paper (CVPR 2019)](https://arxiv.org/abs/1903.06528) — McNally et al.
- [GolfDB GitHub](https://github.com/wmcnally/golfdb)
- [CaddieSet (CVPR 2025)](https://arxiv.org/abs/2508.20491)
- [CoreML Conversion Guide](https://apple.github.io/coremltools/docs-guides/source/convert-pytorch.html)
- Human perceptual threshold research: A/V sync detection at ~40ms
- Golf biomechanics: PGA Tour average downswing 264ms, 3:1 backswing ratio
