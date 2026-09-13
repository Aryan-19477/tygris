"""
Representation Learning Architectures
Faithfully implements ConvNeXt-small (Paper Selected Default) and comparative models.
Reference: Ma et al. (2025) Section 12.
Provides standalone PyTorch architecture fallback if torchvision is not present.
"""

import torch
import torch.nn as nn
from typing import Optional


class StandaloneConvNeXtBlock(nn.Module):
    """Depthwise separable ConvNeXt-style building block."""
    def __init__(self, dim: int):
        super().__init__()
        self.dwconv = nn.Conv2d(dim, dim, kernel_size=7, padding=3, groups=dim)
        self.norm = nn.LayerNorm(dim, eps=1e-6)
        self.pwconv1 = nn.Linear(dim, 4 * dim)
        self.act = nn.GELU()
        self.pwconv2 = nn.Linear(4 * dim, dim)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        res = x
        x = self.dwconv(x)
        x = x.permute(0, 2, 3, 1)  # (N, C, H, W) -> (N, H, W, C)
        x = self.norm(x)
        x = self.pwconv1(x)
        x = self.act(x)
        x = self.pwconv2(x)
        x = x.permute(0, 3, 1, 2)  # (N, H, W, C) -> (N, C, H, W)
        return res + x


class StandaloneConvNeXtSmall(nn.Module):
    """Standalone ConvNeXt-small architecture."""
    def __init__(self, in_chans: int = 3, num_features: int = 768):
        super().__init__()
        self.stem = nn.Sequential(
            nn.Conv2d(in_chans, 96, kernel_size=4, stride=4),
            nn.BatchNorm2d(96)
        )
        self.stage1 = nn.Sequential(*[StandaloneConvNeXtBlock(96) for _ in range(3)])
        self.down1 = nn.Sequential(nn.Conv2d(96, 192, kernel_size=2, stride=2), nn.BatchNorm2d(192))
        self.stage2 = nn.Sequential(*[StandaloneConvNeXtBlock(192) for _ in range(3)])
        self.down2 = nn.Sequential(nn.Conv2d(192, 384, kernel_size=2, stride=2), nn.BatchNorm2d(384))
        self.stage3 = nn.Sequential(*[StandaloneConvNeXtBlock(384) for _ in range(9)])
        self.down3 = nn.Sequential(nn.Conv2d(384, num_features, kernel_size=2, stride=2), nn.BatchNorm2d(num_features))
        self.stage4 = nn.Sequential(*[StandaloneConvNeXtBlock(num_features) for _ in range(3)])
        self.avgpool = nn.AdaptiveAvgPool2d((1, 1))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.stem(x)
        x = self.stage1(x)
        x = self.down1(x)
        x = self.stage2(x)
        x = self.down2(x)
        x = self.stage3(x)
        x = self.down3(x)
        x = self.stage4(x)
        x = self.avgpool(x)
        return torch.flatten(x, 1)


class TigerRepresentationNet(nn.Module):
    """
    [PAPER-SPECIFIED REPRESENTATION NETWORK]
    Uses ConvNeXt-small fine-tuned for tiger identity classification.
    """
    def __init__(
        self,
        num_classes: int = 107,
        backbone_name: str = "ConvNeXt-small",
        pretrained: bool = False,
        freeze_backbone: bool = False
    ):
        super().__init__()
        self.backbone_name = backbone_name
        self.num_classes = num_classes

        # Try loading torchvision backbone, otherwise use standalone implementation
        try:
            import torchvision.models as models
            name_clean = backbone_name.lower().replace("-", "").replace("_", "")
            if "convnext" in name_clean:
                weights = models.ConvNeXt_Small_Weights.DEFAULT if pretrained else None
                self.backbone = models.convnext_small(weights=weights)
                in_features = self.backbone.classifier[2].in_features
                self.backbone.classifier[2] = nn.Identity()
            else:
                weights = models.ResNet50_Weights.DEFAULT if pretrained else None
                self.backbone = models.resnet50(weights=weights)
                in_features = self.backbone.fc.in_features
                self.backbone.fc = nn.Identity()
            self.feature_dim = in_features
        except ImportError:
            self.backbone = StandaloneConvNeXtSmall(num_features=768)
            self.feature_dim = 768

        if freeze_backbone:
            for param in self.backbone.parameters():
                param.requires_grad = False

        self.classifier = nn.Sequential(
            nn.Dropout(p=0.2),
            nn.Linear(self.feature_dim, num_classes)
        )

    def extract_features(self, x: torch.Tensor) -> torch.Tensor:
        return self.backbone(x)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        feat = self.extract_features(x)
        return self.classifier(feat)


def get_representation_model(
    num_classes: int = 107,
    name: str = "ConvNeXt-small",
    pretrained: bool = False,
    freeze_backbone: bool = False
) -> TigerRepresentationNet:
    return TigerRepresentationNet(
        num_classes=num_classes,
        backbone_name=name,
        pretrained=pretrained,
        freeze_backbone=freeze_backbone
    )
