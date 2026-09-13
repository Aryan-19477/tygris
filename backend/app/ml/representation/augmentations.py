"""
Tiger Re-Identification Augmentation & Preprocessing Pipeline
Faithfully implements Section 11 of Ma et al. (2025).
Provides pure PIL/PyTorch fallback if torchvision is not present in the environment.
"""

import random
from typing import Dict, Any, Tuple, Optional
import numpy as np
from PIL import Image, ImageEnhance
import torch


class RandomLighting:
    """[PAPER-SPECIFIED] Random lighting variation simulation for camera traps."""
    def __init__(self, factor_range: Tuple[float, float] = (0.7, 1.3)):
        self.factor_range = factor_range

    def __call__(self, img: Image.Image) -> Image.Image:
        if random.random() > 0.5:
            factor = random.uniform(*self.factor_range)
            enhancer = ImageEnhance.Brightness(img)
            return enhancer.enhance(factor)
        return img


def get_paper_reid_transforms(
    input_size: Tuple[int, int] = (224, 224),
    is_training: bool = False,
    config_params: Optional[Dict[str, Any]] = None
):
    """
    Constructs the preprocessing and augmentation sequence specified in Section 11.
    Uses torchvision if available; falls back to pure PIL + PyTorch tensor conversion.
    """
    try:
        import torchvision.transforms as T
        crop_scale = (0.8, 1.0)
        jitter_b, jitter_c, jitter_s, jitter_h = 0.2, 0.2, 0.2, 0.1

        if is_training:
            return T.Compose([
                T.RandomResizedCrop(input_size, scale=crop_scale),
                T.RandomHorizontalFlip(p=0.5),
                T.ColorJitter(brightness=jitter_b, contrast=jitter_c, saturation=jitter_s, hue=jitter_h),
                RandomLighting(factor_range=(0.8, 1.2)),
                T.RandomGrayscale(p=0.2),
                T.ToTensor(),
                T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
            ])
        else:
            return T.Compose([
                T.Resize(input_size),
                T.ToTensor(),
                T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
            ])
    except ImportError:
        # Pure PIL + PyTorch transform fallback
        def pil_transform(img: Image.Image) -> torch.Tensor:
            resized = img.convert("RGB").resize(input_size)
            arr = np.array(resized, dtype=np.float32) / 255.0  # H, W, C
            # Normalize with ImageNet mean/std
            mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
            std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
            arr = (arr - mean) / std
            tensor = torch.from_numpy(arr).permute(2, 0, 1).float()  # C, H, W
            return tensor

        return pil_transform
