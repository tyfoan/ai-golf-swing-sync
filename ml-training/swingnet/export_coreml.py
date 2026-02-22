"""
Export pre-trained SwingNet to CoreML format with int8 quantization.

Produces a .mlpackage file suitable for on-device inference on iOS.

Usage:
    python export_coreml.py --checkpoint models/swingnet_1800.pth.tar
    python export_coreml.py --checkpoint models/swingnet_1800.pth.tar --output SwingNet.mlpackage
    python export_coreml.py --checkpoint models/swingnet_1800.pth.tar --no-quantize

The exported model accepts:
    - Input: "frames" -- (1, seq_len, 3, 160, 160) float32 RGB tensor
    - Output: "logits" -- (1, seq_len, 9) float32 per-frame event logits

For on-device use, apply softmax to logits and use argmax(probs[:, 5])
to find the impact frame.
"""

import argparse
from pathlib import Path

import coremltools as ct
import torch
import torch.nn as nn

from model import NUM_CLASSES, load_pretrained


class SwingNetForExport(nn.Module):
    """Tracing wrapper that reshapes output to (1, seq_len, 9).

    The raw SwingNet returns (batch * seq_len, 9) which is not ideal
    for CoreML. This wrapper reshapes to (1, seq_len, 9) for batch=1
    inference, which is the standard on-device use case.
    """

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, x):
        """
        Args:
            x: (1, seq_len, 3, 160, 160)
        Returns:
            (1, seq_len, 9) -- per-frame logits
        """
        seq_len = x.shape[1]
        flat_logits = self.model(x)  # (seq_len, 9)
        return flat_logits.view(1, seq_len, NUM_CLASSES)


def export_to_coreml(checkpoint_path, output_path, seq_length=64, quantize=True):
    """Convert a SwingNet checkpoint to CoreML .mlpackage format.

    Args:
        checkpoint_path: path to .pth.tar checkpoint
        output_path: destination .mlpackage path
        seq_length: sequence length for tracing
        quantize: whether to apply int8 weight quantization
    """
    model = load_pretrained(checkpoint_path, device="cpu")
    traced = _trace_model(model, seq_length)
    mlmodel = _convert_to_coreml(traced, seq_length)

    if quantize:
        mlmodel = _quantize_int8(mlmodel)

    mlmodel.save(output_path)
    _print_summary(output_path, quantize)


def _trace_model(model, seq_length):
    """Trace the model with an example input for TorchScript conversion."""
    wrapper = SwingNetForExport(model)
    wrapper.eval()
    example = torch.randn(1, seq_length, 3, 160, 160)

    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example)

    # Verify traced output
    with torch.no_grad():
        out = traced(example)
        assert out.shape == (1, seq_length, NUM_CLASSES), (
            f"Expected (1, {seq_length}, {NUM_CLASSES}), got {out.shape}"
        )

    return traced


def _convert_to_coreml(traced_model, seq_length):
    """Convert traced PyTorch model to CoreML mlprogram."""
    frames_shape = ct.Shape(
        shape=(
            1,
            ct.RangeDim(lower_bound=1, upper_bound=512, default=seq_length),
            3, 160, 160,
        )
    )

    mlmodel = ct.convert(
        traced_model,
        inputs=[ct.TensorType(name="frames", shape=frames_shape)],
        outputs=[ct.TensorType(name="logits")],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
    )

    mlmodel.author = "Golf Sync Swing"
    mlmodel.short_description = (
        "SwingNet: MobileNetV2+BiLSTM golf swing event detector. "
        "Detects 8 swing phases per frame. "
        "Use argmax(softmax(logits)[:, 5]) for impact frame."
    )
    mlmodel.version = "1.0"

    return mlmodel


def _quantize_int8(mlmodel):
    """Apply int8 weight quantization to reduce model size (~4x smaller)."""
    return ct.compression_utils.affine_quantize_weights(
        mlmodel, mode="linear_symmetric",
    )


def _print_summary(output_path, quantized):
    """Print export summary with file size."""
    path = Path(output_path)
    if not path.exists():
        return

    total_bytes = sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
    size_mb = total_bytes / (1024 * 1024)
    quant_str = "int8 quantized" if quantized else "float32"

    print(f"\nExport complete:")
    print(f"  Output:   {output_path}")
    print(f"  Size:     {size_mb:.1f} MB ({quant_str})")
    print(f"  Input:    frames (1, 1-512, 3, 160, 160)")
    print(f"  Output:   logits (1, seq_len, 9)")
    print(f"\niOS usage:")
    print(f"  let probs = softmax(logits)")
    print(f"  let impactFrame = argmax(probs[:, 5])")


def parse_args():
    parser = argparse.ArgumentParser(description="Export SwingNet to CoreML")
    parser.add_argument("--checkpoint", type=str, required=True,
                        help="Path to swingnet_*.pth.tar checkpoint")
    parser.add_argument("--output", type=str, default="SwingNet.mlpackage",
                        help="Output .mlpackage path")
    parser.add_argument("--seq_length", type=int, default=64)
    parser.add_argument("--no-quantize", action="store_true",
                        help="Skip int8 quantization")
    return parser.parse_args()


def main():
    args = parse_args()
    export_to_coreml(
        checkpoint_path=args.checkpoint,
        output_path=args.output,
        seq_length=args.seq_length,
        quantize=not args.no_quantize,
    )


if __name__ == "__main__":
    main()
