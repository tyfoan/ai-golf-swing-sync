"""
SwingNet evaluation script.

Evaluates a pre-trained SwingNet model on the GolfDB validation set,
computing per-event PCE (Percentage of Correct Events).

Requires GolfDB data (videos_160/ and split pickle files).

Usage:
    python evaluate.py --checkpoint models/swingnet_1800.pth.tar --split 1
    python evaluate.py --checkpoint models/swingnet_1800.pth.tar --split 1 --verbose
"""

import argparse
import os

import numpy as np
import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader

from dataset import GolfDBDataset
from metrics import compute_per_event_pce, evaluate_predictions, format_pce_table
from model import NUM_CLASSES, load_pretrained


def run_evaluation(model, data_file, video_dir, seq_length=64,
                   device=None, verbose=True):
    """Evaluate a model on a validation split.

    Processes full-length videos in seq_length-sized chunks,
    concatenates predictions, then computes PCE per event.

    Args:
        model: SwingNet model (on device, in eval mode)
        data_file: path to validation split pickle
        video_dir: path to preprocessed 160x160 video clips
        seq_length: chunk size for inference
        device: torch device
        verbose: print per-video results
    Returns:
        Average PCE across all 8 events
    """
    if device is None:
        device = next(model.parameters()).device

    dataset = GolfDBDataset(
        data_file=data_file,
        video_dir=video_dir,
        seq_length=seq_length,
        training=False,
        augment=False,
    )
    loader = DataLoader(dataset, batch_size=1, shuffle=False, num_workers=4)

    results = []
    for i, sample in enumerate(loader):
        probs = _predict_full_video(model, sample["images"], seq_length, device)
        labels = sample["labels"].squeeze().numpy()

        result = evaluate_predictions(probs, labels)
        results.append(result)

        if verbose:
            correct_str = "".join("Y" if c else "." for c in result["correct"])
            print(f"  Video {i:3d}: tol={result['tolerance']:2d}  [{correct_str}]")

    per_event = compute_per_event_pce(results)

    if verbose:
        print(f"\n{format_pce_table(per_event)}")

    return np.mean(list(per_event.values()))


def _predict_full_video(model, images, seq_length, device):
    """Run inference on a full-length video in seq_length-sized chunks.

    Args:
        model: SwingNet model
        images: (1, total_frames, 3, H, W) tensor
        seq_length: chunk size
        device: torch device
    Returns:
        (total_frames, 9) numpy array of softmax probabilities
    """
    total_frames = images.shape[1]
    all_probs = []

    chunk_start = 0
    while chunk_start < total_frames:
        chunk_end = min(chunk_start + seq_length, total_frames)
        chunk = images[:, chunk_start:chunk_end].to(device)

        with torch.no_grad():
            logits = model(chunk)  # (chunk_len, 9) — flattened output
            probs = F.softmax(logits, dim=-1)
            all_probs.append(probs.cpu().numpy())

        chunk_start = chunk_end

    return np.concatenate(all_probs, axis=0)


def _select_device():
    if torch.cuda.is_available():
        return torch.device("cuda")
    if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def parse_args():
    parser = argparse.ArgumentParser(description="Evaluate SwingNet on GolfDB")
    parser.add_argument("--checkpoint", type=str, required=True)
    parser.add_argument("--split", type=int, default=1, help="Validation fold (1-4)")
    parser.add_argument("--seq_length", type=int, default=64)
    parser.add_argument("--data_dir", type=str, default="data/")
    parser.add_argument("--video_dir", type=str, default="data/videos_160/")
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    device = _select_device()
    model = load_pretrained(args.checkpoint, device=device)

    data_file = os.path.join(args.data_dir, f"val_split_{args.split}.pkl")
    print(f"Evaluating: {args.checkpoint}")
    print(f"Split: {args.split}, Device: {device}\n")

    pce = run_evaluation(
        model=model, data_file=data_file, video_dir=args.video_dir,
        seq_length=args.seq_length, device=device, verbose=args.verbose,
    )
    print(f"\nAverage PCE: {pce:.1%}")


if __name__ == "__main__":
    main()
