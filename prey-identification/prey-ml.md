# Pench Wildlife ML Pipeline — Technical Accuracy Improvement Specification

## 0. Purpose

This document specifies the technical ML pipeline for extending the existing Pench tiger-presence model into a high-precision prey-identification system.

Current system:

```text
Camera frame
    ↓
Tiger / No Tiger model
```

Target system:

```text
Camera frame
    ↓
Quality / trigger filtering
    ↓
General wildlife detector
    ↓
Animal bounding boxes
    ↓
Tiger specialist + Pench prey classifier
    ↓
Confidence calibration + open-set rejection
    ↓
Multi-frame/event aggregation
    ↓
Species/count/attribute observations
    ↓
Human verification for uncertain cases
    ↓
Active-learning dataset
    ↓
Retraining + evaluation
```

The goal is **very high precision for automatically accepted predictions**, not an artificial 100% accuracy claim. Difficult images must be rejected or sent to human review rather than being force-classified.

---

# 1. Design Principles

1. Preserve the existing tiger model.
2. Separate **detection** from **species classification**.
3. Use the Pench dataset for domain-specific fine-tuning.
4. Never rely on random image-level train/test splits when adjacent frames belong to the same camera event.
5. Support multiple animals and multiple species per image.
6. Include `Unknown`, `Other`, and `Review` states.
7. Calibrate confidence scores.
8. Evaluate on unseen camera stations.
9. Mine false positives and hard negatives continuously.
10. Treat camera-trap sequences/events as the primary ecological observation unit.
11. Report per-class metrics, not only aggregate accuracy.
12. Prefer precision/recall/coverage trade-offs over forced classification.
13. Keep model version, preprocessing version and threshold version with every prediction.

---

# 2. Current Model Integration

## 2.1 Existing model

The current model answers:

```text
P(Tiger | frame)
```

with a binary decision:

```text
Tiger
No Tiger
```

Do not immediately replace it.

First create a baseline report:

- precision
- recall
- F1
- specificity
- false-positive rate
- false-negative rate
- PR-AUC
- ROC-AUC
- calibration error
- performance by camera station
- performance by day/night
- performance by image quality
- performance by animal scale

## 2.2 Recommended role

The existing tiger model becomes a **specialist verifier** inside the new pipeline.

```text
                 General Detector
                       │
              ┌────────┴─────────┐
              │                  │
        Tiger candidate       Non-tiger
              │                  │
       Existing tiger       Pench prey model
          specialist
              │                  │
              └────────┬─────────┘
                       ↓
                 Final decision
```

If the current tiger model is a classifier rather than a detector, do not use its output directly as the bounding-box detector. Add a dedicated animal detector first.

---

# 3. Target Species Taxonomy

## P0

```text
0  Tiger
1  Chital
2  Sambar
3  Wild Pig
4  Gaur
```

## P1

```text
5  Nilgai
6  Barking Deer
7  Four-horned Antelope / Chousingha
8  Langur
```

## P2

```text
9  Peafowl
10 Jackal
11 Sloth Bear
12 Indian Hare
13 Other mammal
14 Other bird
15 Human
16 Vehicle
17 Unknown
```

The first production release should prioritize P0/P1 species.

---

# 4. Pipeline Overview

```text
RAW IMAGE
   │
   ├── metadata validation
   ├── duplicate detection
   └── camera-event grouping
   │
   ↓
IMAGE QUALITY GATE
   │
   ├── blur
   ├── exposure
   ├── occlusion
   ├── animal scale
   ├── IR/night condition
   └── corrupted image
   │
   ↓
ANIMAL DETECTOR
   │
   ├── animal
   ├── person
   ├── vehicle
   └── background
   │
   ↓
ANIMAL CROPS
   │
   ↓
SPECIES ROUTER
   │
   ├── Tiger specialist
   ├── Large ungulate specialist
   ├── Small/medium mammal specialist
   └── Other/unknown
   │
   ↓
SPECIES CLASSIFICATION
   │
   ↓
OPEN-SET / UNKNOWN DETECTOR
   │
   ↓
CONFIDENCE CALIBRATION
   │
   ├── automatic
   ├── review
   └── unknown
   │
   ↓
EVENT-LEVEL AGGREGATION
   │
   ↓
FINAL WILDLIFE OBSERVATION
```

---

# 5. Stage 0 — Data Ingestion

Every image should be assigned:

```json
{
  "image_id": "...",
  "camera_id": "...",
  "timestamp": "...",
  "file_hash": "...",
  "source": "camera_trap",
  "width": 1920,
  "height": 1080
}
```

If GPS is associated with the camera:

```json
{
  "camera_id": "...",
  "latitude": 0.0,
  "longitude": 0.0
}
```

Never derive location from the image itself unless a separate geolocation system is explicitly intended.

---

# 6. Stage 1 — Duplicate and Sequence Handling

Camera traps frequently produce several images from one trigger.

Example:

```text
10:04:01
10:04:02
10:04:03
10:04:04
10:04:05
```

These should be grouped into one `event_id`.

Recommended event grouping:

```text
same camera
+
temporal gap < configurable threshold
+
same trigger/burst identifier if available
```

Do not use a fixed threshold blindly. Estimate it from camera metadata and deployment configuration.

Example:

```python
if camera_id == previous.camera_id:
    if timestamp - previous.timestamp <= EVENT_GAP:
        same_event = True
```

The event threshold must be tuned using the actual Pench camera configuration.

---

# 7. Stage 2 — Image Quality Gate

## 7.1 Quality features

Calculate:

### Blur

Variance of Laplacian:

\[
B = Var(\nabla^2 I)
\]

Very low `B` indicates blur.

Do not use one universal threshold for all cameras; calibrate thresholds by camera/image conditions.

### Brightness

\[
\mu_I = \frac{1}{N}\sum_{i=1}^{N}I_i
\]

### Contrast

\[
\sigma_I = \sqrt{\frac{1}{N}\sum_{i=1}^{N}(I_i-\mu_I)^2}
\]

### Exposure clipping

Calculate the proportion of pixels near minimum and maximum intensity.

### Compression

Estimate JPEG artifacts / image quality where useful.

### Animal scale

For a bounding box:

\[
r = \frac{A_{bbox}}{A_{image}}
\]

where:

- \(A_{bbox}\) = bounding-box area
- \(A_{image}\) = image area

Very small `r` should reduce confidence or trigger review.

---

# 8. Stage 3 — General Animal Detector

## 8.1 Required output

For every image:

```json
{
  "detections": [
    {
      "bbox": [x1, y1, x2, y2],
      "class": "animal",
      "confidence": 0.97
    }
  ]
}
```

The detector should initially use broad classes:

```text
animal
person
vehicle
```

rather than 15+ species.

This architecture follows established camera-trap workflows such as MegaDetector, which is specifically designed to locate animals, people and vehicles before downstream species classification.

Reference:
- https://github.com/microsoft/MegaDetector
- https://microsoft.github.io/MegaDetector/

## 8.2 Candidate detector models

Benchmark:

- MegaDetector V6
- YOLO-family detector
- RT-DETR or comparable modern detector

Start with a strong pretrained detector before attempting full custom training.

MegaDetector is explicitly intended as a detector, not a species classifier, and its documented workflow pairs animal detection with a downstream classifier.

---

# 9. Stage 4 — Detector Fine-Tuning

If Pench images produce systematic detector failures:

```text
Generic detector
      ↓
Pench animal boxes
      ↓
Fine-tuning
      ↓
Pench detector
```

Annotation requirements:

```text
animal bbox
person bbox
vehicle bbox
```

For animals:

- include visible body;
- do not hallucinate hidden regions;
- maintain consistent box policy;
- annotate overlapping animals separately;
- include difficult/partial animals;
- include small animals.

---

# 10. Stage 5 — Animal Crop Generation

For each animal box:

```text
[x1, y1, x2, y2]
```

add contextual padding:

\[
bbox' = expand(bbox, p)
\]

where `p` is a tuned percentage of width/height.

Do not use excessive padding because background can dominate the species classifier.

Recommended experiment:

```text
padding = 0%
padding = 5%
padding = 10%
padding = 15%
```

Select using unseen-camera validation.

---

# 11. Stage 6 — Species Classification

## 11.1 Recommended strategy

Do not immediately train one giant classifier.

Use:

```text
Animal crop
    ↓
Global Pench classifier
    ↓
Species group router
    ↓
Specialist classifier
```

For example:

```text
GLOBAL
 ├── Tiger
 ├── Large ungulate
 ├── Medium/small mammal
 ├── Bird
 └── Other

LARGE UNGULATE EXPERT
 ├── Chital
 ├── Sambar
 ├── Gaur
 ├── Nilgai
 ├── Barking Deer
 ├── Chousingha
 └── Wild Pig
```

This is justified by recent camera-trap research showing improved performance when visually similar species are routed to specialist expert models.

A 2025 Scientific Reports study used a global model followed by appearance-based specialist models and reported improved performance over the global model alone.

---

# 12. Model Backbone

Benchmark at minimum:

```text
ConvNeXt
EfficientNet
Swin Transformer
ViT-family model
```

If a strong pretrained wildlife model is available, benchmark fine-tuning it against a locally trained baseline.

A 2026 study found that fine-tuning a global wildlife classifier on local camera-trap data can outperform local-from-scratch models, particularly on unseen camera sites.

Therefore test:

```text
Model A:
ImageNet pretrained → Pench

Model B:
Wildlife pretrained → Pench

Model C:
Global wildlife classifier → Pench fine-tuning

Model D:
Global + specialist experts
```

Select based on **OOD/unseen-camera performance**, not random-split accuracy.

---

# 13. Transfer Learning

For a pretrained backbone:

```text
θ0 = pretrained weights
```

Fine-tune:

\[
\theta^* =
\arg\min_\theta
\frac{1}{N}
\sum_{i=1}^{N}
L(f_\theta(x_i),y_i)
+
\lambda ||\theta||_2^2
\]

where:

- \(x_i\) = animal crop
- \(y_i\) = species label
- \(f_\theta\) = classifier
- \(L\) = classification loss
- \(\lambda\) = weight decay coefficient

Recommended training sequence:

### Phase A

Freeze most backbone layers.

Train:

```text
classification head
```

### Phase B

Unfreeze later backbone blocks.

Use lower learning rate.

### Phase C

Optional full fine-tuning.

Use discriminative learning rates:

```text
early layers → very low LR
late layers  → medium LR
classifier   → higher LR
```

---

# 14. Loss Function

For multiclass classification:

\[
L_{CE}
=
-\sum_{c=1}^{C}
y_c \log p_c
\]

where:

- \(C\) = number of classes
- \(y_c\) = true label
- \(p_c\) = predicted probability.

For severe class imbalance, use weighted cross entropy:

\[
L =
-\sum_{c=1}^{C}
w_c y_c \log p_c
\]

Possible class weight:

\[
w_c =
\frac{N}{C N_c}
\]

where \(N_c\) is the number of samples in class \(c\).

However, do not automatically apply aggressive weights. Compare:

- weighted CE
- focal loss
- balanced sampling
- class-aware sampling

on the same held-out test set.

---

# 15. Focal Loss

For difficult/imbalanced classes:

\[
L_{focal}
=
-\alpha_t(1-p_t)^\gamma\log(p_t)
\]

where:

- \(p_t\) = probability of correct class
- \(\gamma\) = focusing parameter
- \(\alpha_t\) = class weight.

Start with:

```text
gamma = 2
```

and tune using validation.

Focal loss should be used only if it improves rare-class performance without causing excessive false negatives.

---

# 16. Sampling Strategy

Do not train from raw frequency alone.

Example:

```text
Chital       50,000
Sambar       20,000
Gaur          8,000
Chousingha      300
```

A naive model can become biased toward Chital.

Compare:

### Strategy A

Natural distribution.

### Strategy B

Weighted sampler.

### Strategy C

Class-balanced sampler.

### Strategy D

Moderate oversampling + augmentation.

Use macro-F1 and per-class recall to select the strategy.

---

# 17. Data Leakage Prevention

This is critical.

Do NOT:

```text
Image 1 → train
Image 2 → validation
Image 3 → test
```

if all three belong to the same camera event.

Instead:

```text
EVENT-LEVEL SPLIT
```

and preferably:

```text
CAMERA-LEVEL SPLIT
```

Example:

```text
TRAIN:
camera 01–30

VALIDATION:
camera 31–35

TEST:
camera 36–40
```

The test cameras must never appear in training.

This measures geographic/camera domain generalization.

---

# 18. Evaluation Sets

Create at least four independent sets.

## Test A — Random/event-held-out

Measures normal performance.

## Test B — Unseen camera

Measures spatial domain generalization.

## Test C — Night/IR

Measures difficult lighting.

## Test D — Hard-case set

Contains:

- occlusion
- blur
- partial animals
- distant animals
- visually similar species
- unusual poses
- vegetation
- multiple animals

The model must be evaluated separately on all four.

---

# 19. Data Augmentation

Use realistic augmentation:

```text
horizontal flip
small rotation
random crop
scale
brightness
contrast
gamma
Gaussian noise
motion blur
defocus blur
JPEG compression
partial occlusion
```

For night/IR:

```text
low-light augmentation
grayscale variants
contrast variation
noise
```

Do not create unrealistic transformations that alter species morphology.

Real Pench examples should remain the primary source of validation.

---

# 20. Hard Negative Mining

After initial training:

```text
Model
 ↓
False predictions
 ↓
Collect
 ↓
Hard-negative dataset
 ↓
Retrain
```

Important confusion pairs:

```text
Chital ↔ Sambar
Chital ↔ Barking Deer
Sambar ↔ Gaur
Gaur ↔ other large mammals
Nilgai ↔ Chital/Sambar
Wild Pig ↔ other dark/occluded animals
Tiger ↔ dark/striped background
```

Hard negatives should be oversampled carefully during later training.

---

# 21. Open-Set Recognition

The classifier must be able to say:

```text
I do not know.
```

A softmax classifier alone is not sufficient because it always produces probabilities summing to 1.

For logits \(z_i\):

\[
p_i =
\frac{e^{z_i/T}}
{\sum_j e^{z_j/T}}
\]

Even an unknown animal receives a highest class.

Therefore implement an abstention layer.

---

# 22. Confidence-Based Rejection

Let:

\[
p_{max} = \max_i p_i
\]

Use:

```text
pmax >= τ_auto
    → automatic prediction

τ_review <= pmax < τ_auto
    → human review

pmax < τ_review
    → unknown
```

Do not hard-code thresholds initially.

Optimize:

\[
\tau^* =
\arg\max_\tau
Precision(\tau)
\]

subject to:

\[
Coverage(\tau) \ge C_{min}
\]

where:

\[
Coverage(\tau)
=
\frac{\# accepted predictions}
{\# total predictions}
\]

This explicitly trades automation coverage for precision.

---

# 23. Confidence Calibration

Raw softmax scores are not necessarily calibrated probabilities.

Use a held-out calibration set.

Temperature scaling:

\[
p_i =
\frac{\exp(z_i/T)}
{\sum_j\exp(z_j/T)}
\]

where `T` is learned on validation/calibration data.

Optimize:

\[
T^* =
\arg\min_T
-\sum_i \log p(y_i|x_i,T)
\]

Then evaluate:

- Expected Calibration Error (ECE)
- Brier score
- reliability diagram
- precision at confidence threshold.

Recent camera-trap research specifically found that sequence-level logit aggregation and temperature scaling can improve calibration.

---

# 24. Event-Level Classification

Suppose one event has \(K\) frames.

For frame \(k\):

\[
z_k = [z_{k1},...,z_{kC}]
\]

Aggregate logits:

\[
\bar{z}
=
\frac{1}{K}
\sum_{k=1}^{K}z_k
\]

Then:

\[
p_c =
\frac{e^{\bar{z}_c/T}}
{\sum_j e^{\bar{z}_j/T}}
\]

Select:

\[
\hat{y}
=
\arg\max_c p_c
\]

This is preferable to simply averaging already-softmaxed probabilities when the validation experiment confirms improved performance.

A 2024/2025 study of camera-trap sequences found that averaging logits across a sequence can improve calibration.

---

# 25. Multi-Frame Confidence

Example:

```text
Frame 1 → Chital 0.81
Frame 2 → Chital 0.94
Frame 3 → Chital 0.91
Frame 4 → Sambar 0.55
Frame 5 → Chital 0.88
```

Event:

```text
Chital
High confidence
```

The final event confidence should incorporate:

```text
mean logit
+
number of supporting frames
+
maximum confidence
+
prediction consistency
+
image quality
```

Do not simply use:

```text
max(frame confidence)
```

because one erroneous frame can create an inflated confidence.

---

# 26. Multi-Animal Handling

For an image:

```text
Detector:
Box 1 → animal
Box 2 → animal
Box 3 → animal
```

Run classification independently:

```text
Box 1 → Chital
Box 2 → Chital
Box 3 → Sambar
```

Final:

```json
{
  "chital": 2,
  "sambar": 1
}
```

Do not classify the full image as one species.

---

# 27. Counting

For each event:

\[
N_s =
\sum_{i=1}^{M}
\mathbf{1}(species_i=s)
\]

where:

- \(M\) = number of detected animals
- \(s\) = species.

However, if the same animal appears across multiple frames, do not sum across frames.

Count within the event using:

- detector boxes;
- tracking;
- temporal consistency;
- duplicate suppression.

---

# 28. Optional Tracking

For video or burst sequences, use object tracking:

```text
Frame 1:
Animal A

Frame 2:
Animal A

Frame 3:
Animal A
```

should remain:

```text
Animal ID = A
```

rather than becoming three animals.

For image-only camera traps, tracking is less reliable; event-level aggregation should remain the primary mechanism.

---

# 29. Image-Level vs Event-Level Metrics

Report both.

### Image level

\[
Precision =
\frac{TP}{TP+FP}
\]

\[
Recall =
\frac{TP}{TP+FN}
\]

\[
F1 =
2\frac{Precision \times Recall}
{Precision+Recall}
\]

### Event level

Calculate the same metrics after aggregating all frames belonging to one event.

For ecological applications, event-level performance is particularly important.

---

# 30. Macro vs Micro Metrics

Micro-F1 can hide poor rare-species performance.

Use:

\[
F1_{macro}
=
\frac{1}{C}
\sum_{c=1}^{C}F1_c
\]

Also report:

- macro precision;
- macro recall;
- per-class F1;
- balanced accuracy.

Never report only:

```text
Overall accuracy = 97%
```

---

# 31. Confusion Matrix-Driven Development

After every major model version:

```text
              Prediction
             C  S  G  P
Actual
C            96 3  1  0
S             4 94 1  1
G             1 2 96  1
P             1 1  1 97
```

Find the highest off-diagonal pairs.

Then:

```text
confusion pair
      ↓
collect examples
      ↓
inspect annotation quality
      ↓
add hard negatives
      ↓
specialist model if necessary
      ↓
retrain
```

This is more useful than repeatedly increasing model size.

---

# 32. Specialist Expert Models

If confusion remains high:

```text
Global model
     ↓
Large ungulates
     ↓
Expert model
```

Example:

```text
Large Ungulate Expert:

Chital
Sambar
Gaur
Nilgai
Barking Deer
Chousingha
Wild Pig
```

Recent research has demonstrated that grouping visually similar species and training specialist experts can improve camera-trap classification performance.

Do not introduce specialist models unless the confusion matrix justifies them.

---

# 33. Ensemble Verification

For the highest-confidence pipeline, optionally combine:

```text
Model A:
Global classifier

Model B:
Specialist classifier

Model C:
Embedding/retrieval model
```

Example:

```text
Global:
Chital 0.91

Specialist:
Chital 0.96

Embedding:
Chital similarity 0.94

→ ACCEPT
```

If predictions disagree:

```text
Global:
Chital

Specialist:
Sambar

Embedding:
Sambar

→ REVIEW
```

Do not ensemble models merely to increase complexity. Measure whether ensemble disagreement actually improves error detection.

---

# 34. Embedding Retrieval

Use the classifier backbone to generate:

\[
e = f(x) \in \mathbb{R}^{d}
\]

Normalize:

\[
\hat e =
\frac{e}{||e||_2}
\]

Similarity:

\[
sim(e_1,e_2)
=
\hat e_1^T\hat e_2
\]

For a new crop:

```text
crop
 ↓
embedding
 ↓
nearest Pench reference images
 ↓
species distribution
```

Use this as:

- verification;
- error analysis;
- active learning;
- unknown detection;
- nearest-example display for human reviewers.

It should not automatically override the classifier without validation.

---

# 35. Background Bias

A major risk:

```text
Model learns:
"this background = Chital"
```

instead of:

```text
Model learns:
"this morphology = Chital"
```

Mitigations:

- detector-based crops;
- contextual padding experiments;
- background randomization;
- augmentation;
- camera-held-out testing;
- saliency inspection;
- crop/background ablation.

Test:

```text
full crop
vs
tight crop
vs
masked background
```

If accuracy collapses when background is removed, investigate shortcut learning.

---

# 36. Occlusion Strategy

Cases:

```text
full body
partial body
head only
rear only
vegetation
multiple animals
```

Label visibility quality:

```text
full
partial
severe
```

Train and evaluate separately.

For severe occlusion:

```text
force classification = NO
```

Prefer:

```text
Unknown / Review
```

unless the model has demonstrated reliable performance on that condition.

---

# 37. Small Object Strategy

For very small animals:

\[
r =
\frac{A_{bbox}}{A_{image}}
\]

Create performance buckets:

```text
r < 0.01
0.01 ≤ r < 0.05
0.05 ≤ r < 0.20
r ≥ 0.20
```

Report performance separately.

Possible improvements:

- higher detector input resolution;
- tiled inference;
- super-resolution only if experimentally useful;
- dedicated small-object detector;
- specialist classifier.

Do not assume super-resolution creates information that was not captured.

---

# 38. Day/Night Specialist

Route:

```text
Image
 ↓
Day/Night classifier
 ↓
RGB model / IR model
```

Alternative:

```text
one model
+
lighting augmentation
```

Benchmark both.

Report:

```text
Day F1
Night F1
Twilight F1
```

Do not combine them into one number.

---

# 39. Tiger Verification

For any predicted tiger:

```text
General detector
        ↓
Tiger candidate
        ↓
Existing tiger model
        ↓
Tiger confidence
```

Possible final decision:

\[
P(Tiger|x)
=
f(P_{det},P_{tiger})
\]

where `f` should be learned or validated rather than manually invented.

At minimum require agreement:

```text
Detector confidence ≥ τd
AND
Tiger specialist confidence ≥ τt
```

for automatic acceptance.

---

# 40. Human-in-the-Loop

Review interface should display:

```text
Image
Bounding box
AI species
Confidence
Alternative classes
Camera
Timestamp
Event frames
Nearest reference examples
```

Reviewer actions:

```text
Confirm
Change species
Unknown
Bad image
Wrong detection
Split event
Merge event
```

All corrections become training metadata.

---

# 41. Active Learning

At each retraining cycle, rank samples by expected information value.

Prioritize:

```text
low confidence
high model disagreement
rare species
high confusion pair
new camera
night/IR
severe occlusion
new environmental conditions
false positives
false negatives
```

Do not spend annotation effort disproportionately on easy Chital images.

---

# 42. Label Quality

Before training:

```text
Raw labels
 ↓
Duplicate check
 ↓
Event consistency
 ↓
Species verification
 ↓
Bounding-box verification
 ↓
Unknown handling
 ↓
Final training dataset
```

Maintain:

```text
label_source
labeler
verification_status
label_version
```

Possible labels:

```text
expert_verified
ranger_verified
AI_suggested
AI_corrected
uncertain
```

---

# 43. Training Recipe

Recommended baseline experiment:

```text
Input:
224–448 px classifier crop

Optimizer:
AdamW

Initial LR:
1e-4 to 3e-4

Weight decay:
1e-4 to 1e-2

Scheduler:
cosine decay

Warmup:
3–10 epochs

Epochs:
50–150 baseline

Early stopping:
validation macro-F1

Loss:
Cross entropy

Class imbalance:
balanced sampler / weighted loss experiment

Mixed precision:
FP16/BF16

Gradient clipping:
optional

EMA:
benchmark

Augmentation:
camera-trap specific
```

These are starting points, not immutable specifications. Hyperparameters must be selected through controlled experiments.

---

# 44. Detector Training Recipe

Baseline:

```text
Input:
high-resolution camera image

Optimizer:
SGD or AdamW

Augmentation:
Mosaic / scale / crop / flip
+
camera-trap specific augmentation

Loss:
classification
+
box regression
+
objectness / equivalent detector losses

Metrics:
mAP@0.5
mAP@0.5:0.95
precision
recall
```

Detector thresholds must be selected based on downstream species-classification performance, not detector mAP alone.

---

# 45. Important Optimization Objective

The detector's optimal threshold is not necessarily the threshold that maximizes detector F1.

The real pipeline objective is:

\[
Performance_{system}
=
f(
Detection,
Classification,
Abstention,
EventAggregation
)
\]

Example:

A detector that produces slightly more false boxes may still be useful if the classifier reliably rejects them.

Therefore optimize the complete pipeline.

---

# 46. Calibration and Threshold Selection

Create validation predictions:

```text
confidence
true/false
species
camera
condition
```

Then calculate precision at thresholds:

```text
τ = 0.50
τ = 0.60
τ = 0.70
τ = 0.80
τ = 0.90
τ = 0.95
```

Example output:

```text
Threshold    Precision    Recall    Coverage
0.50         91%          96%       99%
0.70         95%          91%       92%
0.80         97%          87%       83%
0.90         99%          78%       68%
0.95         99.5%        63%       51%
```

The actual values must come from Pench validation data.

This is the correct way to pursue near-100% **precision** without falsely claiming near-100% overall accuracy.

---

# 47. Reliability Requirements

For every automatic prediction store:

```json
{
  "species": "chital",
  "raw_confidence": 0.97,
  "calibrated_confidence": 0.94,
  "threshold": 0.90,
  "decision": "automatic"
}
```

This allows later auditing.

---

# 48. Model Registry

Every production model must have:

```text
model_id
version
training_dataset_version
taxonomy_version
preprocessing_version
threshold_version
calibration_version
training_date
evaluation_report
```

Example:

```text
detector: pench-det-v1.2
classifier: pench-species-v2.1
calibrator: temp-v1.0
thresholds: threshold-v1.3
taxonomy: pench-taxonomy-v1
```

---

# 49. Error Taxonomy

Every model error should be categorized:

```text
false_positive
false_negative
wrong_species
missed_detection
duplicate_detection
bad_bbox
unknown_should_have_been_known
known_should_have_been_unknown
event_split_error
event_merge_error
counting_error
```

This allows targeted improvement.

---

# 50. Production Monitoring

Track:

```text
prediction distribution
unknown rate
review rate
species distribution
confidence distribution
camera-specific error rate
night/day error rate
new-camera error rate
drift
```

Example anomaly:

```text
Chital predictions:
historical = 42%
current = 71%
```

This could indicate:

- ecological change;
- camera placement change;
- model drift;
- annotation problem;
- detector issue.

The system should flag the shift, not automatically declare ecological change.

---

# 51. Data Drift

Monitor input distributions:

\[
D_{KL}(P_{current} || P_{reference})
\]

or use robust alternatives such as PSI / Wasserstein distance.

Monitor:

- brightness;
- image size;
- animal size;
- confidence;
- species distribution;
- camera distribution;
- night/day ratio.

If drift is detected:

```text
production
 ↓
sample new data
 ↓
human review
 ↓
evaluate model
 ↓
retrain if required
```

---

# 52. Accuracy Improvement Loop

```text
                 MODEL
                   ↓
              Predictions
                   ↓
          ┌────────┴────────┐
          ↓                 ↓
       Correct           Incorrect
          │                 │
          │           Error taxonomy
          │                 ↓
          │           Hard negatives
          │                 ↓
          └────────→ Dataset update
                            ↓
                         Retrain
                            ↓
                   Unseen-camera test
                            ↓
                       Model registry
                            ↓
                       Deployment
```

---

# 53. Research-Guided Architecture

The proposed architecture is intentionally aligned with established camera-trap research:

## MegaDetector

MegaDetector is designed to detect animals, people and vehicles, then pass animal crops to a downstream species classifier.

Reference:
https://github.com/microsoft/MegaDetector

## Transfer Learning

Willi et al. demonstrated the usefulness of transfer learning for automated camera-trap species identification and confidence thresholding.

Reference:
https://doi.org/10.1111/2041-210X.13099

## Specialist Models

Recent research has shown that a global wildlife model followed by specialist expert models for visually similar species can improve performance.

Reference:
https://doi.org/10.1038/s41598-025-90249-z

## Confidence Calibration

Recent camera-trap research found that sequence-level logit aggregation and temperature scaling can improve calibration.

Reference:
https://doi.org/10.1002/rse2.412

## Global-to-Local Fine-Tuning

A 2026 study reported that fine-tuning a global wildlife classifier on local camera-trap data can outperform local models, including on unseen camera locations.

Reference:
https://doi.org/10.1016/j.scitotenv.2026.181926

---

# 54. Recommended Experimental Matrix

Do not select the final architecture by intuition.

Run:

```text
Experiment 1
Global classifier

Experiment 2
Global classifier + transfer learning

Experiment 3
Global classifier + class balancing

Experiment 4
Global classifier + detector crops

Experiment 5
Global + specialist models

Experiment 6
Global + specialist + calibration

Experiment 7
Global + specialist + event aggregation

Experiment 8
Global + specialist + event aggregation + abstention

Experiment 9
Global + specialist + embedding verification

Experiment 10
Full ensemble
```

Every experiment must use exactly the same held-out test cameras.

---

# 55. Recommended Selection Criterion

Do not select:

```text
highest random-split accuracy
```

Select the model maximizing:

\[
Score =
\alpha F1_{macro}
+
\beta Precision_{high-confidence}
+
\gamma Recall_{P0}
-
\delta ReviewRate
\]

with weights defined by operational requirements.

For conservation use, a reasonable priority is:

```text
1. High-confidence precision
2. P0 species recall
3. Macro-F1
4. Unseen-camera performance
5. Review workload
6. Latency
```

The exact weights should be agreed before final model selection.

---

# 56. Final Recommended Production Architecture

```text
                         CAMERA TRAP
                              │
                              ▼
                     Metadata / Hashing
                              │
                              ▼
                     Event Identification
                              │
                              ▼
                       Quality Gate
                              │
                              ▼
                     GENERAL DETECTOR
                              │
                 ┌────────────┼────────────┐
                 ▼            ▼            ▼
              Animal        Person       Vehicle
                 │
                 ▼
             Animal Crop
                 │
                 ▼
          GLOBAL CLASSIFIER
                 │
       ┌─────────┼──────────┐
       ▼         ▼          ▼
     Tiger     Ungulate    Other
       │         │
       ▼         ▼
 Existing     Ungulate
 Tiger        Expert
 Model        Model
                 │
                 ▼
          Species Prediction
                 │
                 ▼
       ┌──────────────────────┐
       │ Calibration / OOD    │
       │ / Abstention Layer   │
       └──────────┬───────────┘
                  │
        ┌─────────┼─────────┐
        ▼         ▼         ▼
     Accept     Review    Unknown
        │         │
        │      Human Label
        │         │
        └────┬────┘
             ▼
       EVENT AGGREGATION
             │
             ▼
      Count / Attributes /
        Behaviour
             │
             ▼
      FINAL OBSERVATION
             │
             ▼
       ACTIVE LEARNING
             │
             ▼
        RETRAINING LOOP
```

---

# 57. Definition of a High-Quality Prediction

A prediction should be considered production-grade only when:

```text
Detector confidence       ≥ validated threshold
Species confidence        ≥ calibrated threshold
Image quality             acceptable
Species not OOD            true
Model agreement            acceptable
Event consistency          acceptable
Camera condition           within validated distribution
```

Otherwise:

```text
REVIEW / UNKNOWN
```

---

# 58. Critical Edge Cases

The pipeline must explicitly handle:

- empty frame;
- wind-triggered frame;
- moving vegetation;
- rain;
- fog;
- snow-like IR artifacts if applicable;
- severe darkness;
- overexposure;
- motion blur;
- partial animal;
- animal at frame boundary;
- tiny animal;
- multiple animals;
- overlapping animals;
- multiple species;
- animal behind vegetation;
- animal facing away;
- unusual posture;
- carcass;
- human;
- vehicle;
- domestic animal;
- unknown species;
- corrupted image;
- duplicate image;
- burst sequence;
- camera clock drift;
- camera replacement;
- camera relocation;
- new camera domain;
- seasonal appearance change.

Every edge case should have an explicit expected behavior.

---

# 59. Expected Output Contract

Final prediction:

```json
{
  "image_id": "img_123",
  "event_id": "event_456",
  "camera_id": "cam_07",

  "detections": [
    {
      "bbox": [120, 80, 740, 680],
      "species": "chital",

      "detector_confidence": 0.98,
      "raw_species_confidence": 0.96,
      "calibrated_confidence": 0.94,

      "decision": "automatic",

      "quality_score": 0.91,

      "model": {
        "detector": "pench-det-v1.2",
        "classifier": "pench-species-v2.1",
        "calibrator": "temperature-v1.0"
      }
    }
  ]
}
```

Possible decisions:

```text
automatic
review
unknown
rejected
```

---

# 60. Final Technical Objective

The pipeline should optimize for:

\[
\boxed{
\text{High Precision}
+
\text{High Recall}
+
\text{Calibrated Uncertainty}
+
\text{Generalization to Unseen Cameras}
}
\]

rather than:

\[
\boxed{\text{Artificially High Accuracy on a Random Split}}
\]

The most important technical upgrades to the current tiger-only system are:

```text
1. General animal detector
2. Detector-based animal crops
3. Pench-specific transfer learning
4. Global + specialist species classifiers
5. Hard-negative mining
6. Event-level aggregation
7. Confidence calibration
8. Unknown/OOD rejection
9. Camera-level holdout evaluation
10. Human-in-the-loop correction
11. Active learning
12. Continuous error analysis
```

The system should ultimately behave as:

```text
Easy image
→ automatic high-confidence identification

Ambiguous image
→ human review

Unknown species
→ Unknown

Multiple frames
→ one event

Multiple animals
→ independent detections

New camera/environment
→ measured generalization

Model error
→ hard negative → retraining
```

This is the practical route toward very high reliability in Pench rather than attempting to force a neural network to produce a species label for every image.
