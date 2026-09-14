"""Lightweight foreground isolation applied before embedding.

The paper's biggest single accuracy driver was background removal ahead of
identification (raw-background accuracy 0.43-0.57 vs 0.94-0.95 with the
background stripped, Table 5); it also found that a cheap bounding-box crop
performed almost identically to a full trained segmentation network. Training
a DDRNet-style segmenter is out of scope here, so this applies the same idea
with a classical-CV stand-in: OpenCV's GrabCut, seeded from a center-weighted
rectangle (camera-trap subjects are reliably centered and dominant in frame),
to suppress background pixels before the image reaches the embedding model.
"""
import cv2
import numpy as np

GRABCUT_ITERATIONS = 5
# Fraction of the frame margin excluded from the initial foreground rect,
# i.e. how much border is assumed to be background on all four sides.
BORDER_MARGIN = 0.08


def suppress_background(image: np.ndarray) -> np.ndarray:
    """Zero out likely-background pixels in an HxWx3 uint8 RGB image.

    Falls back to returning the image unchanged if GrabCut fails to converge
    to a non-empty foreground (e.g. near-uniform or degenerate frames), since
    a bad mask is worse than no mask.
    """
    h, w = image.shape[:2]
    mask = np.zeros((h, w), np.uint8)
    bgd_model = np.zeros((1, 65), np.float64)
    fgd_model = np.zeros((1, 65), np.float64)

    mx, my = int(w * BORDER_MARGIN), int(h * BORDER_MARGIN)
    rect = (mx, my, w - 2 * mx, h - 2 * my)

    try:
        cv2.grabCut(image, mask, rect, bgd_model, fgd_model,
                     GRABCUT_ITERATIONS, cv2.GC_INIT_WITH_RECT)
    except cv2.error:
        return image

    foreground = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 1, 0).astype(np.uint8)
    if foreground.sum() < 0.02 * h * w:
        # GrabCut collapsed to almost nothing - keep the original frame
        # rather than feed the model a near-blank image.
        return image

    return image * foreground[:, :, None]
