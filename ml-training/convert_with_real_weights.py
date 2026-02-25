#!/usr/bin/env python3
"""
SwingNet → CoreML conversion with REAL pretrained weights.

Phase 1 of implementation plan:
  1. Load swingnet_1800.pth.tar (real trained weights)
  2. Map weights into fixed-shape model (no .cuda(), no dynamic .size())
  3. Convert to CoreML .mlmodel (neuralnetwork format)
  4. Validate: PyTorch vs CoreML output on test_video.mp4
"""

import sys
import os
import time
import argparse

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "golfdb_repo"))

import torch
import torch.nn as nn
import numpy as np
import cv2
import torch.nn.functional as F

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WEIGHTS_PATH = os.path.join(SCRIPT_DIR, "golfdb_repo", "models", "swingnet_1800.pth.tar")
TEST_VIDEO = os.path.join(SCRIPT_DIR, "golfdb_repo", "test_video.mp4")
OUTPUT_PATH = os.path.join(SCRIPT_DIR, "SwingNet.mlmodel")

EVENT_NAMES = {
    0: "Address",
    1: "Toe-up",
    2: "Mid-backswing",
    3: "Top",
    4: "Mid-downswing",
    5: "Impact",
    6: "Mid-follow-through",
    7: "Finish",
}

IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD = [0.229, 0.224, 0.225]


# ============================================================
# Fixed-shape model (identical to convert_swingnet_v2.py)
# ============================================================

from MobileNetV2 import MobileNetV2


class SwingNetFixed(nn.Module):
    """Full SwingNet with fixed shapes — no .cuda(), no dynamic .size()."""

    BATCH = 1
    SEQ_LEN = 64

    def __init__(self, width_mult=1.0, lstm_hidden=256):
        super().__init__()
        self.lstm_hidden = lstm_hidden

        net = MobileNetV2(width_mult=width_mult)
        self.cnn = nn.Sequential(*list(net.children())[0][:19])
        self.pool = nn.AdaptiveAvgPool2d(1)

        cnn_out = int(1280 * width_mult if width_mult > 1.0 else 1280)
        self.rnn = nn.LSTM(
            cnn_out, lstm_hidden, num_layers=1,
            batch_first=True, bidirectional=True
        )
        self.lin = nn.Linear(2 * lstm_hidden, 9)

    def forward(self, x):
        # x: [1, 64, 3, 160, 160]
        c_in = x.reshape(self.BATCH * self.SEQ_LEN, 3, 160, 160)
        c_out = self.cnn(c_in)
        c_out = self.pool(c_out)
        c_out = c_out.squeeze(-1).squeeze(-1)

        r_in = c_out.reshape(self.BATCH, self.SEQ_LEN, -1)
        h0 = torch.zeros(2, self.BATCH, self.lstm_hidden)
        c0 = torch.zeros(2, self.BATCH, self.lstm_hidden)
        r_out, _ = self.rnn(r_in, (h0, c0))

        out = self.lin(r_out)
        out = out.reshape(self.BATCH * self.SEQ_LEN, 9)
        return out


# ============================================================
# Weight loading
# ============================================================

def load_real_weights(model, weights_path):
    """Load swingnet_1800 weights into fixed-shape model."""
    checkpoint = torch.load(weights_path, map_location="cpu", weights_only=False)
    state_dict = checkpoint["model_state_dict"]

    # Filter out dropout (not in our model) and check for mismatches
    model_keys = set(model.state_dict().keys())
    ckpt_keys = set(state_dict.keys())

    # The original model may have 'drop.XXX' keys — skip them
    filtered = {k: v for k, v in state_dict.items() if k in model_keys}
    missing = model_keys - set(filtered.keys())
    unexpected = ckpt_keys - model_keys

    if missing:
        print(f"  WARNING: Missing keys in checkpoint: {missing}")
    if unexpected:
        print(f"  INFO: Skipping unexpected keys: {unexpected}")

    model.load_state_dict(filtered, strict=False)
    print(f"  Loaded {len(filtered)}/{len(model_keys)} parameters from {os.path.basename(weights_path)}")
    return model


# ============================================================
# Video preprocessing (same as test_video.py)
# ============================================================

def preprocess_video(video_path, input_size=160):
    """Load and preprocess video frames exactly like GolfDB test_video.py."""
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    frame_h = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
    frame_w = cap.get(cv2.CAP_PROP_FRAME_WIDTH)

    print(f"  Video: {os.path.basename(video_path)}")
    print(f"  Frames: {frame_count}, FPS: {fps:.1f}, Size: {int(frame_w)}x{int(frame_h)}")

    ratio = input_size / max(frame_h, frame_w)
    new_h = int(frame_h * ratio)
    new_w = int(frame_w * ratio)
    delta_w = input_size - new_w
    delta_h = input_size - new_h
    top, bottom = delta_h // 2, delta_h - (delta_h // 2)
    left, right = delta_w // 2, delta_w - (delta_w // 2)

    images = []
    for _ in range(frame_count):
        ret, img = cap.read()
        if not ret:
            break
        resized = cv2.resize(img, (new_w, new_h))
        bordered = cv2.copyMakeBorder(
            resized, top, bottom, left, right,
            cv2.BORDER_CONSTANT,
            value=[0.406 * 255, 0.456 * 255, 0.485 * 255]
        )
        bordered_rgb = cv2.cvtColor(bordered, cv2.COLOR_BGR2RGB)
        images.append(bordered_rgb)
    cap.release()

    # Convert to tensor [1, N, 3, 160, 160] with ImageNet normalization
    images_np = np.asarray(images, dtype=np.float32) / 255.0
    # HWC → CHW
    images_np = images_np.transpose(0, 3, 1, 2)
    # Normalize
    for c in range(3):
        images_np[:, c] = (images_np[:, c] - IMAGENET_MEAN[c]) / IMAGENET_STD[c]

    tensor = torch.from_numpy(images_np).unsqueeze(0)  # [1, N, 3, 160, 160]
    print(f"  Preprocessed: {tensor.shape}")
    return tensor, fps


# ============================================================
# PyTorch inference
# ============================================================

def pytorch_inference(model, video_tensor, seq_length=64):
    """Run inference on video exactly like GolfDB eval.py."""
    model.eval()
    total_frames = video_tensor.shape[1]
    all_probs = None

    batch = 0
    with torch.no_grad():
        while batch * seq_length < total_frames:
            start = batch * seq_length
            end = min((batch + 1) * seq_length, total_frames)
            chunk = video_tensor[:, start:end, :, :, :]

            # Pad to seq_length if needed
            actual_len = chunk.shape[1]
            if actual_len < seq_length:
                pad = torch.zeros(1, seq_length - actual_len, 3, 160, 160)
                chunk = torch.cat([chunk, pad], dim=1)

            logits = model(chunk)
            probs = F.softmax(logits.data, dim=1).numpy()

            if all_probs is None:
                all_probs = probs[:actual_len]
            else:
                all_probs = np.append(all_probs, probs[:actual_len], axis=0)
            batch += 1

    return all_probs


def extract_events(probs):
    """Extract event frames from probability matrix."""
    events = np.argmax(probs, axis=0)[:-1]  # 8 events (skip class 8 = no-event)
    confidences = [probs[events[i], i] for i in range(len(events))]
    return events, confidences


# ============================================================
# CoreML conversion
# ============================================================

def convert_to_coreml(model, output_path):
    """Convert traced model to CoreML .mlmodel."""
    import coremltools as ct

    model.eval()
    dummy = torch.randn(1, 64, 3, 160, 160)

    print("\n  Step 1: JIT trace...")
    with torch.no_grad():
        ref_out = model(dummy)
    traced = torch.jit.trace(model, dummy)
    with torch.no_grad():
        traced_out = traced(dummy)
    diff = (ref_out - traced_out).abs().max().item()
    print(f"  Trace OK (max diff: {diff:.2e})")

    print("  Step 2: CoreML convert (neuralnetwork format)...")
    t0 = time.time()
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input", shape=(1, 64, 3, 160, 160))],
        convert_to="neuralnetwork",
    )
    elapsed = time.time() - t0
    print(f"  Conversion OK ({elapsed:.1f}s)")

    mlmodel.save(output_path)
    size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"  Saved: {output_path} ({size_mb:.1f} MB)")

    return mlmodel


# ============================================================
# CoreML inference (for validation)
# ============================================================

def coreml_inference(mlmodel_path, video_tensor, seq_length=64):
    """Run CoreML inference on the same video."""
    import coremltools as ct

    mlmodel = ct.models.MLModel(mlmodel_path)
    total_frames = video_tensor.shape[1]
    all_probs = None

    batch = 0
    while batch * seq_length < total_frames:
        start = batch * seq_length
        end = min((batch + 1) * seq_length, total_frames)
        chunk = video_tensor[:, start:end, :, :, :].numpy()

        actual_len = chunk.shape[1]
        if actual_len < seq_length:
            pad = np.zeros((1, seq_length - actual_len, 3, 160, 160), dtype=np.float32)
            chunk = np.concatenate([chunk, pad], axis=1)

        result = mlmodel.predict({"input": chunk})
        output_key = list(result.keys())[0]
        probs_raw = result[output_key]

        # Apply softmax (CoreML neuralnetwork outputs raw logits)
        from scipy.special import softmax
        probs = softmax(probs_raw[:actual_len], axis=1)

        if all_probs is None:
            all_probs = probs
        else:
            all_probs = np.append(all_probs, probs, axis=0)
        batch += 1

    return all_probs


# ============================================================
# Main
# ============================================================

def main():
    parser = argparse.ArgumentParser(description="SwingNet → CoreML with real weights")
    parser.add_argument("--weights", default=WEIGHTS_PATH, help="Path to swingnet_1800.pth.tar")
    parser.add_argument("--video", default=TEST_VIDEO, help="Path to test video")
    parser.add_argument("--output", default=OUTPUT_PATH, help="Output .mlmodel path")
    parser.add_argument("--skip-validation", action="store_true", help="Skip CoreML validation")
    args = parser.parse_args()

    print("=" * 60)
    print("SwingNet → CoreML Conversion (REAL WEIGHTS)")
    print("=" * 60)
    print(f"Python:  {sys.version.split()[0]}")
    print(f"PyTorch: {torch.__version__}")
    print()

    # Step 1: Load model with real weights
    print("[1/4] Loading SwingNet with pretrained weights...")
    model = SwingNetFixed()
    model = load_real_weights(model, args.weights)
    model.eval()
    print()

    # Step 2: Run PyTorch inference on test video
    print("[2/4] PyTorch inference on test video...")
    video_tensor, fps = preprocess_video(args.video)
    pytorch_probs = pytorch_inference(model, video_tensor)
    pt_events, pt_confs = extract_events(pytorch_probs)

    print(f"\n  PyTorch detected events:")
    for i, (frame, conf) in enumerate(zip(pt_events, pt_confs)):
        time_s = frame / fps
        print(f"    {EVENT_NAMES[i]:25s}: frame {frame:4d} ({time_s:6.2f}s) conf={conf:.3f}")
    impact_frame_pt = pt_events[5]
    print(f"\n  >>> IMPACT FRAME (PyTorch): {impact_frame_pt} ({impact_frame_pt/fps:.2f}s)")

    # Step 3: Convert to CoreML
    print("\n[3/4] Converting to CoreML...")
    convert_to_coreml(model, args.output)

    # Step 4: Validate CoreML output
    if args.skip_validation:
        print("\n[4/4] Skipping CoreML validation (--skip-validation)")
    else:
        print("\n[4/4] Validating CoreML output...")
        try:
            coreml_probs = coreml_inference(args.output, video_tensor)
            cm_events, cm_confs = extract_events(coreml_probs)

            print(f"\n  CoreML detected events:")
            for i, (frame, conf) in enumerate(zip(cm_events, cm_confs)):
                time_s = frame / fps
                print(f"    {EVENT_NAMES[i]:25s}: frame {frame:4d} ({time_s:6.2f}s) conf={conf:.3f}")
            impact_frame_cm = cm_events[5]
            print(f"\n  >>> IMPACT FRAME (CoreML): {impact_frame_cm} ({impact_frame_cm/fps:.2f}s)")

            # Compare
            print("\n  " + "-" * 50)
            print("  VALIDATION RESULTS:")
            print("  " + "-" * 50)
            max_diff = 0
            all_pass = True
            for i in range(8):
                diff = abs(int(pt_events[i]) - int(cm_events[i]))
                max_diff = max(max_diff, diff)
                status = "PASS" if diff <= 2 else "FAIL"
                if diff > 2:
                    all_pass = False
                print(f"    {EVENT_NAMES[i]:25s}: PT={pt_events[i]:4d} CM={cm_events[i]:4d} diff={diff:2d} [{status}]")

            impact_diff = abs(int(impact_frame_pt) - int(impact_frame_cm))
            print(f"\n  Impact frame difference: {impact_diff} frames ({impact_diff/fps*1000:.0f}ms)")
            print(f"  Max event difference:    {max_diff} frames")

            if all_pass:
                print("\n  >>> GO: All events within ±2 frames. Proceed to Phase 2!")
            elif impact_diff <= 2:
                print(f"\n  >>> GO: Impact within ±2 frames (diff={impact_diff}). Proceed to Phase 2!")
            else:
                print(f"\n  >>> NO-GO: Impact differs by {impact_diff} frames. Investigate.")

        except ImportError:
            print("  scipy not installed — installing...")
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "scipy"])
            print("  Re-run this script to validate.")
        except Exception as e:
            print(f"  CoreML validation failed: {e}")
            import traceback
            traceback.print_exc()
            print("\n  NOTE: Conversion succeeded. Validation can be done on macOS with coremltools.")

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
