"""
GolfDB dataset loader for SwingNet training and evaluation.

Handles:
- Loading preprocessed 160x160 video clips from GolfDB
- Parsing annotation DataFrames (split pickle files)
- Frame-level label generation (8 events + no-event)
- Training: random 64-frame clip sampling with augmentation
- Evaluation: full-length video sequences
"""

import os

import cv2
import numpy as np
import pandas as pd
import torch
from torch.utils.data import Dataset


class GolfDBDataset(Dataset):
    """GolfDB video dataset for golf swing event detection.

    Each sample is a video clip with per-frame labels:
        - Classes 0-7: the 8 swing events (address, toe-up, mid-backswing,
          top, mid-downswing, impact, mid-follow-through, finish)
        - Class 8: no-event (all other frames)

    During training, random fixed-length clips are sampled.
    During evaluation, the full video is returned.
    """

    IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    NO_EVENT_CLASS = 8

    def __init__(self, data_file, video_dir, seq_length=64, training=True, augment=True):
        self.annotations = pd.read_pickle(data_file)
        self.video_dir = video_dir
        self.seq_length = seq_length
        self.training = training
        self.augment = augment and training

    def __len__(self):
        return len(self.annotations)

    def __getitem__(self, idx):
        annotation = self.annotations.loc[idx]
        events = annotation["events"].copy()
        events -= events[0]  # normalize to clip-relative frame indices

        video_path = os.path.join(self.video_dir, f"{annotation['id']}.mp4")
        frames, labels = self._load_clip(video_path, events)

        frames = self._preprocess(frames)

        return {
            "images": torch.from_numpy(frames),
            "labels": torch.from_numpy(labels).long(),
        }

    def _load_clip(self, video_path, events):
        """Load frames and generate per-frame labels from a video clip."""
        cap = cv2.VideoCapture(video_path)
        event_frames = set(events[1:-1])  # exclude start/end boundaries
        event_lookup = {int(f): i for i, f in enumerate(events[1:-1])}

        frames, labels = self._read_frames(cap, events, event_frames, event_lookup)
        cap.release()
        return np.array(frames), np.array(labels)

    def _read_frames(self, cap, events, event_frames, event_lookup):
        """Read frames from video capture, either random clip or full video."""
        frames = []
        labels = []

        if self.training:
            return self._read_training_clip(cap, events, event_frames, event_lookup)

        return self._read_full_video(cap, event_frames, event_lookup)

    def _read_training_clip(self, cap, events, event_frames, event_lookup):
        """Sample a random fixed-length clip for training."""
        frames = []
        labels = []
        start_frame = np.random.randint(events[-1] + 1)
        cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
        pos = start_frame

        while len(frames) < self.seq_length:
            ret, frame = cap.read()
            if ret:
                frames.append(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
                labels.append(event_lookup.get(pos, self.NO_EVENT_CLASS))
                pos += 1
            else:
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                pos = 0

        return frames, labels

    def _read_full_video(self, cap, event_frames, event_lookup):
        """Read all frames from a video for evaluation."""
        frames = []
        labels = []
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

        for pos in range(total_frames):
            ret, frame = cap.read()
            if not ret:
                break
            frames.append(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
            labels.append(event_lookup.get(pos, self.NO_EVENT_CLASS))

        return frames, labels

    def _preprocess(self, frames):
        """Convert frames to normalized float tensors with optional augmentation.

        Args:
            frames: (seq_len, H, W, 3) uint8 array
        Returns:
            (seq_len, 3, H, W) float32 array, ImageNet-normalized
        """
        frames = frames.astype(np.float32) / 255.0

        if self.augment:
            frames = self._apply_augmentation(frames)

        # Normalize with ImageNet stats: (seq, H, W, 3)
        frames = (frames - self.IMAGENET_MEAN) / self.IMAGENET_STD

        # Transpose to (seq, 3, H, W)
        frames = frames.transpose(0, 3, 1, 2)

        return frames

    def _apply_augmentation(self, frames):
        """Apply consistent augmentation across all frames in a clip.

        Augmentations:
        - Random horizontal flip (50% chance)
        - Random affine: rotation +/-5 deg, shear +/-5 deg
        """
        if np.random.random() < 0.5:
            frames = frames[:, :, ::-1, :].copy()  # horizontal flip

        angle = np.random.uniform(-5, 5)
        shear = np.random.uniform(-5, 5)
        if abs(angle) > 0.5 or abs(shear) > 0.5:
            frames = self._apply_affine(frames, angle, shear)

        return frames

    def _apply_affine(self, frames, angle, shear):
        """Apply rotation and shear to all frames in a clip."""
        h, w = frames.shape[1], frames.shape[2]
        center = (w / 2, h / 2)

        rotation_matrix = cv2.getRotationMatrix2D(center, angle, 1.0)
        shear_rad = np.deg2rad(shear)
        shear_matrix = np.array([
            [1, np.tan(shear_rad), 0],
            [0, 1, 0],
        ], dtype=np.float64)
        transform = shear_matrix @ np.vstack([rotation_matrix, [0, 0, 1]])
        transform = transform[:2]

        result = np.empty_like(frames)
        for i in range(len(frames)):
            result[i] = cv2.warpAffine(
                frames[i], transform, (w, h),
                borderMode=cv2.BORDER_REFLECT_101,
            )
        return result


def build_data_loader(data_file, video_dir, seq_length=64, batch_size=22,
                      training=True, augment=True, num_workers=6):
    """Factory function to create a configured DataLoader."""
    dataset = GolfDBDataset(
        data_file=data_file,
        video_dir=video_dir,
        seq_length=seq_length,
        training=training,
        augment=augment,
    )
    return torch.utils.data.DataLoader(
        dataset,
        batch_size=batch_size,
        shuffle=training,
        num_workers=num_workers,
        drop_last=training,
        pin_memory=True,
    )
