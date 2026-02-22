# SwingNet: Golf Swing Event Detection

PyTorch reimplementation of the SwingNet model from the [GolfDB paper](https://arxiv.org/abs/1903.06528) (McNally et al., CVPR Workshops 2019).

Uses **pre-trained weights** from the original GolfDB repo (CC-BY-NC 4.0, non-commercial use). No training required -- just download weights and export to CoreML.

Detects 8 golf swing events per frame: address, toe-up, mid-backswing, top, mid-downswing, **impact**, mid-follow-through, finish. Primary use case: finding the exact impact frame for video synchronization.

## Architecture

```
Input (B, T, 3, 160, 160)
  |
  v
MobileNetV2 features (19 layers, ImageNet pretrained)
  |
  v
Global Average Pool -> (B*T, 1280)
  |
  v
BiLSTM(input=1280, hidden=256, layers=1) -> (B, T, 512)
  |
  v
Linear(512, 9) -> (B*T, 9)
```

Total parameters: ~5.38M

## Quick Start

```bash
# 1. Setup
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# 2. Download pre-trained weights
python download_weights.py

# 3. Export to CoreML
python export_coreml.py --checkpoint models/swingnet_1800.pth.tar
```

This produces `SwingNet.mlpackage` (~5MB int8 quantized) ready for iOS.

## File Structure

```
swingnet/
  model.py             -- SwingNet architecture + load_pretrained()
  download_weights.py  -- Download pre-trained weights from GolfDB Google Drive
  export_coreml.py     -- CoreML conversion + int8 quantization
  evaluate.py          -- Optional: verify model on GolfDB validation set
  dataset.py           -- GolfDB dataset loader (for evaluation)
  metrics.py           -- PCE computation and evaluation utilities
  requirements.txt     -- Python dependencies
```

## Detailed Usage

### Download Weights

```bash
python download_weights.py
# Downloads to models/swingnet_1800.pth.tar (~21MB)
```

If automatic download fails, manually download from:
https://drive.google.com/file/d/1MBIDwHSM8OKRbxS8YfyRLnUBAdt0nupW/view

### CoreML Export

```bash
# Default: int8 quantized (~5MB)
python export_coreml.py --checkpoint models/swingnet_1800.pth.tar

# Float32 (larger, ~20MB)
python export_coreml.py --checkpoint models/swingnet_1800.pth.tar --no-quantize

# Custom output path
python export_coreml.py --checkpoint models/swingnet_1800.pth.tar --output MyModel.mlpackage
```

The exported CoreML model:
- Input: `frames` -- (1, 1-512, 3, 160, 160) float32 RGB
- Output: `logits` -- (1, seq_len, 9) float32 per-frame logits
- Flexible sequence length (1 to 512 frames)
- Minimum deployment: iOS 16

### iOS Usage

```swift
// Find impact frame:
let probs = softmax(logits)  // (seq_len, 9)
let impactFrame = argmax(probs[:, 5])  // event class 5 = impact
```

### Evaluation (Optional)

Requires GolfDB data: [videos_160](https://drive.google.com/file/d/1uBwRxFxW04EqG87VCoX3l6vXeV5T5JYJ/view) and split pickles from `../golfdb_repo/data/`.

```bash
python evaluate.py --checkpoint models/swingnet_1800.pth.tar --split 1 --verbose
# Expected: ~71.5% average PCE (without augmentation), ~98% on impact
```

## Expected Results

The pre-trained model (no augmentation, split 1) achieves:

| Event | PCE |
|-------|-----|
| address | ~32% |
| toe-up | ~65% |
| mid-backswing | ~74% |
| top | ~83% |
| mid-downswing | ~88% |
| **impact** | **~98%** |
| mid-follow-through | ~72% |
| finish | ~60% |
| **Average** | **~71.5%** |

Impact detection is the strongest event (98.4% PCE in the paper with augmentation).

## License

The pre-trained weights are from GolfDB, licensed under [CC-BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) (non-commercial use only).

## References

- McNally, W., Vats, K., Pinto, T., Dulhanty, C., McPhee, J., & Wong, A. (2019). GolfDB: A Video Database for Golf Swing Sequencing. CVPR Workshops.
- [GolfDB Paper](https://arxiv.org/abs/1903.06528)
- [GolfDB Repository](https://github.com/wmcnally/GolfDB)
