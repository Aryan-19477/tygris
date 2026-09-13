# **Amur Tiger Re-Identification — Explained From Scratch**

Let's build this up from zero, like you're new to the whole field.

---

## **The Core Problem**

Tigers are like humans — each one has unique stripe patterns (like a fingerprint). If you want to track individual tigers over years using camera trap footage (motion-triggered cameras in the forest), you need a way to answer: **"Is this the same tiger I saw last month, or a new one?"**

Doing this manually — a human staring at thousands of photos comparing stripes — is slow, error-prone, and requires expertise. So the researchers built an AI system to automate it.

---

## **Step 1: Getting the Data (The Raw Material)**

They used 30,000 camera traps across a 14,100 km² national park (China-Russia border region). Cameras trigger and record a 10-second video whenever something moves.

From 2012–2023, they had footage of **16 individual tigers** — meaning humans had already manually confirmed "this tiger is TIG-02," "this one is TIG-08," etc., across many videos.

**Key insight**: Real forest footage is messy — night, snow, tigers partially hidden by grass, different angles, blur. This is very different from a zoo where lighting and background are clean and controlled. Most earlier tiger-ID research used zoo data, which made models look more accurate than they'd really be in the wild.

---

## **Step 2: Building Two Datasets**

They didn't just dump raw footage into a model. They built two carefully curated datasets:

### **Dataset A — Segmentation Dataset (1,121 images)**

Purpose: teach a model to draw an outline around "where is the tiger" vs "where is the background" (grass, trees, snow, rocks).

They manually traced (labeled) the tiger's outline in 1,121 images using annotation software (Labelme). Just two labels: **tiger** or **background**.

### **Dataset B — Re-identification Dataset (34,691 images / 1,993 videos / 544 camera sites)**

Purpose: teach a model "which specific tiger is this."

Process:

1. Took raw video, chopped into frames (single images) → got 119,683 raw frames.  
2. Ran the segmentation model (from Dataset A) on all of them, to auto-remove backgrounds.  
3. Threw away bad frames (blurry, poorly segmented, no tiger visible, or too similar/redundant to other frames).  
4. Ended up with 34,691 clean, background-removed images of 16 known tigers.

**Why remove the background?** Because tigers are territorial — they get photographed at the same camera locations repeatedly. If you don't remove the background, the model might "cheat" by learning "this location \= TIG-02" instead of actually learning stripe patterns. That would make it useless the moment the tiger moves somewhere new, or another tiger passes the same camera.

---

## **Step 3: Splitting Data for Training/Testing (Avoiding Cheating)**

You can't just randomly shuffle all images into train/test sets. Why? Because many images come from the *same 10-second video* — they're nearly identical frames. If some frames from one video end up in "training" and others from the *same video* end up in "testing," the model isn't really being tested fairly — it's basically seeing the answer sheet.

**Their fix**: Split by **video/shot**, not by individual image. All frames from one video stay together in either train, validation, or test (ratio 6:2:2). This is called "shot-aware splitting" and prevents data leakage.

---

## **Step 4: The Model Pipeline (4 Stages)**

Think of this as an assembly line:

Video → Extract Frames → Segment (remove background) → Classify (who is this tiger?) → Output ID

### **Stage 1: Input Layer**

Video gets broken into individual frames, resized into a standard format (a "tensor" — just a numeric array a neural network can process).

### **Stage 2: Segmentation Layer — "Cut out the tiger"**

A neural network scans each frame and marks every pixel as "tiger" or "not tiger," then crops out just the tiger.

They tested **4 different segmentation architectures**: PP-LiteSeg, DDRNet, STDC, RegSeg. Think of these as 4 different "recipes" for building a segmentation model. They trained all 4 and compared performance using a metric called **IoU (Intersection over Union)** — basically, "how well does the predicted outline overlap with the real outline?"

**Winner: DDRNet-39** (scored 0.953 TIoU — closest match to the true tiger shape).

### **Stage 3: Classification Layer — "Whose stripes are these?"**

This is the heart of the system, and it's actually **two separate approaches running in parallel**, then combined:

**Approach A — Representation Learning (a standard classifier)** This is like a normal "sort into categories" model. You give it a tiger image, it outputs a probability for each of the 16 known tigers: "80% sure this is TIG-02, 15% TIG-08, 5% other."

They tested **10 different backbone architectures** (different neural network designs — ResNet, ConvNeXt, Swin Transformer, etc.) — like test-driving 10 different car engines to see which performs best on this specific road.

**Winner: ConvNeXt-small** (94.74% mAP — a measure of how precisely it ranks the correct tiger).

**Approach B — Metric Learning (a "similarity" approach)** Instead of directly classifying, this approach turns each image into a point in an abstract "feature space" (imagine a map where similar-looking tigers cluster close together). When a new image comes in, the model finds the **k=7 nearest known tigers** in that space (like "nearest neighbors" — similar to how Netflix might recommend movies based on similar users).

This uses the same best backbone (ConvNeXt-small) but repurposed slightly — the last classification layer is stripped out and replaced with an "embedding" layer that just outputs a location in this feature-space map.

**Why do both?** Because they work differently and fail differently. Combining them catches more correct answers than either alone.

### **Stage 4: Fusion — "Vote and combine"**

Instead of picking one approach, they blend both, using a weighted voting system:

* Approach A's top guess gets a fixed weight.  
* Approach B's top-7 nearest neighbors get weights based on how close they are (closer \= more weight).  
* Add up the "votes" for each candidate tiger across all frames in the video.  
* Whichever tiger ID gets the most total votes wins.  
* If no tiger gets enough confident votes, the system says **"unrecognized"** and treats it as a possible new individual.

This fusion step gave a real accuracy boost — going from \~91-93% (either method alone) to **95.49%** (both combined).

---

## **Step 5: Practices Used to Improve Accuracy (Why It Works Better)**

Here's the practical "tricks" list — this is probably the most useful part for your own project:

| Practice | Why it helps |
| ----- | ----- |
| **Background removal (segmentation first)** | Biggest single improvement — accuracy jumped from \~56% to \~95% for ConvNeXt-small. Prevents the model from "cheating" by memorizing camera backgrounds instead of learning tiger stripes. |
| **Shot-aware data splitting** | Prevents data leakage (train/test overlap from same video), giving a realistic accuracy estimate instead of an inflated one. |
| **Strict dataset diversity criteria** | Deliberately included all 4 seasons, day/dusk/night, various angles, partial occlusion, different postures — so the model doesn't overfit to "easy" conditions only. |
| **Data augmentation** | Random crop, grayscale, color jitter, lighting changes, RandAugment — artificially creates more training variety from the same images, improving generalization. |
| **No frozen layers in transfer learning** | Normally you "freeze" early layers of a pretrained model (like ImageNet-trained ConvNeXt) and only fine-tune the later layers. Here, letting *all* layers retrain worked better — because tiger stripes are very different from everyday ImageNet objects (dogs, cars, furniture), so even "basic" pretrained features needed adjustment. |
| **Fusion of two different modeling approaches** | Representation learning and metric learning make different kinds of mistakes — combining them covers each other's blind spots. |
| **CNN-based backbones over pure Transformers** | Counter to general trends (Transformers usually dominate CV benchmarks), the paper found CNN-style models (ConvNeXt, ResNeXt) worked better here — likely because tiger identification depends on subtle, local stripe details rather than "big picture" global features, which is what Transformers excel at. |
| **Open-world handling (unknown tiger detection)** | Real-world deployment isn't just "which of my 16 known tigers is this" — sometimes it's a *new* tiger nobody has seen. They tuned a distance threshold to catch new individuals, accepting a tradeoff: stricter thresholds catch more new tigers but misclassify more known ones. |

---

## **Step 6: How They Proved It's Actually Useful (Not Just a Lab Exercise)**

They used the re-ID outputs to calculate **home ranges** (the geographic area a tiger occupies) using a method called **Minimum Convex Polygon (MCP)** — basically drawing the smallest polygon that contains all the locations a tiger was seen at.

Findings that validate the pipeline:

* Male tigers had much bigger territories (\~883 km²) than females (\~70 km²) — matches known tiger biology.  
* They tracked a real event: one male tiger (TIG-19) died in 2021, and within the same year another male (TIG-100) took over his exact territory — a believable, biologically sound story that the re-ID data captured correctly.

This is the "proof it works" — if the tiger identification was wrong or noisy, these home range patterns wouldn't make ecological sense.

---

## **Summary — The Whole Thing in One Paragraph**

They took messy, real camera-trap video of wild tigers, cut individual frames, trained a segmentation model to cut out just the tiger (removing background so the model can't cheat), then ran two different types of AI models in parallel — one that directly classifies "which of 16 tigers is this," and one that finds "nearest similar tigers" in an abstract feature map — and combined their votes into one final answer. This got 95.49% accuracy, work that would previously need expert human eyes. Then they proved it wasn't just a lab trick by using the results to calculate real tiger territories and successfully catching a real biological event (territory takeover after a tiger's death).

Want me to go deeper into any one part — e.g., the actual math of the fusion formula, or how you'd adapt this exact pipeline for a different species like Bengal tigers/leopards for the MoEFCC project?

