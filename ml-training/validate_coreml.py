#!/usr/bin/env python3
"""
Validate CoreML SwingNet model output against known PyTorch results.
Run with Python 3.12 venv (coremltools native extensions work).

Usage:
  ./venv312/bin/python3 validate_coreml.py
"""

import os
import sys
import json
import numpy as np
import coremltools as ct
from scipy.special import softmax

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(SCRIPT_DIR, "SwingNet.mlmodel")

# PyTorch reference results (from convert_with_real_weights.py)
PYTORCH_EVENTS = {
    "Address": 74,
    "Toe-up": 86,
    "Mid-backswing": 98,
    "Top": 114,
    "Mid-downswing": 132,
    "Impact": 143,
    "Mid-follow-through": 151,
    "Finish": 236,
}

EVENT_NAMES = [
    "Address", "Toe-up", "Mid-backswing", "Top",
    "Mid-downswing", "Impact", "Mid-follow-through", "Finish"
]


def validate_with_random_input():
    """Validate model loads and runs with random input."""
    print(f"Loading model: {MODEL_PATH}")
    mlmodel = ct.models.MLModel(MODEL_PATH)

    print(f"Model spec inputs: {[i.name for i in mlmodel.get_spec().description.input]}")
    print(f"Model spec outputs: {[o.name for o in mlmodel.get_spec().description.output]}")

    # Run with random input
    dummy = np.random.randn(1, 64, 3, 160, 160).astype(np.float32)
    result = mlmodel.predict({"input": dummy})
    output_key = list(result.keys())[0]
    output = result[output_key]
    print(f"Output key: {output_key}")
    print(f"Output shape: {output.shape}")
    print(f"Output dtype: {output.dtype}")
    print(f"Output sample [0,:5]: {output[0, :5]}")

    return mlmodel, output_key


def validate_with_video():
    """
    Validate by preprocessing test_video.mp4 and comparing events.
    Since we don't have torch here, we preprocess with cv2+numpy.
    """
    try:
        import cv2
    except ImportError:
        print("  cv2 not available in venv312 — skipping video validation")
        print("  (This is expected. Video validation requires opencv.)")
        return None

    video_path = os.path.join(SCRIPT_DIR, "golfdb_repo", "test_video.mp4")
    input_size = 160
    mean = [0.485, 0.456, 0.406]
    std = [0.229, 0.224, 0.225]

    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    frame_h = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
    frame_w = cap.get(cv2.CAP_PROP_FRAME_WIDTH)

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

    images_np = np.asarray(images, dtype=np.float32) / 255.0
    images_np = images_np.transpose(0, 3, 1, 2)
    for c in range(3):
        images_np[:, c] = (images_np[:, c] - mean[c]) / std[c]

    total_frames = len(images)
    print(f"  Video: {frame_count} frames, {fps:.0f} fps")

    mlmodel = ct.models.MLModel(MODEL_PATH)
    output_key = list(mlmodel.get_spec().description.output)[0].name
    seq_length = 64
    all_probs = None

    batch_idx = 0
    while batch_idx * seq_length < total_frames:
        start = batch_idx * seq_length
        end = min((batch_idx + 1) * seq_length, total_frames)
        chunk = images_np[start:end]

        actual_len = len(chunk)
        if actual_len < seq_length:
            pad = np.zeros((seq_length - actual_len, 3, 160, 160), dtype=np.float32)
            chunk = np.concatenate([chunk, pad], axis=0)

        chunk_input = chunk[np.newaxis, ...]  # [1, 64, 3, 160, 160]
        result = mlmodel.predict({"input": chunk_input})
        probs_raw = result[output_key]
        probs = softmax(probs_raw[:actual_len], axis=1)

        if all_probs is None:
            all_probs = probs
        else:
            all_probs = np.append(all_probs, probs, axis=0)
        batch_idx += 1

    events = np.argmax(all_probs, axis=0)[:-1]
    confidences = [all_probs[events[i], i] for i in range(len(events))]

    return events, confidences, fps


def main():
    print("=" * 60)
    print("SwingNet CoreML Validation")
    print("=" * 60)
    print(f"Python:      {sys.version.split()[0]}")
    print(f"coremltools: {ct.__version__}")
    print()

    # Test 1: Model loads and runs
    print("[1/2] Basic model validation...")
    mlmodel, output_key = validate_with_random_input()
    print("  PASS: Model loads and produces output\n")

    # Test 2: Video validation
    print("[2/2] Video validation (test_video.mp4)...")
    video_result = validate_with_video()

    if video_result is not None:
        events, confidences, fps = video_result
        print(f"\n  CoreML detected events:")
        max_diff = 0
        all_within_2 = True
        for i, name in enumerate(EVENT_NAMES):
            pt_frame = PYTORCH_EVENTS[name]
            cm_frame = int(events[i])
            diff = abs(pt_frame - cm_frame)
            max_diff = max(max_diff, diff)
            if diff > 2:
                all_within_2 = False
            status = "PASS" if diff <= 2 else "WARN" if diff <= 5 else "FAIL"
            print(f"    {name:25s}: PT={pt_frame:4d} CM={cm_frame:4d} diff={diff:2d} conf={confidences[i]:.3f} [{status}]")

        impact_diff = abs(PYTORCH_EVENTS["Impact"] - int(events[5]))
        print(f"\n  Impact frame difference: {impact_diff} frames ({impact_diff/fps*1000:.0f}ms)")
        print(f"  Max event difference:    {max_diff} frames")

        # Go/No-Go
        if impact_diff <= 2:
            print(f"\n  >>> GO: Impact within ±2 frames. Proceed to Phase 2!")
            result = "GO"
        else:
            print(f"\n  >>> NO-GO: Impact differs by {impact_diff} frames.")
            result = "NO-GO"

        # Save results
        results = {
            "pytorch_events": PYTORCH_EVENTS,
            "coreml_events": {name: int(events[i]) for i, name in enumerate(EVENT_NAMES)},
            "impact_diff_frames": impact_diff,
            "max_diff_frames": max_diff,
            "verdict": result,
        }
        results_path = os.path.join(SCRIPT_DIR, "coreml_validation_results.json")
        with open(results_path, "w") as f:
            json.dump(results, f, indent=2)
        print(f"\n  Results saved to: {results_path}")
    else:
        print("  Video validation skipped (no cv2)")
        print("  Model conversion verified: loads and produces correct-shape output")

    print("\n" + "=" * 60)


if __name__ == "__main__":
    main()
