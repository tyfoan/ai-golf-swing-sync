#!/usr/bin/env python3
"""
SwingNet (EventDetector) → CoreML conversion script.
Tests multiple conversion paths: JIT trace, coremltools, ONNX intermediate.
"""

import sys
import os
import time
import traceback

# Add golfdb_repo to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "golfdb_repo"))

import torch
import torch.nn as nn
import numpy as np
import coremltools as ct


# ============================================================
# Step 1: Patched EventDetector that works on CPU
# ============================================================
from MobileNetV2 import MobileNetV2


class EventDetectorCPU(nn.Module):
    """EventDetector patched for CPU inference and CoreML tracing.

    Key changes from original:
    - init_hidden uses CPU tensors (no .cuda())
    - Fixed sequence length for tracing (no dynamic shapes)
    - Dropout disabled for inference
    """

    def __init__(self, width_mult=1.0, lstm_layers=1, lstm_hidden=256,
                 bidirectional=True):
        super().__init__()
        self.width_mult = width_mult
        self.lstm_layers = lstm_layers
        self.lstm_hidden = lstm_hidden
        self.bidirectional = bidirectional
        self.num_directions = 2 if bidirectional else 1

        # CNN backbone: MobileNetV2 features (first 19 layers)
        net = MobileNetV2(width_mult=width_mult)
        self.cnn = nn.Sequential(*list(net.children())[0][:19])

        # Sequence model
        cnn_out = int(1280 * width_mult if width_mult > 1.0 else 1280)
        self.rnn = nn.LSTM(
            cnn_out, lstm_hidden, lstm_layers,
            batch_first=True, bidirectional=bidirectional
        )

        # Classifier
        lin_in = self.num_directions * lstm_hidden
        self.lin = nn.Linear(lin_in, 9)

    def forward(self, x):
        batch_size, timesteps, C, H, W = x.size()

        # Initialize hidden state on CPU
        h0 = torch.zeros(self.num_directions * self.lstm_layers,
                         batch_size, self.lstm_hidden)
        c0 = torch.zeros(self.num_directions * self.lstm_layers,
                         batch_size, self.lstm_hidden)

        # CNN: process all frames
        c_in = x.view(batch_size * timesteps, C, H, W)
        c_out = self.cnn(c_in)
        c_out = c_out.mean(3).mean(2)  # Global average pooling

        # LSTM: process sequence
        r_in = c_out.view(batch_size, timesteps, -1)
        r_out, _ = self.rnn(r_in, (h0, c0))

        # Classify each timestep
        out = self.lin(r_out)
        out = out.view(batch_size * timesteps, 9)
        return out


# ============================================================
# Step 2: CNN-only wrapper for partial conversion
# ============================================================
class SwingNetCNN(nn.Module):
    """Just the MobileNetV2 backbone — guaranteed CoreML compatible."""

    def __init__(self, width_mult=1.0):
        super().__init__()
        net = MobileNetV2(width_mult=width_mult)
        self.cnn = nn.Sequential(*list(net.children())[0][:19])

    def forward(self, x):
        # x: [batch, 3, 160, 160]
        out = self.cnn(x)
        out = out.mean(3).mean(2)  # [batch, 1280]
        return out


# ============================================================
# Step 3: Split architecture — CNN + LSTM as separate models
# ============================================================
class SwingNetLSTM(nn.Module):
    """Just the LSTM + linear head, takes CNN features as input."""

    def __init__(self, lstm_layers=1, lstm_hidden=256, bidirectional=True,
                 input_size=1280):
        super().__init__()
        self.lstm_layers = lstm_layers
        self.lstm_hidden = lstm_hidden
        self.bidirectional = bidirectional
        self.num_directions = 2 if bidirectional else 1

        self.rnn = nn.LSTM(
            input_size, lstm_hidden, lstm_layers,
            batch_first=True, bidirectional=bidirectional
        )
        lin_in = self.num_directions * lstm_hidden
        self.lin = nn.Linear(lin_in, 9)

    def forward(self, x):
        # x: [1, seq_len, 1280]
        batch_size = x.size(0)
        h0 = torch.zeros(self.num_directions * self.lstm_layers,
                         batch_size, self.lstm_hidden)
        c0 = torch.zeros(self.num_directions * self.lstm_layers,
                         batch_size, self.lstm_hidden)

        r_out, _ = self.rnn(x, (h0, c0))
        out = self.lin(r_out)
        # out: [1, seq_len, 9]
        return out


# ============================================================
# Conversion Helpers
# ============================================================
def try_jit_trace(model, dummy_input, name):
    """Attempt torch.jit.trace and report results."""
    print(f"\n{'='*60}")
    print(f"JIT Trace: {name}")
    print(f"{'='*60}")
    print(f"  Input shape: {dummy_input.shape}")

    try:
        model.eval()
        with torch.no_grad():
            ref_output = model(dummy_input)
        print(f"  PyTorch output shape: {ref_output.shape}")

        traced = torch.jit.trace(model, dummy_input)

        with torch.no_grad():
            traced_output = traced(dummy_input)

        diff = (ref_output - traced_output).abs().max().item()
        print(f"  JIT trace: SUCCESS")
        print(f"  Max numerical diff (PyTorch vs traced): {diff:.2e}")
        return traced, ref_output
    except Exception as e:
        print(f"  JIT trace: FAILED")
        print(f"  Error: {e}")
        traceback.print_exc()
        return None, None


def try_coreml_convert(traced_model, dummy_input, name, output_path,
                       ref_output=None):
    """Attempt coremltools conversion from traced model."""
    print(f"\n{'='*60}")
    print(f"CoreML Convert: {name}")
    print(f"{'='*60}")

    if traced_model is None:
        print("  Skipped (no traced model)")
        return False

    try:
        # Try mlprogram format (newer, better LSTM support)
        print("  Converting with convert_to='mlprogram' ...")
        t0 = time.time()
        ct_input = ct.TensorType(
            name="input",
            shape=dummy_input.shape
        )
        mlmodel = ct.convert(
            traced_model,
            inputs=[ct_input],
            convert_to="mlprogram",
            minimum_deployment_target=ct.target.iOS16,
        )
        elapsed = time.time() - t0
        print(f"  CoreML conversion: SUCCESS ({elapsed:.1f}s)")

        # Save
        mlmodel.save(output_path)
        size_mb = sum(
            os.path.getsize(os.path.join(dp, f))
            for dp, dn, filenames in os.walk(output_path)
            for f in filenames
        ) / (1024 * 1024)
        print(f"  Saved: {output_path} ({size_mb:.1f} MB)")

        # Numerical comparison
        if ref_output is not None:
            print("  Running CoreML prediction for numerical comparison...")
            try:
                input_np = dummy_input.numpy()
                pred = mlmodel.predict({"input": input_np})
                # Get the output key
                out_keys = list(pred.keys())
                print(f"  CoreML output keys: {out_keys}")
                coreml_out = pred[out_keys[0]]
                ref_np = ref_output.detach().numpy()

                # Handle shape differences
                coreml_flat = np.array(coreml_out).flatten()
                ref_flat = ref_np.flatten()
                if coreml_flat.shape == ref_flat.shape:
                    max_diff = np.abs(coreml_flat - ref_flat).max()
                    mean_diff = np.abs(coreml_flat - ref_flat).mean()
                    print(f"  Max diff (PyTorch vs CoreML): {max_diff:.6f}")
                    print(f"  Mean diff (PyTorch vs CoreML): {mean_diff:.6f}")
                else:
                    print(f"  Shape mismatch: CoreML={coreml_flat.shape}, "
                          f"PyTorch={ref_flat.shape}")
            except Exception as e:
                print(f"  Numerical comparison failed: {e}")

        return True

    except Exception as e:
        print(f"  CoreML conversion: FAILED")
        print(f"  Error: {e}")
        traceback.print_exc()
        return False


def try_onnx_then_coreml(model, dummy_input, name, onnx_path, coreml_path):
    """Try PyTorch → ONNX → CoreML path."""
    print(f"\n{'='*60}")
    print(f"ONNX → CoreML: {name}")
    print(f"{'='*60}")

    try:
        import onnx
        print("  onnx package available")
    except ImportError:
        print("  onnx package not installed — skipping ONNX path")
        return False

    try:
        model.eval()
        print(f"  Exporting to ONNX ({onnx_path}) ...")
        torch.onnx.export(
            model,
            dummy_input,
            onnx_path,
            input_names=["input"],
            output_names=["output"],
            opset_version=17,
            dynamic_axes=None,  # fixed shapes for now
        )
        onnx_size = os.path.getsize(onnx_path) / (1024 * 1024)
        print(f"  ONNX export: SUCCESS ({onnx_size:.1f} MB)")

        # Validate ONNX
        onnx_model = onnx.load(onnx_path)
        onnx.checker.check_model(onnx_model)
        print("  ONNX validation: PASSED")

        # Convert ONNX → CoreML
        print("  Converting ONNX → CoreML ...")
        mlmodel = ct.converters.onnx.convert(model=onnx_path)
        mlmodel.save(coreml_path)
        print(f"  ONNX → CoreML: SUCCESS → {coreml_path}")
        return True

    except Exception as e:
        print(f"  ONNX → CoreML: FAILED")
        print(f"  Error: {e}")
        traceback.print_exc()
        return False


# ============================================================
# Main
# ============================================================
def main():
    print("=" * 60)
    print("SwingNet → CoreML Conversion Test")
    print("=" * 60)
    print(f"PyTorch version: {torch.__version__}")
    print(f"coremltools version: {ct.__version__}")

    output_dir = os.path.dirname(os.path.abspath(__file__))
    SEQ_LEN = 64  # Standard SwingNet sequence length

    # ----------------------------------------------------------
    # Test A: Full EventDetector (CNN + BiLSTM + Linear)
    # ----------------------------------------------------------
    print("\n\n" + "#" * 60)
    print("# TEST A: Full EventDetector (MobileNetV2 + BiLSTM)")
    print("#" * 60)

    full_model = EventDetectorCPU(
        width_mult=1.0,
        lstm_layers=1,
        lstm_hidden=256,
        bidirectional=True,
    )
    full_model.eval()

    param_count = sum(p.numel() for p in full_model.parameters())
    print(f"  Total parameters: {param_count:,} ({param_count/1e6:.2f}M)")

    dummy_full = torch.randn(1, SEQ_LEN, 3, 160, 160)

    traced_full, ref_full = try_jit_trace(full_model, dummy_full, "Full EventDetector")
    success_full = try_coreml_convert(
        traced_full, dummy_full, "Full EventDetector",
        os.path.join(output_dir, "swingnet_full.mlpackage"),
        ref_full
    )

    # ----------------------------------------------------------
    # Test B: CNN only (MobileNetV2 backbone)
    # ----------------------------------------------------------
    print("\n\n" + "#" * 60)
    print("# TEST B: CNN Only (MobileNetV2)")
    print("#" * 60)

    cnn_model = SwingNetCNN(width_mult=1.0)
    cnn_model.eval()

    param_count_cnn = sum(p.numel() for p in cnn_model.parameters())
    print(f"  CNN parameters: {param_count_cnn:,} ({param_count_cnn/1e6:.2f}M)")

    dummy_cnn = torch.randn(1, 3, 160, 160)

    traced_cnn, ref_cnn = try_jit_trace(cnn_model, dummy_cnn, "CNN Only")
    success_cnn = try_coreml_convert(
        traced_cnn, dummy_cnn, "CNN Only",
        os.path.join(output_dir, "swingnet_cnn.mlpackage"),
        ref_cnn
    )

    # ----------------------------------------------------------
    # Test C: LSTM only (sequence model)
    # ----------------------------------------------------------
    print("\n\n" + "#" * 60)
    print("# TEST C: LSTM Only")
    print("#" * 60)

    lstm_model = SwingNetLSTM(
        lstm_layers=1,
        lstm_hidden=256,
        bidirectional=True,
        input_size=1280,
    )
    lstm_model.eval()

    param_count_lstm = sum(p.numel() for p in lstm_model.parameters())
    print(f"  LSTM parameters: {param_count_lstm:,} ({param_count_lstm/1e6:.2f}M)")

    dummy_lstm = torch.randn(1, SEQ_LEN, 1280)

    traced_lstm, ref_lstm = try_jit_trace(lstm_model, dummy_lstm, "LSTM Only")
    success_lstm = try_coreml_convert(
        traced_lstm, dummy_lstm, "LSTM Only",
        os.path.join(output_dir, "swingnet_lstm.mlpackage"),
        ref_lstm
    )

    # ----------------------------------------------------------
    # Test D: Full model with shorter sequence (16 frames)
    # ----------------------------------------------------------
    if not success_full:
        print("\n\n" + "#" * 60)
        print("# TEST D: Full EventDetector with 16-frame sequence")
        print("#" * 60)

        dummy_short = torch.randn(1, 16, 3, 160, 160)
        traced_short, ref_short = try_jit_trace(
            full_model, dummy_short, "Full EventDetector (16 frames)"
        )
        success_short = try_coreml_convert(
            traced_short, dummy_short, "Full EventDetector (16 frames)",
            os.path.join(output_dir, "swingnet_full_16f.mlpackage"),
            ref_short
        )

    # ----------------------------------------------------------
    # Test E: ONNX intermediate path (if direct conversion failed)
    # ----------------------------------------------------------
    if not success_full:
        print("\n\n" + "#" * 60)
        print("# TEST E: Full EventDetector via ONNX")
        print("#" * 60)
        try_onnx_then_coreml(
            full_model, dummy_full, "Full EventDetector via ONNX",
            os.path.join(output_dir, "swingnet_full.onnx"),
            os.path.join(output_dir, "swingnet_full_onnx.mlpackage"),
        )

    # ----------------------------------------------------------
    # Summary
    # ----------------------------------------------------------
    print("\n\n" + "=" * 60)
    print("CONVERSION SUMMARY")
    print("=" * 60)
    print(f"  Full model (CNN+BiLSTM) → CoreML: {'SUCCESS' if success_full else 'FAILED'}")
    print(f"  CNN only (MobileNetV2)  → CoreML: {'SUCCESS' if success_cnn else 'FAILED'}")
    print(f"  LSTM only (BiLSTM+Lin)  → CoreML: {'SUCCESS' if success_lstm else 'FAILED'}")

    if success_cnn and success_lstm and not success_full:
        print("\n  RECOMMENDATION: Use split architecture (CNN + LSTM as separate CoreML models)")
        print("  On iOS, run CNN per-frame, collect features, then run LSTM on the sequence.")

    if success_full:
        print("\n  Full model converts directly — single .mlpackage for iOS integration.")


if __name__ == "__main__":
    main()
