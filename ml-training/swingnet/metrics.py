"""
Evaluation metrics for SwingNet golf swing event detection.

Implements the Percentage of Correct Events (PCE) metric from the GolfDB paper.
Tolerance is adaptive: max(round((impact_frame - address_frame) / 30), 1).
"""

import numpy as np


def compute_tolerance(events):
    """Compute adaptive tolerance based on swing duration.

    Tolerance = max(round((impact_frame - address_frame) / 30), 1)
    This scales with swing speed: faster swings get tighter tolerance.

    Args:
        events: array of ground-truth event frame indices (8 events)
    Returns:
        Integer tolerance in frames
    """
    address_frame = events[0]
    impact_frame = events[5]
    return max(round((impact_frame - address_frame) / 30), 1)


def find_predicted_events(probs, num_events=8):
    """Find predicted frame index for each event class.

    For each event class k, the predicted frame is argmax(probs[:, k]).

    Args:
        probs: (seq_len, 9) probability array
        num_events: number of event classes (default 8)
    Returns:
        (num_events,) array of predicted frame indices
    """
    predictions = np.zeros(num_events, dtype=np.int64)
    for k in range(num_events):
        predictions[k] = np.argmax(probs[:, k])
    return predictions


def evaluate_predictions(probs, labels, tolerance=None):
    """Evaluate predictions for a single video.

    Args:
        probs: (seq_len, 9) softmax probabilities
        labels: (seq_len,) ground-truth labels
        tolerance: optional fixed tolerance; if None, computed from events
    Returns:
        dict with keys:
            - "events": ground-truth event frame indices
            - "predictions": predicted event frame indices
            - "deltas": absolute frame errors
            - "tolerance": tolerance used
            - "correct": boolean array per event
    """
    event_indices = np.where(labels < 8)[0]
    predicted = find_predicted_events(probs, num_events=len(event_indices))

    if tolerance is None:
        tolerance = compute_tolerance(event_indices)

    deltas = np.abs(event_indices - predicted)
    correct = deltas <= tolerance

    return {
        "events": event_indices,
        "predictions": predicted,
        "deltas": deltas,
        "tolerance": tolerance,
        "correct": correct,
    }


EVENT_NAMES = [
    "address",
    "toe-up",
    "mid-backswing",
    "top",
    "mid-downswing",
    "impact",
    "mid-follow-through",
    "finish",
]


def compute_per_event_pce(results_list):
    """Compute PCE per event class across multiple videos.

    Args:
        results_list: list of dicts from evaluate_predictions
    Returns:
        dict mapping event name to PCE (0.0-1.0)
    """
    num_events = len(EVENT_NAMES)
    correct_counts = np.zeros(num_events)
    total_counts = np.zeros(num_events)

    for result in results_list:
        correct = result["correct"]
        n = min(len(correct), num_events)
        correct_counts[:n] += correct[:n]
        total_counts[:n] += 1

    pce = {}
    for i, name in enumerate(EVENT_NAMES):
        if total_counts[i] > 0:
            pce[name] = correct_counts[i] / total_counts[i]
        else:
            pce[name] = 0.0

    return pce


def format_pce_table(per_event_pce):
    """Format PCE results as a readable table string."""
    lines = ["Event              PCE", "-" * 28]
    total = 0.0
    count = 0
    for name, pce in per_event_pce.items():
        lines.append(f"{name:<20s} {pce:.1%}")
        total += pce
        count += 1
    avg = total / count if count > 0 else 0.0
    lines.append("-" * 28)
    lines.append(f"{'Average':<20s} {avg:.1%}")
    return "\n".join(lines)
