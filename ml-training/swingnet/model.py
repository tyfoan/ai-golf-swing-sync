"""
SwingNet: MobileNetV2 + Bidirectional LSTM for golf swing event detection.

Architecture reimplementation based on the GolfDB paper (McNally et al., CVPR 2019).
Weight-compatible with the pre-trained swingnet_1800.pth.tar checkpoint.

The module names (cnn, rnn, lin) match the original checkpoint key prefixes,
enabling direct load_state_dict() from pre-trained weights.

Input:  (batch, seq_len, 3, 160, 160) — RGB video frames
Output: (batch * seq_len, 9)           — per-frame logits (flattened)
"""

import torch
import torch.nn as nn
from torchvision.models import mobilenet_v2, MobileNet_V2_Weights


NUM_EVENTS = 8
NUM_CLASSES = NUM_EVENTS + 1  # 8 swing events + no-event
FEATURE_DIM = 1280
DEFAULT_HIDDEN = 256

EVENT_NAMES = [
    "address", "toe-up", "mid-backswing", "top",
    "mid-downswing", "impact", "mid-follow-through", "finish",
]


class SwingNet(nn.Module):
    """End-to-end golf swing event detector.

    Architecture:
        MobileNetV2 (.features, 19 layers) -> global avg pool -> [Dropout]
        -> BiLSTM(1280, 256) -> Linear(512, 9)

    Weight keys match the original GolfDB checkpoint:
        cnn.{0..18}.* -- MobileNetV2 feature layers
        rnn.*          -- BiLSTM parameters
        lin.*          -- output linear layer

    8 swing events:
        0: address, 1: toe-up, 2: mid-backswing, 3: top,
        4: mid-downswing, 5: impact, 6: mid-follow-through, 7: finish
    Plus class 8: no-event
    """

    def __init__(self, lstm_hidden=DEFAULT_HIDDEN, lstm_layers=1, dropout=False):
        super().__init__()
        self.lstm_hidden = lstm_hidden
        self.lstm_layers = lstm_layers
        self.use_dropout = dropout

        self.cnn = self._build_backbone()
        self.rnn = nn.LSTM(
            input_size=FEATURE_DIM,
            hidden_size=lstm_hidden,
            num_layers=lstm_layers,
            batch_first=True,
            bidirectional=True,
        )
        self.lin = nn.Linear(lstm_hidden * 2, NUM_CLASSES)

        if dropout:
            self.drop = nn.Dropout(0.5)

    def forward(self, x):
        """
        Args:
            x: (batch, seq_len, 3, 160, 160)
        Returns:
            (batch * seq_len, 9) -- flattened per-frame logits
        """
        batch_size, timesteps, c, h, w = x.size()

        features = self._encode_frames(x.view(batch_size * timesteps, c, h, w))
        temporal = self._encode_temporal(features, batch_size, timesteps)
        logits = self.lin(temporal)

        return logits.view(batch_size * timesteps, NUM_CLASSES)

    def predict_events(self, x):
        """Run inference and return per-frame probabilities.

        Args:
            x: (batch, seq_len, 3, 160, 160)
        Returns:
            (batch, seq_len, 9) -- softmax probabilities (reshaped)
        """
        batch_size, seq_len = x.shape[:2]
        with torch.no_grad():
            logits = self.forward(x)
            probs = torch.softmax(logits, dim=-1)
            return probs.view(batch_size, seq_len, NUM_CLASSES)

    def freeze_backbone(self, num_layers=10):
        """Freeze the first `num_layers` of the CNN backbone."""
        for i, layer in enumerate(self.cnn.children()):
            if i < num_layers:
                for param in layer.parameters():
                    param.requires_grad = False

    def _encode_frames(self, frames):
        """Extract per-frame CNN features.

        Args:
            frames: (batch * seq_len, 3, H, W)
        Returns:
            (batch * seq_len, 1280)
        """
        features = self.cnn(frames)
        features = features.mean(3).mean(2)  # global average pool
        if self.use_dropout:
            features = self.drop(features)
        return features

    def _encode_temporal(self, features, batch_size, timesteps):
        """Model temporal dependencies with BiLSTM.

        Args:
            features: (batch * seq_len, 1280)
        Returns:
            (batch, seq_len, 512)
        """
        sequence = features.view(batch_size, timesteps, -1)
        output, _ = self.rnn(sequence)
        return output

    def _build_backbone(self):
        """Build MobileNetV2 feature extractor (19 layers)."""
        backbone = mobilenet_v2(weights=MobileNet_V2_Weights.IMAGENET1K_V1)
        return nn.Sequential(*list(backbone.features.children()))


def load_pretrained(checkpoint_path, device="cpu"):
    """Load SwingNet from a pre-trained GolfDB checkpoint.

    Handles the weight key mapping between the original GolfDB MobileNetV2
    (custom implementation) and torchvision's MobileNetV2. The layer
    structures are identical but internal naming differs slightly.

    Args:
        checkpoint_path: path to swingnet_*.pth.tar
        device: target device string or torch.device
    Returns:
        SwingNet model in eval mode with loaded weights
    """
    model = SwingNet(lstm_hidden=DEFAULT_HIDDEN, lstm_layers=1, dropout=False)
    checkpoint = torch.load(checkpoint_path, map_location=device, weights_only=True)
    saved_state = checkpoint["model_state_dict"]

    mapped = _map_weights(saved_state, model.state_dict())
    model.load_state_dict(mapped, strict=True)
    model.to(device)
    model.eval()
    return model


def _map_weights(saved_state, model_state):
    """Map checkpoint keys to model keys by module prefix and order.

    The original and torchvision MobileNetV2 have the same layer structure
    (19 sequential blocks producing 1280-dim features) but different key
    names inside InvertedResidual blocks. We match by ordered position
    within each top-level module (cnn, rnn, lin).
    """
    if set(saved_state.keys()) == set(model_state.keys()):
        return saved_state

    saved_grouped = _group_by_prefix(saved_state)
    model_grouped = _group_by_prefix(model_state)

    mapped = {}
    for prefix in ["cnn", "rnn", "lin"]:
        s_keys = saved_grouped.get(prefix, [])
        m_keys = model_grouped.get(prefix, [])
        assert len(s_keys) == len(m_keys), (
            f"Key count mismatch for '{prefix}': {len(s_keys)} vs {len(m_keys)}"
        )
        for s_key, m_key in zip(s_keys, m_keys):
            assert saved_state[s_key].shape == model_state[m_key].shape, (
                f"Shape mismatch: {s_key} {saved_state[s_key].shape} "
                f"vs {m_key} {model_state[m_key].shape}"
            )
            mapped[m_key] = saved_state[s_key]

    return mapped


def _group_by_prefix(state_dict):
    """Group state dict keys by top-level module prefix, preserving order."""
    groups = {}
    for key in state_dict.keys():
        prefix = key.split(".")[0]
        groups.setdefault(prefix, []).append(key)
    return groups
