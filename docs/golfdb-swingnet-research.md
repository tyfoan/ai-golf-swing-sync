# GolfDB & SwingNet: Deep Research Report

> **Date**: February 21, 2026
> **Researcher**: ML Expert (GolfDB/SwingNet Specialist)
> **Purpose**: Evaluate GolfDB dataset and SwingNet architecture for golf swing impact detection in iOS app

---

## Executive Summary

GolfDB is a 1,400-video benchmark dataset for golf swing sequencing, annotated with 8 swing events at frame-level precision. SwingNet, its baseline model, achieves **98.4% impact detection accuracy** (PCE) using a MobileNetV2+BiLSTM architecture with only 5.38M parameters — designed explicitly for mobile deployment. Impact detection is the **easiest** of the 8 events, with Address (31.7%) and Finish (26.5%) dragging down the 76.1% overall score.

**Key finding for the app**: SwingNet's architecture produces **frame-level probability distributions** across the entire video — far more precise than Create ML's clip-level classification. The argmax of the impact class probability column directly yields the predicted impact frame, no probability curve heuristics needed.

---

## 1. GolfDB Dataset

### Overview
- **Source**: CVPR Workshop 2019 (McNally et al., University of Waterloo)
- **Repository**: [github.com/wmcnally/golfdb](https://github.com/wmcnally/golfdb)
- **Paper**: [arxiv.org/abs/1903.06528](https://arxiv.org/abs/1903.06528)
- **License**: Creative Commons Attribution-NonCommercial 4.0

### Dataset Statistics
| Metric | Value |
|--------|-------|
| Total videos | 1,400 trimmed golf swing clips |
| Total frames | 390,000+ |
| Source videos | 580 YouTube compilations |
| Players | 248 professionals (PGA, LPGA, Champions Tour) |
| Resolution | 720p HD |
| Frame rates | 30fps (real-time) + various slow-motion rates |
| Real-time frames | ~195,000 |
| Slow-motion frames | ~195,000 |
| Splits | 4-fold cross-validation |

### 8 Swing Event Definitions
| # | Event | Definition | PCE |
|---|-------|-----------|-----|
| 0 | **Address** | Moment just before takeaway begins | 31.7% |
| 1 | **Toe-up** | Shaft parallel with ground during backswing | 84.2% |
| 2 | **Mid-backswing** | Arm parallel with ground during backswing | 88.7% |
| 3 | **Top** | Club changes direction (backswing→downswing transition) | 83.9% |
| 4 | **Mid-downswing** | Arm parallel with ground during downswing | 98.1% |
| 5 | **Impact** | Clubhead touches golf ball | **98.4%** |
| 6 | **Mid-follow-through** | Shaft parallel with ground during follow-through | 97.6% |
| 7 | **Finish** | Moment before final pose is relaxed | 26.5% |

**Overall PCE**: 76.1% (91.8% excluding Address/Finish)

### Annotation Format
- 10 frames annotated per video: start frame, 8 event frames, end frame
- Stored in MAT files, converted to pandas DataFrames via `generate_splits.py`
- Additional metadata: bounding box (enclosing clubhead + ball), player name, sex, club type, view type (face-on, down-the-line, other)
- Videos preprocessed to 160x160 resolution (available on Google Drive)

### Why Impact Is So Accurate (98.4%)
1. **Strongest visual signal**: Clubhead at lowest point, closest to ball — unambiguous
2. **Temporal context**: Sandwiched between rapid downswing and follow-through — distinct velocity profile
3. **Consistent across players**: Unlike address (subjective start) or finish (varied poses)
4. **Tolerance-based metric**: PCE allows ±delta frames where delta = max(round((impact_frame - address_frame) / 30), 1)
5. **Dense temporal region**: Mid-downswing, impact, and mid-follow-through all occur in a tight window, making them easy for BiLSTM to locate

---

## 2. SwingNet Architecture

### High-Level Design
SwingNet is a **hybrid CNN-RNN** that maps a sequence of RGB frames to a sequence of per-frame event probability distributions.

```
Input Video (N frames, 160x160x3)
    │
    ▼
┌─────────────────────┐
│  MobileNetV2         │  Per-frame spatial feature extraction
│  (ImageNet pretrain) │  → 1280-dim feature vector per frame
│  First 19 layers     │
└─────────────────────┘
    │
    ▼  (N x 1280)
┌─────────────────────┐
│  Bidirectional LSTM  │  Temporal modeling
│  1 layer, 256 hidden │  → captures forward + backward context
│  batch_first=True    │
└─────────────────────┘
    │
    ▼  (N x 512)  [256 forward + 256 backward]
┌─────────────────────┐
│  Fully Connected     │
│  512 → 9 classes     │  8 events + 1 no-event
└─────────────────────┘
    │
    ▼  (N x 9)
┌─────────────────────┐
│  Softmax             │  Per-frame probability distribution
└─────────────────────┘
    │
    ▼  (N x 9)
   Output: probability matrix
```

### Architecture Parameters
| Component | Detail |
|-----------|--------|
| Backbone | MobileNetV2 (width_mult=1.0) |
| Feature dim | 1280 per frame |
| LSTM type | Bidirectional |
| LSTM layers | 1 |
| LSTM hidden | 256 (→ 512 output from bi-direction) |
| Output classes | 9 (8 events + no-event) |
| Total params | **5.38 x 10^6** |
| FLOPs | 10.92 x 10^9 |
| Input resolution | 160 x 160 pixels |
| Sequence length | 64 frames (training) |
| Inference | Full video (variable length, batched in chunks of 64) |

### Key Design Decisions from Ablation Study (Table 1 in paper)
1. **Pre-trained weights essential**: Model does not train at all without ImageNet pre-training
2. **Bidirectional +12.1% PCE**: Critical improvement over unidirectional LSTM
3. **Single LSTM layer > two layers**: More parameters did not help
4. **256 hidden units optimal**: Outperformed 64 and 128
5. **Freeze first 10 MobileNetV2 layers**: Allows larger batch/sequence, prevents overfitting
6. **160x160 input**: Cost-effective balance (128 too small, 224 too expensive for GPU)

### Why BiLSTM Matters for Impact
The bidirectional LSTM sees both past AND future context at each frame:
- **Forward pass**: "downswing is accelerating, impact approaching"
- **Backward pass**: "follow-through just started, impact was here"
- Combined: extremely precise localization of the transition point

This is architecturally superior to our current Create ML approach which uses a sliding window and cannot look ahead.

---

## 3. Training Pipeline

### Configuration
| Parameter | Value |
|-----------|-------|
| Optimizer | Adam, lr=0.001 |
| LR schedule | Reduce 10x after 5,000 iterations |
| Total iterations | 7,000 per split |
| Batch size | 24 (paper) / 22 (code) |
| Loss | Weighted cross-entropy |
| Event weight | 1.0 |
| No-event weight | 0.1 |
| Frozen layers | First 10 MobileNetV2 layers |
| GPU | Single NVIDIA Titan Xp |

### Data Augmentation (Paper — +5% PCE over baseline)
- Random horizontal flipping (left↔right handed golfer)
- Random affine transforms (-5 to +5 degrees shear/rotation)
- Random start frame selection within clip

### Label Encoding
- Each frame gets a class label: 0-7 for the 8 events, 8 for no-event
- Most frames are class 8 (no-event) — hence the 0.1 weight
- Training clips: 64 frames randomly sampled within the annotated range
- Evaluation: full video processed sequentially in 64-frame batches

---

## 4. Inference Pipeline (How Impact Frame Is Found)

### Step-by-Step Process

```python
# 1. Load and preprocess video
frames = load_video(path)  # All frames, 160x160, normalized

# 2. Process in batches of 64 frames
all_probs = []
for batch in chunks(frames, seq_length=64):
    logits = model(batch)              # Shape: (64, 9)
    probs = F.softmax(logits, dim=1)   # Per-frame probabilities
    all_probs.append(probs)

# 3. Concatenate all probabilities
probs = np.concatenate(all_probs)  # Shape: (total_frames, 9)

# 4. Find event frames via argmax per event class
events = np.argmax(probs, axis=0)[:-1]  # 8 event frame indices
# events[5] = IMPACT FRAME (the frame with highest P(impact))

# 5. Get confidence for each event
confidences = [probs[events[i], i] for i in range(8)]
```

### Critical Insight: The Prediction is Direct
- **No probability curve heuristics needed** (unlike our Create ML approach)
- **No threshold tuning required** — just argmax
- The model outputs a probability for EACH frame being EACH event
- Impact frame = `argmax(probs[:, 5])` — the frame with highest P(impact)
- Confidence = `probs[impact_frame, 5]` — how sure the model is

### PCE Tolerance Calculation
```python
tolerance = max(round((events[5] - events[0]) / 30), 1)
# events[5] = impact frame, events[0] = address frame
# Divides by 30 (fps) to get seconds, rounds to integer
# For a typical 30fps clip: tolerance = 1 frame
# For slow-motion clips: tolerance scales proportionally
```

A prediction is "correct" if `|predicted_frame - ground_truth_frame| <= tolerance`

---

## 5. Comparison: SwingNet vs Current Create ML Approach

| Aspect | SwingNet | Create ML Action Classifier |
|--------|----------|-----------------------------|
| **Output** | Per-frame probability for each event | Clip-level class label |
| **Impact precision** | Exact frame (argmax) | Requires probability curve analysis |
| **Architecture** | MobileNetV2 + BiLSTM | Pose extraction + proprietary temporal |
| **Input** | Raw RGB pixels (160x160) | Skeleton/pose keypoints (18 joints) |
| **Model size** | ~20MB | 100-500KB |
| **Inference speed** | ~33ms/frame on mobile | <20ms per window |
| **Impact accuracy** | 98.4% PCE | Unknown (our 4-class model struggles) |
| **Temporal context** | Bidirectional (sees future) | Sliding window (causal only) |
| **Number of classes** | 9 (8 events + no-event) | 4-5 (coarse phases) |
| **Training data** | 1400 labeled videos | Our custom 5,236 clips |
| **Pre-trained weights** | Available (.pth.tar) | Must train from scratch |

### Key Advantages of SwingNet
1. **Frame-level predictions** — no need for probability curve heuristics
2. **Bidirectional context** — sees what comes after, not just before
3. **Pre-trained on 1400 pro swings** — proven 98.4% impact PCE
4. **Direct impact frame output** — argmax on column 5
5. **Battle-tested** — published, cited, reproduced

### Key Disadvantages
1. **Requires RGB input** — must decode video frames (more compute than pose)
2. **PyTorch model** — needs conversion to CoreML for iOS
3. **Bidirectional** — requires full video (cannot do real-time streaming detection)
4. **Non-commercial license** — CC-BY-NC 4.0, cannot use in commercial app
5. **160x160 crops** — needs person detection/cropping first

---

## 6. CoreML Conversion Path

### PyTorch → CoreML (Two Routes)

**Route A: Direct via coremltools (Recommended)**
```python
import coremltools as ct
import torch

model = EventDetector(...)
model.load_state_dict(torch.load("swingnet_1800.pth.tar"))
model.eval()

# Trace with example input
example = torch.randn(1, 64, 3, 160, 160)
traced = torch.jit.trace(model, example)

# Convert
mlmodel = ct.convert(traced,
    inputs=[ct.TensorType(shape=(1, ct.RangeDim(1, 300), 3, 160, 160))],
    minimum_deployment_target=ct.target.iOS17)
mlmodel.save("SwingNet.mlpackage")
```

**Route B: Via ONNX (Fallback)**
```python
torch.onnx.export(model, example, "swingnet.onnx",
    dynamic_axes={"input": {1: "seq_length"}})
# Then: coremltools.converters.onnx.convert("swingnet.onnx")
```

### Challenges
1. **Dynamic sequence length**: Training uses 64 frames, inference needs variable length — must handle in conversion
2. **Bidirectional LSTM**: CoreML supports BiLSTM but conversion can be tricky
3. **MobileNetV2 batch processing**: The reshape from (B*T, C, H, W) to (B, T, features) must be preserved
4. **Memory**: Processing 300 frames at 160x160 on iPhone — may need chunking strategy

### Estimated CoreML Model Size
- MobileNetV2: ~14MB (float32) or ~3.5MB (quantized int8)
- BiLSTM (256 hidden, bidir): ~5MB or ~1.3MB quantized
- FC layer: negligible
- **Total**: ~20MB float32, **~5MB quantized** (suitable for iOS bundle)

---

## 7. Follow-Up Research & Alternatives

### Academic Improvements on GolfDB
| Year | Method | Key Innovation | Impact on our use case |
|------|--------|----------------|----------------------|
| 2022 | LinearSVM + Golfer Detection | 88.3% recall (vs 76.1%) | Different metric, image-based |
| 2022 | Pruned VGGNet | 87.9% recall without detection | Single-frame, no temporal |
| 2023 | MLPFormer (IJCNN) | Gaussian soft labels for temporal boundaries | Better boundary precision |
| 2024 | T-DEED (CVPR) | Transformer encoder-decoder, SOTA event spotting | 16.4M params, too large |
| 2025 | CaddieSet + fine-tuned SwingNet | 78.0% overall (+2% over baseline) | Joint features + ball trajectory |

### CaddieSet (CVPR 2025 Workshop)
- 924 shots with joint features + ball trajectory (speed, spin, direction)
- Same 8-phase taxonomy as GolfDB
- Uses a sequence mapping model fine-tuned on GolfDB
- Validates that joint/pose features are sufficient for swing sequencing
- CSV-only annotations (no video clips for training)

### Unrelated "SwingNet" (ACM 2021)
- Different paper: "Ubiquitous Fine-Grained Swing Tracking via Stochastic NAS"
- IMU/sensor-based, not vision — not relevant to our use case

---

## 8. Practical Recommendations for the App

### Option A: Convert SwingNet to CoreML (Fastest Path to 98.4%)
**Pros**: Pre-trained, proven accuracy, frame-level output
**Cons**: CC-BY-NC license (non-commercial!), needs person cropping, bidirectional (offline only)
**Effort**: 2-3 days for conversion + integration
**Blocker**: License prohibits commercial use

### Option B: Train SwingNet Architecture from Scratch on GolfDB
**Pros**: Can use commercial-friendly license for own weights, same architecture
**Cons**: Need GPU, training setup, validation
**Effort**: 1-2 weeks
**Note**: Architecture itself is standard PyTorch (MobileNetV2+BiLSTM), no license restriction on reimplementation

### Option C: Hybrid — Keep Create ML Pose + Add BiLSTM Head
**Pros**: Leverages Apple's pose extraction (efficient), adds temporal context
**Cons**: Create ML doesn't expose intermediate features for custom heads
**Effort**: 2-3 weeks, requires Create ML Components pipeline

### Option D: Train 8-Class Create ML Model Using GolfDB Phase Mapping
**Pros**: Stays native Apple, small model, real-time capable
**Cons**: Clip-level only, still needs probability heuristics
**Effort**: 1 week to prepare data + train
**Note**: Map GolfDB 8 events to Create ML phases, use 15-frame windows

### Recommendation
**Option B** (reimplementation) gives the best accuracy with commercial viability. The architecture is well-documented (MobileNetV2+BiLSTM) and can be implemented in PyTorch, trained on GolfDB data (dataset is separate from code license), and converted to CoreML. However, this requires GPU training infrastructure.

For **immediate improvement** while pursuing Option B, **Option D** (better Create ML training with GolfDB-informed data preparation) can be done in parallel with existing infrastructure.

---

## 9. Key Takeaways

1. **98.4% impact PCE is real and reproducible** — it's the easiest event to detect
2. **Frame-level output** is SwingNet's killer feature vs Create ML's clip-level approach
3. **Bidirectional LSTM** provides +12.1% improvement — but prevents real-time use
4. **CC-BY-NC license** on the code/weights is a **blocker for commercial use** of pre-trained model
5. **The architecture itself** (MobileNetV2+BiLSTM) is standard and can be reimplemented
6. **GolfDB dataset** is freely available for research and training
7. **160x160 input requires person cropping** — adds a preprocessing step
8. **5.38M params, ~20MB float32, ~5MB quantized** — very reasonable for iOS
9. **Inference**: process full video in 64-frame chunks, argmax column 5 = impact frame
10. **Tolerance**: At 30fps, PCE uses ±1 frame tolerance — matching our ±33ms target

---

## Sources
- [GolfDB Paper (CVPR 2019)](https://arxiv.org/abs/1903.06528)
- [GolfDB GitHub Repository](https://github.com/wmcnally/golfdb)
- [SwingNet Pre-trained Weights](https://github.com/wmcnally/golfdb) (Google Drive link in README)
- [CaddieSet (CVPR 2025)](https://arxiv.org/abs/2508.20491)
- [Golf Swing Sequencing Using Computer Vision (2022)](https://dl.acm.org/doi/10.1007/978-3-031-04881-4_28)
- [CoreML Conversion Guide](https://apple.github.io/coremltools/docs-guides/source/convert-pytorch.html)
