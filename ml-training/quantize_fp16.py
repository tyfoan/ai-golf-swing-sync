#!/usr/bin/env python3
"""
Quantize SwingNet.mlmodel from Float32 to Float16 and validate accuracy.
Run with Python 3.12 venv: ./venv312/bin/python3 quantize_fp16.py
"""

import coremltools as ct
import numpy as np
import sys
from pathlib import Path


def quantize(input_path: str, output_path: str) -> tuple[float, float]:
    """Quantize model to FP16 and return (original_size_mb, quantized_size_mb)."""
    model = ct.models.MLModel(input_path)
    original_size = Path(input_path).stat().st_size / (1024 * 1024)

    quantized = ct.models.neural_network.quantization_utils.quantize_weights(
        model, nbits=16
    )
    quantized.save(output_path)
    quantized_size = Path(output_path).stat().st_size / (1024 * 1024)

    return original_size, quantized_size


def validate(fp32_path: str, fp16_path: str) -> dict:
    """Compare FP32 and FP16 model outputs on random input."""
    fp32_model = ct.models.MLModel(fp32_path)
    fp16_model = ct.models.MLModel(fp16_path)

    # Create random input matching SwingNet shape [1, 64, 3, 160, 160]
    rng = np.random.default_rng(42)
    test_input = rng.standard_normal((1, 64, 3, 160, 160)).astype(np.float32)

    fp32_out = fp32_model.predict({"input": test_input})
    fp16_out = fp16_model.predict({"input": test_input})

    fp32_logits = fp32_out["var_838"]
    fp16_logits = fp16_out["var_838"]

    max_abs_diff = np.max(np.abs(fp32_logits - fp16_logits))
    mean_abs_diff = np.mean(np.abs(fp32_logits - fp16_logits))

    # Check if argmax (detected event frame) changes
    fp32_events = np.argmax(fp32_logits.reshape(64, 9), axis=0)
    fp16_events = np.argmax(fp16_logits.reshape(64, 9), axis=0)
    frame_drift = np.max(np.abs(fp32_events.astype(int) - fp16_events.astype(int)))

    return {
        "max_abs_diff": float(max_abs_diff),
        "mean_abs_diff": float(mean_abs_diff),
        "fp32_events": fp32_events.tolist(),
        "fp16_events": fp16_events.tolist(),
        "max_frame_drift": int(frame_drift),
    }


def validate_on_video(fp32_path: str, fp16_path: str, video_path: str) -> dict:
    """Compare FP32 vs FP16 on actual video frames."""
    import cv2

    cap = cv2.VideoCapture(video_path)
    frames = []
    while len(frames) < 64:
        ret, frame = cap.read()
        if not ret:
            break
        frame = cv2.resize(frame, (160, 160))
        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        frame = frame.astype(np.float32) / 255.0
        # ImageNet normalization
        mean = np.array([0.485, 0.456, 0.406])
        std = np.array([0.229, 0.224, 0.225])
        frame = (frame - mean) / std
        frames.append(frame.transpose(2, 0, 1))  # HWC -> CHW
    cap.release()

    # Pad to 64 if needed
    while len(frames) < 64:
        frames.append(np.zeros((3, 160, 160), dtype=np.float32))

    input_array = np.array(frames, dtype=np.float32).reshape(1, 64, 3, 160, 160)

    fp32_model = ct.models.MLModel(fp32_path)
    fp16_model = ct.models.MLModel(fp16_path)

    fp32_out = fp32_model.predict({"input": input_array})["var_838"]
    fp16_out = fp16_model.predict({"input": input_array})["var_838"]

    # Apply softmax
    def softmax(x):
        e = np.exp(x - np.max(x, axis=-1, keepdims=True))
        return e / e.sum(axis=-1, keepdims=True)

    fp32_probs = softmax(fp32_out.reshape(64, 9))
    fp16_probs = softmax(fp16_out.reshape(64, 9))

    # Impact = event 5
    fp32_impact = int(np.argmax(fp32_probs[:, 5]))
    fp16_impact = int(np.argmax(fp16_probs[:, 5]))

    return {
        "fp32_impact_frame": fp32_impact,
        "fp16_impact_frame": fp16_impact,
        "impact_frame_drift": abs(fp32_impact - fp16_impact),
        "fp32_impact_confidence": float(fp32_probs[fp32_impact, 5]),
        "fp16_impact_confidence": float(fp16_probs[fp16_impact, 5]),
    }


def main():
    fp32_path = "SwingNet.mlmodel"
    fp16_path = "SwingNet_fp16.mlmodel"
    video_path = "golfdb_repo/test_video.mp4"

    print("=== SwingNet FP16 Quantization ===\n")

    # Step 1: Quantize
    print("Quantizing...")
    orig_mb, quant_mb = quantize(fp32_path, fp16_path)
    print(f"  FP32: {orig_mb:.1f} MB")
    print(f"  FP16: {quant_mb:.1f} MB")
    print(f"  Reduction: {(1 - quant_mb/orig_mb)*100:.1f}%\n")

    # Step 2: Validate on random input
    print("Validating on random input...")
    random_results = validate(fp32_path, fp16_path)
    print(f"  Max abs diff: {random_results['max_abs_diff']:.6f}")
    print(f"  Mean abs diff: {random_results['mean_abs_diff']:.6f}")
    print(f"  Max frame drift: {random_results['max_frame_drift']}")
    print(f"  FP32 events: {random_results['fp32_events']}")
    print(f"  FP16 events: {random_results['fp16_events']}\n")

    # Step 3: Validate on test video
    if Path(video_path).exists():
        print("Validating on test_video.mp4...")
        video_results = validate_on_video(fp32_path, fp16_path, video_path)
        print(f"  FP32 impact: frame {video_results['fp32_impact_frame']} (conf={video_results['fp32_impact_confidence']:.3f})")
        print(f"  FP16 impact: frame {video_results['fp16_impact_frame']} (conf={video_results['fp16_impact_confidence']:.3f})")
        print(f"  Impact frame drift: {video_results['impact_frame_drift']}\n")

        go = video_results["impact_frame_drift"] <= 1
    else:
        print(f"  Video not found: {video_path}\n")
        go = random_results["max_frame_drift"] <= 1

    # Verdict
    verdict = "GO" if go else "NO-GO"
    print(f"Verdict: {verdict}")

    if go:
        print(f"\nFP16 model saved to: {fp16_path}")
        print("Copy to Xcode source dir and re-run tests.")
    else:
        print("\nFP16 quantization introduces too much drift. Keep FP32.")

    return 0 if go else 1


if __name__ == "__main__":
    sys.exit(main())
