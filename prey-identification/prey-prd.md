# PRD — Pench Wildlife Prey Identification & Tiger–Prey Intelligence ML Pipeline

## 1. Product Overview

### Objective

Extend the existing Pench wildlife ML system, which currently detects whether a camera-trap frame contains a tiger, into a robust **multi-species wildlife detection and ecological intelligence pipeline**.

The system must:

1. Preserve and reuse the existing tiger model.
2. Detect animals other than tigers.
3. Identify priority Pench prey species.
4. Count animals within frames/events.
5. Handle multiple animals, occlusion, poor lighting, IR imagery and empty frames.
6. Quantify prediction confidence and explicitly support `Unknown`.
7. Aggregate consecutive camera-trap frames into wildlife events.
8. Enable ranger verification of uncertain predictions.
9. Build structured prey observations for downstream analytics.
10. Correlate prey distribution/activity with tiger presence, movement, habitat and time.
11. Continuously improve through human feedback and active learning.

### Accuracy Philosophy

The system must **not force predictions** to achieve an artificial accuracy percentage.

Target:

> Maximize precision on automatically accepted predictions while maintaining useful recall and routing uncertain cases to `Unknown / Human Review`.

All reported model performance must include per-class precision, recall, F1, confusion matrices and performance by environmental condition.

---

# 2. Current System

Current capability:

```text
Camera-trap frame
       ↓
Existing Tiger Model
       ↓
Tiger / No Tiger
```

Current limitation:

- Cannot detect non-tiger animals.
- Cannot localize animals.
- Cannot identify prey species.
- Cannot count animals.
- Cannot distinguish multiple species in one frame.
- No structured prey observations.
- No event-level aggregation.
- No tiger–prey correlation.

The existing tiger model must be preserved as a **specialist tiger model** and benchmarked before modification.

---

# 3. Proposed System

```text
Camera Frame
     ↓
Image Quality Gate
     ↓
General Animal Detector
     ↓
Animal Bounding Boxes
     ↓
Species Classification
     ↓
Tiger Specialist / Prey Specialist / Other
     ↓
Confidence & Unknown Handling
     ↓
Multi-frame Event Aggregation
     ↓
Count + Behaviour + Attributes
     ↓
Structured Wildlife Observation
     ↓
Spatial + Temporal + Habitat Analysis
     ↓
Tiger–Prey Intelligence
```

---

# 4. Species Taxonomy

## P0 — Highest Priority

| Species | Priority | Reason |
|---|---:|---|
| Tiger | P0 | Existing model; primary predator |
| Chital / Spotted Deer | P0 | Major tiger prey |
| Sambar | P0 | Major high-biomass tiger prey |
| Wild Pig / Wild Boar | P0 | Important alternative prey |
| Gaur | P0 | Major large ungulate |

## P1

| Species | Priority |
|---|---:|
| Nilgai | P1 |
| Barking Deer | P1 |
| Four-horned Antelope / Chousingha | P1 |
| Langur | P1 |

## P2

| Species | Priority |
|---|---:|
| Peafowl | P2 |
| Jackal | P2 |
| Sloth Bear | P2 |
| Indian Hare | P2 |
| Other mammals | P2 |
| Other birds | P2 |

The initial production classifier should prioritize approximately 8–10 key species instead of attempting to identify every possible species immediately.

---

# 5. Functional Requirements

## FR-01 — General Animal Detection

The system must detect all relevant animals in an image.

Input:

```text
Camera-trap image
```

Output:

```json
{
  "detections": [
    {
      "bbox": [x1, y1, x2, y2],
      "category": "animal",
      "confidence": 0.97
    }
  ]
}
```

The detector should initially distinguish:

- Animal
- Person
- Vehicle
- Unknown/background

Species identification should be handled downstream.

---

# 6. FR-02 — Species Classification

Every animal crop must be passed to a species classifier.

Example:

```text
Animal crop
     ↓
Species classifier
     ↓
Chital — 0.94
```

The classifier must support:

- Tiger
- Chital
- Sambar
- Wild Pig
- Gaur
- Nilgai
- Barking Deer
- Chousingha
- Langur
- Other
- Unknown

The architecture should support adding species without redesigning the entire pipeline.

---

# 7. FR-03 — Existing Tiger Model Integration

The existing tiger model must be retained.

Recommended architecture:

```text
                 General Detector
                       ↓
              ┌────────┴────────┐
              ↓                 ↓
         Tiger candidate      Non-tiger
              ↓                 ↓
      Existing Tiger Model   Prey Classifier
              ↓                 ↓
       Tiger verification    Species result
```

The existing tiger model should act as a **specialist verifier**, rather than being discarded.

Before integration:

- benchmark current model;
- record precision/recall/F1;
- identify false positives;
- identify false negatives;
- evaluate confidence calibration;
- evaluate day/night performance;
- evaluate performance by camera station.

---

# 8. FR-04 — Pench-Specific Fine-Tuning

Training strategy:

```text
Generic pretrained vision model
            ↓
Generic wildlife/camera-trap data
            ↓
Pench dataset
            ↓
Pench-specific fine-tuning
            ↓
Pench validation
            ↓
Unseen-camera test
            ↓
Production
```

Transfer learning should be preferred over training from scratch unless experiments demonstrate otherwise.

The Pench dataset must be treated as the primary domain-specific source.

---

# 9. FR-05 — Unknown / Abstention

The model must never be required to classify every image.

Possible result:

```text
Unknown
```

when:

- confidence is low;
- image quality is poor;
- animal is heavily occluded;
- animal is too small;
- species is not represented in taxonomy;
- classifier and embedding model disagree;
- multiple models disagree;
- image contains an unfamiliar visual condition.

Example:

```json
{
  "prediction": "unknown",
  "confidence": 0.51,
  "reason": "low_confidence"
}
```

Thresholds must be learned using validation/calibration data.

---

# 10. FR-06 — Image Quality Assessment

Before species classification, assess:

- blur;
- motion blur;
- darkness;
- overexposure;
- IR quality;
- compression;
- occlusion;
- animal size;
- vegetation obstruction;
- rain/fog;
- extreme crop;
- partial animal;
- camera obstruction.

Output:

```json
{
  "quality_score": 0.32,
  "usable": false,
  "reason": "severe_occlusion"
}
```

Low-quality images should be routed to `Unknown / Review`.

---

# 11. FR-07 — Multiple Animal Detection

The system must support multiple animals in the same frame.

Example:

```text
Frame
 ├── Chital
 ├── Chital
 └── Sambar
```

Output:

```json
{
  "animals": [
    {"species": "chital"},
    {"species": "chital"},
    {"species": "sambar"}
  ]
}
```

Aggregated result:

```text
Chital: 2
Sambar: 1
```

---

# 12. FR-08 — Animal Counting

The system should estimate:

- number of animals;
- number by species;
- group size.

Example:

```text
Chital: 14
Sambar: 2
```

Counting must be performed from bounding boxes rather than species-classification labels alone.

---

# 13. FR-09 — Sex and Age Classification

Where image quality permits:

```text
Adult Male
Adult Female
Juvenile
Unknown
```

Initially prioritize:

- Chital
- Sambar
- Gaur
- Nilgai

Predictions must be allowed to return `Unknown`.

---

# 14. FR-10 — Behaviour Recognition

Initial behaviour taxonomy:

- Walking
- Running
- Feeding
- Resting
- Drinking
- Grazing
- Alert
- Fleeing
- Crossing
- Social/grouping
- Unknown

Behaviour confidence must be independently stored.

Example:

```json
{
  "species": "chital",
  "behaviour": "alert",
  "behaviour_confidence": 0.78
}
```

The system must never equate `Alert` with confirmed tiger presence.

---

# 15. FR-11 — Day/Night Processing

The pipeline must support:

- daylight RGB;
- low light;
- twilight;
- infrared/night images;
- flash images.

Evaluation must separately report:

```text
Day performance
Night/IR performance
Twilight performance
```

If a single model performs poorly on IR data, specialist day/night models may be introduced.

---

# 16. FR-12 — Event-Level Aggregation

Camera traps frequently generate sequences.

Example:

```text
12:01:01 → Unknown
12:01:02 → Chital
12:01:03 → Chital
12:01:04 → Chital
12:01:05 → Unknown
```

The system should create:

```text
Event
Species = Chital
Supporting frames = 3
Event confidence = High
```

The system must not treat every consecutive frame as an independent animal observation.

---

# 17. FR-13 — Temporal Consensus

For frames belonging to the same event:

```text
P(species | frame 1)
P(species | frame 2)
P(species | frame 3)
...
```

should be aggregated into:

```text
P(species | event)
```

Possible methods:

- weighted probability averaging;
- confidence-weighted voting;
- temporal consistency;
- majority voting;
- ensemble agreement.

The selected approach must be experimentally evaluated.

---

# 18. FR-14 — Embedding-Based Verification

The classifier should produce an embedding representation.

```text
Animal crop
     ↓
Vision encoder
     ↓
Embedding
```

Use embedding similarity as a secondary verification mechanism.

Example:

```text
Classifier → Chital 94%
Embedding → Chital similarity 91%

→ High confidence
```

If:

```text
Classifier → Chital 93%
Embedding → Sambar similarity 89%

→ Human review
```

This should be evaluated rather than assumed to improve performance.

---

# 19. FR-15 — Confidence Calibration

Raw neural-network confidence must not automatically be treated as probability.

Evaluate calibration using:

- Expected Calibration Error;
- reliability diagrams;
- confidence histograms;
- precision at threshold;
- recall at threshold;
- coverage vs accuracy.

Possible calibrated output:

```text
≥ threshold A → Automatic
threshold B–A → Human review
< threshold B → Unknown
```

Thresholds must be determined experimentally.

---

# 20. FR-16 — Human Verification

Low-confidence predictions must enter a review queue.

Example:

```text
AI Prediction
Chital — 71%

[Confirm Chital]
[Change Species]
[Unknown]
```

Human correction must be stored as a training label.

---

# 21. FR-17 — Active Learning

The system should prioritize difficult images for annotation.

Priority:

1. low confidence;
2. model disagreement;
3. visually confusing species;
4. rare species;
5. new camera station;
6. new environmental conditions;
7. night/IR images;
8. unusual poses;
9. heavy occlusion;
10. false-positive clusters.

Corrected samples should enter a curated training dataset.

---

# 22. FR-18 — Hard Negative Mining

Maintain explicit hard-negative datasets.

Examples:

```text
Tiger false positives:
- logs
- rocks
- shadows
- vegetation
- deer
- people
- vehicles

Chital false positives:
- Sambar
- Barking Deer
- Nilgai

Sambar false positives:
- Chital
- Gaur
- Barking Deer
```

False positives from real Pench deployment should automatically become candidates for hard-negative training.

---

# 23. FR-19 — Dataset Splitting

Never randomly split adjacent camera-trap frames.

Training/validation/test splitting should occur at the **event level** and preferably the **camera-station level**.

Preferred:

```text
Training:
Camera Stations A–X

Validation:
Camera Stations Y–Z

Test:
Completely unseen stations
```

This prevents temporal leakage and gives a realistic estimate of deployment performance.

---

# 24. FR-20 — Data Augmentation

Training augmentation should include realistic camera-trap conditions:

- brightness;
- contrast;
- gamma;
- noise;
- blur;
- compression;
- small rotations;
- crop/scale;
- partial occlusion;
- low-light simulation;
- IR-like conditions.

Synthetic augmentation must not replace real Pench examples.

---

# 25. ML Model Architecture

Recommended baseline:

```text
                    IMAGE
                      ↓
             Quality Assessment
                      ↓
               Animal Detector
                      ↓
              ┌───────┴───────┐
              ↓               ↓
           Animal            Non-animal
              ↓
       Species Classifier
              ↓
       ┌──────┼─────────┐
       ↓      ↓         ↓
     Tiger   Prey     Other
       ↓      ↓
 Existing   Prey
 Tiger      Specialist
 Model       Models
       └──────┬─────────┘
              ↓
       Confidence Layer
              ↓
       Unknown / Review
              ↓
        Event Aggregation
              ↓
       Structured Observation
```

Candidate architectures should be experimentally benchmarked rather than hard-coded:

### Detector

Benchmark:

- YOLO-family detector;
- RT-DETR;
- other suitable modern detector.

### Classifier

Benchmark:

- ConvNeXt;
- EfficientNet;
- Swin Transformer;
- ViT-family model.

Final architecture should be selected using Pench-specific validation and deployment constraints.

---

# 26. Specialist Model Architecture

A single global classifier is not mandatory.

Recommended:

```text
                  Animal Crop
                       ↓
             ┌─────────┴─────────┐
             ↓                   ↓
        Tiger Specialist      Prey Specialist
                                 ↓
               ┌─────────────────┼──────────────┐
               ↓                 ↓              ↓
             Deer             Large           Other
            group             ungulates       prey
               ↓
        Species classification
```

Specialist models should be introduced where confusion matrices demonstrate meaningful benefit.

---

# 27. Edge Cases

The system must explicitly handle:

### Empty frame

```text
No animal detected
```

### Animal partially outside frame

```text
Unknown / Partial detection
```

### Multiple animals

```text
Independent bounding boxes
```

### Multiple species

```text
Independent species predictions
```

### Animal behind vegetation

```text
Low confidence / Review
```

### Animal extremely far away

```text
Unknown or low-confidence
```

### Motion blur

```text
Quality degradation → Review
```

### Night IR

```text
IR pipeline / appropriate specialist
```

### Animal silhouette

```text
Do not force species prediction
```

### Unknown species

```text
Other / Unknown
```

### Human

```text
Human event
```

### Vehicle

```text
Vehicle event
```

### Domestic animal

```text
Other / Non-target
```

### Camera malfunction

```text
Camera health event
```

### Duplicate frames

```text
Deduplicate / event grouping
```

### Same animal appearing repeatedly

```text
Event-level aggregation
```

### Species visually confused

```text
Secondary verification / Human review
```

---

# 28. Evaluation Framework

Do not use overall accuracy as the primary metric.

Required metrics:

### Classification

- Precision
- Recall
- F1
- Macro F1
- Balanced accuracy
- Confusion matrix
- Per-class accuracy

### Detection

- mAP
- precision
- recall
- localization accuracy

### Confidence

- ECE
- precision at confidence threshold
- coverage

### Operational

- automatic acceptance rate;
- human-review rate;
- false-positive rate;
- false-negative rate;
- inference latency;
- memory usage;
- CPU/GPU utilization.

---

# 29. Target Performance

The product should define performance targets as:

### High-confidence automatic predictions

> Very high precision, with target ≥99% on the validated high-confidence subset where operationally achievable.

### Overall system

Optimize the trade-off between:

```text
Precision
Recall
Coverage
Review workload
```

Do not claim 99–100% overall accuracy unless demonstrated on a genuinely held-out Pench test set.

Performance must additionally be reported separately for:

- day;
- night;
- twilight;
- species;
- camera station;
- image quality;
- occlusion;
- distance.

---

# 30. Tiger–Prey Intelligence Layer

Once structured observations exist, build a separate analytics layer.

Inputs:

```text
Tiger observations
Prey observations
Camera stations
GPS
Timestamp
Habitat
Water sources
Patrolling data
Human activity
Environmental variables
```

---

# 31. Insight 1 — Prey Availability

Estimate relative prey activity by:

- camera station;
- species;
- time;
- season;
- habitat.

Example:

```text
Station 17

Chital     HIGH
Sambar     HIGH
Wild Pig   MEDIUM
Gaur       LOW
```

Use terms such as **relative abundance/activity index**, not absolute population size unless appropriate statistical estimation is implemented.

---

# 32. Insight 2 — Tiger–Prey Spatial Association

Compare:

```text
Tiger detections
       +
Prey detections
       +
Spatial distance
```

Potential output:

```text
High tiger–prey association
Station cluster 12–19
```

The system must distinguish correlation/association from causation.

---

# 33. Insight 3 — Tiger–Prey Temporal Association

Compare:

```text
Tiger activity
vs
Prey activity
```

Example:

```text
Tiger:
18:00–01:00

Chital:
17:00–22:00
```

Calculate temporal overlap.

Potential outputs:

- activity overlap;
- temporal separation;
- activity shifts;
- species-specific patterns.

---

# 34. Insight 4 — Prey Behaviour Before Tiger Detection

Analyze sequences such as:

```text
Normal prey activity
        ↓
Elevated alert behaviour
        ↓
Running/fleeing
        ↓
Tiger detected
```

The system may calculate whether prey behavioural changes are statistically associated with subsequent tiger detections.

It must **not automatically infer predation**.

---

# 35. Insight 5 — Tiger-associated Species

Calculate species associations around tiger detections.

Example:

```text
Tiger-associated observations

Chital       HIGH
Sambar       HIGH
Wild Pig     MEDIUM
Gaur         MEDIUM
Nilgai       LOW
```

This can support ecological analysis of prey associations.

---

# 36. Insight 6 — Habitat Association

Correlate observations with:

- forest type;
- water;
- grassland;
- dense forest;
- open forest;
- elevation;
- slope;
- roads;
- human settlements;
- fire history.

Outputs:

```text
Tiger probability
Prey activity
Tiger–prey overlap
```

by habitat type.

---

# 37. Insight 7 — Waterhole Intelligence

For each water source:

```text
Species activity
Peak activity time
Tiger detections
Seasonal variation
```

Example:

```text
Waterhole A

Chital       HIGH
Sambar       MEDIUM
Tiger        HIGH

Peak prey activity:
17:00–21:00
```

---

# 38. Insight 8 — Ecological Anomaly Detection

Flag:

```text
Unexpected prey decline
Unexpected prey concentration
Sudden behavioural change
Unusual species absence
Sudden tiger/prey activity change
```

Example:

```text
WARNING

Chital activity at Station Cluster A
has declined significantly relative to
the recent baseline.
```

The system should show the evidence supporting the anomaly.

---

# 39. Insight 9 — Tiger Movement and Prey Movement

Compare:

```text
Prey movement
      ↓
Time
      ↓
Tiger movement
```

Potential output:

> Temporal-spatial sequence detected between prey movement and subsequent tiger movement.

This is an analytical association and must not be represented as confirmed hunting behaviour.

---

# 40. Database Schema

Minimum observation object:

```json
{
  "observation_id": "...",
  "event_id": "...",
  "camera_id": "...",
  "timestamp": "...",
  "location": {
    "latitude": 0,
    "longitude": 0
  },
  "species": "chital",
  "species_confidence": 0.94,
  "bbox": [0, 0, 0, 0],
  "count": 1,
  "sex": "female",
  "age_class": "adult",
  "behaviour": "feeding",
  "behaviour_confidence": 0.81,
  "image_quality": 0.89,
  "verification_status": "ai_verified"
}
```

Possible verification statuses:

```text
ai_verified
human_verified
human_corrected
unknown
rejected
```

---

# 41. Human-in-the-Loop Workflow

```text
Camera Image
     ↓
AI Prediction
     ↓
Confidence Check
     ↓
 ┌───┴──────────────┐
 ↓                  ↓
High confidence    Low confidence
 ↓                  ↓
Automatic           Review Queue
                      ↓
                Ranger Verification
                      ↓
                Corrected Label
                      ↓
                Training Dataset
```

---

# 42. Model Versioning

Every prediction must retain:

```text
model_version
detector_version
classifier_version
confidence_threshold
timestamp
```

Example:

```text
detector: v2.1
species_model: v1.4
tiger_model: v3.2
```

This allows historical predictions to be traced back to the model that produced them.

---

# 43. Continuous Improvement

Production loop:

```text
Deployment
    ↓
Predictions
    ↓
Errors / Low confidence
    ↓
Human verification
    ↓
Hard-negative collection
    ↓
Dataset update
    ↓
Retraining
    ↓
Unseen-camera evaluation
    ↓
Model approval
    ↓
Deployment
```

No model should automatically replace a production model without evaluation.

---

# 44. Research References

The ML implementation should use established camera-trap research as methodological references.

### Transfer Learning

Willi et al. demonstrated the effectiveness of transfer learning for automated species classification in camera-trap imagery.

https://doi.org/10.1111/2041-210X.13099

### Large-Scale Camera-Trap Recognition

Norouzzadeh et al. demonstrated large-scale automated animal identification, counting and behavioural description using camera-trap imagery.

https://doi.org/10.1111/2041-210X.13504

### Snapshot Serengeti

Swanson et al. provide a major benchmark for large-scale citizen-science/camera-trap species identification.

https://doi.org/10.1038/sdata.2015.26

### Camera-Trap Classification Challenges

Gomez Villa et al. studied automated animal recognition and the effects of class imbalance, incomplete animals and difficult camera-trap imagery.

https://doi.org/10.1016/j.ecoinf.2016.11.005

### MegaDetector

Microsoft's MegaDetector demonstrates the practical animal/person/vehicle detection → downstream species classification architecture.

https://github.com/microsoft/CameraTraps

### Specialist Wildlife Models

Recent research indicates that specialist models can improve recognition among groups of visually similar wildlife species.

https://pmc.ncbi.nlm.nih.gov/articles/PMC12064792/

---

# 45. Development Phases

## Phase 1 — Audit Existing Tiger Model

Deliverables:

- current model benchmark;
- dataset audit;
- confusion/error analysis;
- confidence analysis;
- day/night analysis;
- false-positive dataset.

---

## Phase 2 — General Animal Detection

Deliverables:

- animal detector;
- bounding boxes;
- person/vehicle filtering;
- empty-frame handling.

Success criterion:

> Reliable localization of wildlife in unseen Pench camera stations.

---

## Phase 3 — Priority Prey Classifier

Implement:

```text
Tiger
Chital
Sambar
Wild Pig
Gaur
Nilgai
Barking Deer
Chousingha
Langur
Other
Unknown
```

---

## Phase 4 — Event-Level Intelligence

Implement:

- sequence grouping;
- multi-frame consensus;
- counting;
- confidence aggregation;
- duplicate suppression.

---

## Phase 5 — Human Verification

Implement:

- review queue;
- correction workflow;
- hard-negative collection;
- active learning dataset.

---

## Phase 6 — Behaviour and Attributes

Implement:

- sex;
- age;
- behaviour;
- movement direction.

These should only be added after species detection reaches production reliability.

---

## Phase 7 — Tiger–Prey Intelligence

Implement:

- spatial correlation;
- temporal correlation;
- prey availability;
- habitat association;
- waterhole analysis;
- behavioural response;
- anomaly detection.

---

# 46. Non-Goals

The first version should NOT attempt:

- exact population census from raw detections;
- guaranteed individual identification of prey;
- automatic predation claims;
- automatic kill detection;
- unrestricted species recognition;
- 100% accuracy claims;
- replacing ranger verification;
- ecological causal inference from correlation alone.

---

# 47. Key Product Principle

The system should transform:

```text
IMAGE
```

into:

```text
STRUCTURED ECOLOGICAL OBSERVATION
```

and eventually:

```text
OBSERVATIONS
       ↓
PATTERNS
       ↓
TIGER–PREY RELATIONSHIPS
       ↓
ECOLOGICAL INTELLIGENCE
```

The value of the system is therefore not merely:

> **“AI identifies a chital.”**

It is:

> **“The system continuously converts Pench camera-trap imagery into reliable, uncertainty-aware wildlife observations that can be correlated with tiger activity, prey availability, habitat, movement and environmental conditions.”**

---

# 48. Definition of Done

The pipeline is production-ready when:

- [ ] Existing tiger model has been benchmarked.
- [ ] General animal detector is operational.
- [ ] Priority Pench species are supported.
- [ ] Unknown/abstention is implemented.
- [ ] Image quality filtering is implemented.
- [ ] Multi-animal detection works.
- [ ] Event-level aggregation works.
- [ ] Day/night performance is separately validated.
- [ ] Test data contains unseen camera stations.
- [ ] Per-class precision/recall/F1 are reported.
- [ ] Confidence is calibrated.
- [ ] Human review workflow exists.
- [ ] Model versions are tracked.
- [ ] Hard-negative mining works.
- [ ] Active-learning dataset pipeline exists.
- [ ] Structured observations are stored.
- [ ] Tiger and prey observations can be spatially correlated.
- [ ] Tiger and prey observations can be temporally correlated.
- [ ] Analytics distinguish association from causation.
- [ ] No forced prediction is made on uncertain images.
- [ ] Production performance is validated on genuinely held-out Pench data.

# 49. Final Architecture

```text
                         PENCH CAMERA TRAPS
                                │
                                ▼
                       ┌─────────────────┐
                       │  Quality Gate   │
                       └────────┬────────┘
                                ▼
                       ┌─────────────────┐
                       │ Animal Detector │
                       └────────┬────────┘
                                ▼
                     ┌─────────────────────┐
                     │   Animal Crops      │
                     └─────────┬───────────┘
                               ▼
                    ┌──────────────────────┐
                    │ Species Classification│
                    └──────────┬───────────┘
                               │
             ┌─────────────────┼──────────────────┐
             ▼                 ▼                  ▼
      Tiger Specialist    Prey Specialist    Other/Unknown
             │                 │
      Existing Model      Pench Models
             │                 │
             └─────────────────┼──────────────────┘
                               ▼
                    Confidence + Calibration
                               │
                     ┌─────────┴─────────┐
                     ▼                   ▼
                  Accept              Review
                     │                   │
                     └─────────┬─────────┘
                               ▼
                       Event Aggregation
                               ▼
                    Count / Behaviour /
                    Sex / Age / Movement
                               ▼
                     Wildlife Observation DB
                               │
             ┌─────────────────┼─────────────────┐
             ▼                 ▼                 ▼
          Spatial           Temporal          Habitat
          Analysis          Analysis          Analysis
             │                 │                 │
             └─────────────────┼─────────────────┘
                               ▼
                    TIGER–PREY INTELLIGENCE
                               │
             ┌─────────────────┼─────────────────┐
             ▼                 ▼                 ▼
       Prey Availability   Tiger Association   Anomalies
             │                 │                 │
             └─────────────────┼─────────────────┘
                               ▼
                    CONSERVATION INSIGHTS
```