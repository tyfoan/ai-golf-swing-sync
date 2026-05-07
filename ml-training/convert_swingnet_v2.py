#!/usr/bin/env python3
"""
SwingNet → CoreML conversion v2.
Addresses:
  1. torch 2.10 'int' op incompatibility with coremltools 9.0
  2. BlobWriter not loaded (Python 3.14 incompatibility)

Strategy:
  A. Rewrite forward() to avoid dynamic .size() → int conversions
  B. Try neuralnetwork format instead of mlprogram
  C. Try exporting via ONNX as intermediate
  D. Try torch.export (ExecuTorch path) as alternative
"""

import sys
import os
import time
import traceback

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "golfdb_repo"))

import torch
import torch.nn as nn
import numpy as np
import coremltools as ct


from MobileNetV2 import MobileNetV2


# ============================================================
# Fixed-shape models (no dynamic size queries)
# ============================================================

class SwingNetCNNFixed(nn.Module):
    """MobileNetV2 CNN with absolutely no dynamic shape ops."""

    def __init__(self, width_mult=1.0):
        super().__init__()
        net = MobileNetV2(width_mult=width_mult)
        self.cnn = nn.Sequential(*list(net.children())[0][:19])
        # Add explicit global average pooling layer
        self.pool = nn.AdaptiveAvgPool2d(1)

    def forward(self, x):
        # x: [1, 3, 160, 160] — single frame
        feat = self.cnn(x)  # [1, 1280, 5, 5]
        feat = self.pool(feat)  # [1, 1280, 1, 1]
        feat = feat.squeeze(-1).squeeze(-1)  # [1, 1280]
        return feat


class SwingNetLSTMFixed(nn.Module):
    """BiLSTM with fixed batch=1, no dynamic shape queries."""

    def __init__(self, seq_len=64, lstm_hidden=256, input_size=1280):
        super().__init__()
        self.lstm_hidden = lstm_hidden
        self.rnn = nn.LSTM(
            input_size, lstm_hidden, num_layers=1,
            batch_first=True, bidirectional=True
        )
        self.lin = nn.Linear(2 * lstm_hidden, 9)

    def forward(self, x):
        # x: [1, seq_len, 1280] — fixed batch=1
        # Do NOT query x.size() — use hardcoded constants
        h0 = torch.zeros(2, 1, self.lstm_hidden)  # 2 directions, batch=1
        c0 = torch.zeros(2, 1, self.lstm_hidden)
        r_out, _ = self.rnn(x, (h0, c0))
        out = self.lin(r_out)  # [1, seq_len, 9]
        return out


class SwingNetFullFixed(nn.Module):
    """Full EventDetector with fixed shapes — no dynamic size queries."""

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
        # Reshape WITHOUT using x.size() — use constants
        c_in = x.reshape(self.BATCH * self.SEQ_LEN, 3, 160, 160)
        c_out = self.cnn(c_in)  # [64, 1280, 5, 5]
        c_out = self.pool(c_out)  # [64, 1280, 1, 1]
        c_out = c_out.squeeze(-1).squeeze(-1)  # [64, 1280]

        # LSTM
        r_in = c_out.reshape(self.BATCH, self.SEQ_LEN, -1)
        h0 = torch.zeros(2, self.BATCH, self.lstm_hidden)
        c0 = torch.zeros(2, self.BATCH, self.lstm_hidden)
        r_out, _ = self.rnn(r_in, (h0, c0))

        out = self.lin(r_out)  # [1, 64, 9]
        out = out.reshape(self.BATCH * self.SEQ_LEN, 9)
        return out


def try_conversion(model, dummy_input, name, output_path, convert_to="mlprogram",
                   target=None):
    """Try trace + convert with given settings."""
    print(f"\n{'='*60}")
    print(f"Attempt: {name} [format={convert_to}]")
    print(f"{'='*60}")

    model.eval()

    # Step 1: JIT trace
    try:
        with torch.no_grad():
            ref_out = model(dummy_input)
        traced = torch.jit.trace(model, dummy_input)
        with torch.no_grad():
            traced_out = traced(dummy_input)
        diff = (ref_out - traced_out).abs().max().item()
        print(f"  JIT trace: OK (max diff={diff:.2e})")
        print(f"  Output shape: {ref_out.shape}")
    except Exception as e:
        print(f"  JIT trace: FAILED — {e}")
        return False

    # Step 2: CoreML convert
    try:
        kwargs = {
            "inputs": [ct.TensorType(name="input", shape=dummy_input.shape)],
            "convert_to": convert_to,
        }
        if target:
            kwargs["minimum_deployment_target"] = target

        t0 = time.time()
        mlmodel = ct.convert(traced, **kwargs)
        elapsed = time.time() - t0
        print(f"  CoreML convert: OK ({elapsed:.1f}s)")

        # Save
        mlmodel.save(output_path)
        if os.path.isdir(output_path):
            size = sum(
                os.path.getsize(os.path.join(dp, f))
                for dp, dn, fns in os.walk(output_path) for f in fns
            ) / (1024 * 1024)
        else:
            size = os.path.getsize(output_path) / (1024 * 1024)
        print(f"  Saved: {output_path} ({size:.1f} MB)")
        return True

    except Exception as e:
        print(f"  CoreML convert: FAILED")
        print(f"  Error type: {type(e).__name__}")
        print(f"  Error: {e}")
        # Print just the last few lines of traceback
        tb = traceback.format_exc().split("\n")
        for line in tb[-6:]:
            if line.strip():
                print(f"    {line}")
        return False


def try_onnx_conversion(model, dummy_input, name, onnx_path, coreml_path):
    """Try PyTorch → ONNX → CoreML."""
    print(f"\n{'='*60}")
    print(f"ONNX path: {name}")
    print(f"{'='*60}")

    model.eval()

    # Step 1: Export ONNX
    try:
        torch.onnx.export(
            model, dummy_input, onnx_path,
            input_names=["input"],
            output_names=["output"],
            opset_version=17,
        )
        size = os.path.getsize(onnx_path) / (1024 * 1024)
        print(f"  ONNX export: OK ({size:.1f} MB)")
    except Exception as e:
        print(f"  ONNX export: FAILED — {e}")
        return False

    # Step 2: Validate ONNX
    try:
        import onnx
        m = onnx.load(onnx_path)
        onnx.checker.check_model(m)
        print(f"  ONNX validate: OK")
    except ImportError:
        print(f"  ONNX validate: skipped (onnx not installed)")
    except Exception as e:
        print(f"  ONNX validate: FAILED — {e}")

    # Step 3: ONNX → CoreML via coremltools unified converter
    try:
        mlmodel = ct.convert(
            onnx_path,
            convert_to="mlprogram",
            minimum_deployment_target=ct.target.iOS16,
        )
        mlmodel.save(coreml_path)
        print(f"  ONNX → CoreML: OK → {coreml_path}")
        return True
    except Exception as e:
        print(f"  ONNX → CoreML: FAILED — {e}")

    # Step 3b: Try neuralnetwork format
    try:
        mlmodel = ct.convert(
            onnx_path,
            convert_to="neuralnetwork",
        )
        nn_path = coreml_path.replace(".mlpackage", ".mlmodel")
        mlmodel.save(nn_path)
        print(f"  ONNX → CoreML (neuralnetwork): OK → {nn_path}")
        return True
    except Exception as e:
        print(f"  ONNX → CoreML (neuralnetwork): FAILED — {e}")

    return False


def main():
    print("=" * 60)
    print("SwingNet → CoreML Conversion v2 (Fixed Shapes)")
    print("=" * 60)
    print(f"Python:       {sys.version}")
    print(f"PyTorch:      {torch.__version__}")
    print(f"coremltools:  {ct.__version__}")
    print()
    print("NOTE: coremltools 9.0 supports Python ≤3.12.")
    print("      Python 3.14 may cause BlobWriter errors.")
    print("      Torch 2.10 may cause 'int' op errors.")
    print()

    output_dir = os.path.dirname(os.path.abspath(__file__))
    results = {}

    # ----------------------------------------------------------
    # Test 1: CNN only — fixed shapes, mlprogram
    # ----------------------------------------------------------
    cnn = SwingNetCNNFixed()
    dummy_cnn = torch.randn(1, 3, 160, 160)

    results["CNN mlprogram iOS16"] = try_conversion(
        cnn, dummy_cnn, "CNN Fixed (mlprogram, iOS16)",
        os.path.join(output_dir, "swingnet_cnn_v2.mlpackage"),
        convert_to="mlprogram",
        target=ct.target.iOS16,
    )

    # ----------------------------------------------------------
    # Test 2: CNN only — neuralnetwork format (older, more compatible)
    # ----------------------------------------------------------
    results["CNN neuralnetwork"] = try_conversion(
        cnn, dummy_cnn, "CNN Fixed (neuralnetwork)",
        os.path.join(output_dir, "swingnet_cnn_v2.mlmodel"),
        convert_to="neuralnetwork",
    )

    # ----------------------------------------------------------
    # Test 3: LSTM only — fixed shapes, mlprogram
    # ----------------------------------------------------------
    lstm = SwingNetLSTMFixed(seq_len=64)
    dummy_lstm = torch.randn(1, 64, 1280)

    results["LSTM mlprogram iOS16"] = try_conversion(
        lstm, dummy_lstm, "LSTM Fixed (mlprogram, iOS16)",
        os.path.join(output_dir, "swingnet_lstm_v2.mlpackage"),
        convert_to="mlprogram",
        target=ct.target.iOS16,
    )

    # ----------------------------------------------------------
    # Test 4: LSTM only — neuralnetwork
    # ----------------------------------------------------------
    results["LSTM neuralnetwork"] = try_conversion(
        lstm, dummy_lstm, "LSTM Fixed (neuralnetwork)",
        os.path.join(output_dir, "swingnet_lstm_v2.mlmodel"),
        convert_to="neuralnetwork",
    )

    # ----------------------------------------------------------
    # Test 5: Full model — fixed shapes, mlprogram
    # ----------------------------------------------------------
    full = SwingNetFullFixed()
    dummy_full = torch.randn(1, 64, 3, 160, 160)

    results["Full mlprogram iOS16"] = try_conversion(
        full, dummy_full, "Full Fixed (mlprogram, iOS16)",
        os.path.join(output_dir, "swingnet_full_v2.mlpackage"),
        convert_to="mlprogram",
        target=ct.target.iOS16,
    )

    # ----------------------------------------------------------
    # Test 6: Full model — neuralnetwork
    # ----------------------------------------------------------
    results["Full neuralnetwork"] = try_conversion(
        full, dummy_full, "Full Fixed (neuralnetwork)",
        os.path.join(output_dir, "swingnet_full_v2.mlmodel"),
        convert_to="neuralnetwork",
    )

    # ----------------------------------------------------------
    # Test 7: ONNX intermediate path
    # ----------------------------------------------------------
    print("\n\n" + "#" * 60)
    print("# ONNX Intermediate Paths")
    print("#" * 60)

    results["CNN via ONNX"] = try_onnx_conversion(
        cnn, dummy_cnn, "CNN via ONNX",
        os.path.join(output_dir, "swingnet_cnn.onnx"),
        os.path.join(output_dir, "swingnet_cnn_onnx.mlpackage"),
    )

    results["LSTM via ONNX"] = try_onnx_conversion(
        lstm, dummy_lstm, "LSTM via ONNX",
        os.path.join(output_dir, "swingnet_lstm.onnx"),
        os.path.join(output_dir, "swingnet_lstm_onnx.mlpackage"),
    )

    results["Full via ONNX"] = try_onnx_conversion(
        full, dummy_full, "Full via ONNX",
        os.path.join(output_dir, "swingnet_full.onnx"),
        os.path.join(output_dir, "swingnet_full_onnx.mlpackage"),
    )

    # ----------------------------------------------------------
    # Summary
    # ----------------------------------------------------------
    print("\n\n" + "=" * 60)
    print("CONVERSION RESULTS SUMMARY")
    print("=" * 60)
    for test_name, success in results.items():
        status = "SUCCESS" if success else "FAILED"
        print(f"  {test_name:30s} → {status}")

    successes = [k for k, v in results.items() if v]
    if successes:
        print(f"\n  {len(successes)} path(s) succeeded!")
    else:
        print(f"\n  ALL PATHS FAILED.")
        print("  Root causes:")
        print("    1. Python 3.14 → coremltools native extensions missing (BlobWriter)")
        print("    2. torch 2.10 → coremltools 9.0 op compatibility issues")
        print("  Fix: Use Python 3.11-3.12 with torch 2.7 and coremltools 8.x or 9.0")


if __name__ == "__main__":
    main()
