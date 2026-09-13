"""
Metric Learning Architectures
Faithfully implements ConvNeXt-small (Paper-Selected Default) with 64-D MLP projection head.
Reference: Ma et al. (2025) Section 13.
Architecture: Backbone -> remove classifier -> MLP (Linear -> GELU -> Linear -> 64-D embedding).
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
from typing import Optional

from ..representation.models import StandaloneConvNeXtSmall


class TigerMetricNet(nn.Module):
    """
    [PAPER-SPECIFIED METRIC LEARNING ARCHITECTURE]
    ConvNeXt-small backbone with MLP projection head producing normalized 64-D embeddings.
    """
    def __init__(
        self,
        backbone_name: str = "ConvNeXt-small",
        embedding_dim: int = 64,  # [PAPER-SPECIFIED: 64-D]
        mlp_hidden_dim: int = 256,
        pretrained: bool = False,
        freeze_backbone: bool = False
    ):
        super().__init__()
        self.backbone_name = backbone_name
        self.embedding_dim = embedding_dim

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
        except ImportError:
            self.backbone = StandaloneConvNeXtSmall(num_features=768)
            in_features = 768

        if freeze_backbone:
            for param in self.backbone.parameters():
                param.requires_grad = False

        # [PAPER-SPECIFIED MLP PROJECTION HEAD: Linear -> GELU -> Linear -> 64-D]
        self.projection_head = nn.Sequential(
            nn.Linear(in_features, mlp_hidden_dim),
            nn.GELU(),
            nn.Linear(mlp_hidden_dim, embedding_dim)
        )

    def extract_features(self, x: torch.Tensor) -> torch.Tensor:
        return self.backbone(x)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        feat = self.extract_features(x)
        emb = self.projection_head(feat)
        return emb

    def extract_normalized_embeddings(self, x: torch.Tensor) -> torch.Tensor:
        emb = self.forward(x)
        return F.normalize(emb, p=2, dim=-1)


def get_metric_model(
    name: str = "ConvNeXt-small",
    embedding_dim: int = 64,
    pretrained: bool = False,
    freeze_backbone: bool = False
) -> TigerMetricNet:
    return TigerMetricNet(
        backbone_name=name,
        embedding_dim=embedding_dim,
        pretrained=pretrained,
        freeze_backbone=freeze_backbone
    )
