# 🐅 TYGRIS: Autonomous Wildlife Intelligence & Ecological Monitoring Platform

> **Vikasit Nagpur Hackathon 2026** | **Pench Tiger Reserve (PTR), Maharashtra / Central India Landscape**  
> An end-to-end platform uniting paper-faithful computer vision, individual tiger stripe biometrics, prey population ecology, camera-trap station health analytics, and real-time human-wildlife conflict triage.

[![Next.js](https://img.shields.io/badge/Frontend-Next.js%2016%20%2F%20React%2019-black?logo=next.js)](frontend-v2)
[![FastAPI](https://img.shields.io/badge/Backend-FastAPI-009688?logo=fastapi)](backend)
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python)](backend)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.0-3178C6?logo=typescript)](frontend-v2)
[![Flutter](https://img.shields.io/badge/Mobile-Flutter%20%2F%20Android-02569B?logo=flutter)](ranger_mobile)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 📌 Executive Summary

**TYGRIS** is designed for wildlife biologists, forest department officers, and on-ground field rangers. It transforms raw, high-volume camera trap data into actionable ecological intelligence. 

The platform is grounded in real-world camera-trap data from the **Pench Tiger Reserve 2024–2025 Annual Survey** (2,172 high-resolution captures across 62 unique tigers and 295 active spatial grids) and paper-faithful computer vision algorithms (*Ma et al., Ecological Indicators 2025*).

---

## 🌟 Core Modules

### 1. 🔍 Individual Tiger Re-Identification (Re-ID) & Stripe Biometrics
- **Dual-Branch Deep Feature Extraction**: Isolates invariant stripe patterns along the flanks, ribs, and shoulders of *Panthera tigris tigris*.
- **Bilateral Flank Alignment**: Handles independent left-flank and right-flank match galleries with orientation-aware scoring.
- **15-Point Anatomical Pose Keypoints**: Predicts head, spine, flank, and limb landmarks to normalize perspective and posture distortion.
- **Confidence Scoring & Decision Engine**: Automatically matches known individuals (e.g. `T103_F`, `T119_M`, `T98_M`) or routes ambiguous detections to a human-in-the-loop review desk.

### 2. 🦌 Prey Intelligence & Population Ecology Suite
- **Multi-Species Classification Pipeline**: Detects and identifies sympatric Central Indian prey species (Chital, Sambar, Gaur, Wild Pig, Nilgai, Barking Deer, Langur, Peafowl).
- **Relative Abundance Index (RAI)**: Calculates standardized abundance per 100 trap-nights across ranges, beats, and stations.
- **Predator-Prey Spatial & Diel Association**: Analyzes temporal co-occurrence curves (overlap coefficients $\Delta$) and spatial correlation between tiger movements and herbivore clusters.
- **Waterhole & Resource Risk Analytics**: Evaluates camera stations near perennial water sources and tracks encounter risks during drought periods.
- **Human-in-the-Loop Review Queue**: Low-confidence or obstructed animal captures are flagged for rapid ranger verification.

### 3. 🗺️ Spatio-Temporal GIS & Territory Intelligence
- **High-Fidelity Vector Map**: Renders Pench Core and Buffer boundaries, 7 administrative ranges, 77 beats, 44 peripheral villages, and 311 camera trap stations.
- **Territory Mapping (100% MCP)**: Computes Minimum Convex Polygon (MCP) home-range estimates for individual resident and transient tigers.
- **Station Report Card (Camera Trap Dossier)**: Full telemetry view for each camera trap station featuring:
  - Station metadata (GPS, range, beat, distance to nearest village/water).
  - Occupancy stats (total sightings, unique tigers, date range, image quality index).
  - Resident tigers identified with interactive home-range overlays on high-res satellite imagery.
  - Complete chronological sighting history and threat levels.

### 4. 🚨 Conflict Triage & Perimeter Early Warning
- **Automated Threat Assessment**: Categorizes sightings into **🟢 Safe**, **🟡 Caution**, and **🔴 Danger** based on distance to the 44 boundary villages, tiger speed, and history.
- **Audio & Visual Alerts**: Multi-lingual notification broadcast system with voice announcements in **English**, **Hindi (हिंदी)**, and **Marathi (मराठी)**.
- **Village Proximity Monitoring**: Instant warnings when a high-risk individual approaches agricultural or residential zones.

### 5. 📱 Ranger Ops Field Mobility (`ranger_mobile/`)
- **Offline-First Field App**: Built with Flutter for field foresters and patrolling teams.
- **Field Incident & Spoor Logging**: Allows rangers to log pugmarks, scratch marks, kills, and direct sightings directly from patrol beats.
- **Supabase Cloud Sync**: Synchronizes ground observations with the central server and triggers automated territory cross-referencing.

---

## 📊 Pench Tiger Reserve (PTR) 2024–2025 Survey Dataset

The platform is pre-loaded and calibrated with the official 2024–2025 camera trap survey:

| Parameter | Value | Details |
| :--- | :--- | :--- |
| **Identified Tigers** | **62 unique individuals** | 31 Adult Females (`_F`), 27 Adult Males (`_M`), 4 Unassigned (`_U`) |
| **Photographic Catalog** | **2,172 images** | 1.77 GB high-resolution trail camera imagery |
| **Bilateral Capture Ratio** | **47.7% Cam A / 52.3% Cam B** | 1,035 left/right flank paired perspectives |
| **Camera Trap Stations** | **295 active grids** | Deployed across 7 forest ranges and 77 beats |
| **Grid Capture Efficiency** | **68.5%** | 202 grids recorded positive tiger events |
| **Peak Hotspots** | **Grids 229, 240, 248, 282** | Critical movement corridors and waterhole junctions |

---

## 📂 Repository Layout

```
tygris-2/
├── backend/                         # FastAPI ML & Ecological Intelligence Engine
│   ├── app/
│   │   ├── api/                     # REST API Endpoints
│   │   │   ├── routes_gis.py        # GIS bundle, 311 stations, and station dossiers
│   │   │   ├── routes_identify.py   # 5-stage tiger Re-ID & burst matching
│   │   │   ├── routes_prey.py       # Prey classification, insights, review queue
│   │   │   ├── routes_gallery.py    # Enrolled individual profiles & territories
│   │   │   └── routes_alerts.py     # Conflict alerts & village proximity triage
│   │   ├── ml/                      # Dual-branch embedding, pose estimation & fusion
│   │   ├── prey/                    # Animal detection, diel curves, RAI calculators
│   │   └── simulation/              # Pench agent-based movement simulation
│   ├── data/                        # SQLite DB (pench_unified.db), GeoJSON boundaries
│   ├── main.py                      # FastAPI application entrypoint (port 8420)
│   └── requirements.txt             # Python backend dependencies
│
├── frontend-v2/                     # Next.js 16 Interactive Glassmorphic Dashboard
│   ├── public/                      # Tiger portraits, GIS tiles, static media
│   ├── src/
│   │   ├── app/                     # Next.js App Router
│   │   ├── components/
│   │   │   ├── views/               # StationReportCardView, PreyCheckerView, etc.
│   │   │   └── ui/                  # Glass cards, interactive maps, badges
│   │   └── lib/                     # API client, TypeScript interfaces, i18n locales
│   ├── package.json
│   └── tsconfig.json
│
├── ranger_mobile/                   # Flutter cross-platform mobile application
│   ├── lib/                         # Mobile UI, patrol tracking, offline SQLite
│   └── pubspec.yaml
│
├── docs/                            # Research papers, survey reports & blueprints
│   ├── tiger_survey_analysis.md     # In-depth Pench 2024-2025 survey report
│   └── 1-s2.0-S1470160X25001566.pdf# Ma et al. 2025 Tiger Re-ID Paper
├── prey-identification/             # Prey PRD & ML architecture specifications
├── scripts/                         # Operational launchers and data pipeline scripts
│   └── run_dev.py                   # Unified development runner
├── start.bat                        # Windows 1-click execution script
└── README.md
```

---

## ⚡ Quick Start Guide

### System Requirements
- **Python**: 3.10, 3.11, or 3.12
- **Node.js**: v18.0.0 or higher
- **Package Manager**: `npm` or `pnpm`
- **OS**: Windows, macOS, or Linux

---

### 1. Installation

#### A. Backend Setup
```bash
cd backend
python -m venv .venv312

# Windows
.venv312\Scripts\activate

# Linux / macOS
source .venv312/bin/activate

pip install -r requirements.txt
cd ..
```

#### B. Frontend Setup
```bash
cd frontend-v2
npm install
cd ..
```

---

### 2. Dataset Setup on Your Device

> [!IMPORTANT]
> **Datasets are excluded from Git via `.gitignore`** to avoid committing heavy binary files (~1.77 GB) to the repository.

To use the full photographic dataset for training, Re-ID inference, or script analysis on your respective device:

1. **Obtain the survey dataset** folder (`PTR_Tiger_IDs_2025` containing the 62 tiger subdirectories).
2. **Place the folder** in your project root or dataset directory on your machine:
   ```
   tygris-2/
   ├── PTR_Tiger_IDs_2025/
   │   └── PTR_Tiger_IDs_2025/
   │       ├── T103_F/
   │       ├── T119_M/
   │       ├── T98_M/
   │       └── ... (62 tiger folders)
   ```
   *(Alternatively: place under `Dataset/PTR_Tiger_IDs_2025/PTR_Tiger_IDs_2025/`)*
3. **If storing on an external drive or dedicated SSD path**, update the `DATASET_DIR` constant in `scripts/migrate_real_tiger_dataset.py` or your `.env` configuration.

---

### 3. Running Locally

#### 🚀 Method 1: Unified 1-Click Launcher (Recommended)

**On Windows:**
Double-click `start.bat` or run:
```powershell
python scripts\run_dev.py
```

This concurrently boots:
1. **FastAPI Backend** on `http://localhost:8420`
2. **Next.js Frontend** on `http://localhost:3002`

---

#### 🛠️ Method 2: Individual Terminals

**Terminal 1 — Backend:**
```powershell
.\backend\.venv312\Scripts\python.exe -m uvicorn backend.main:app --host 0.0.0.0 --port 8420 --reload
```

**Terminal 2 — Frontend:**
```powershell
cd frontend-v2
npm run dev
```

---

### 3. Accessing the Services

| Service | URL | Description |
| :--- | :--- | :--- |
| 🖥️ **Web Dashboard** | [http://localhost:3002](http://localhost:3002) | Full interactive GIS, tiger directory, station dossiers & prey analytics |
| 📜 **Swagger / OpenAPI Docs** | [http://localhost:8420/docs](http://localhost:8420/docs) | Interactive API exploration and testing |
| 💓 **API Health Endpoint** | [http://localhost:8420/](http://localhost:8420/) | Server status and active module registry |

---

## 🌐 Key API Endpoints

```
GET  /api/gis/bundle                # Complete vector bundle (borders, 311 stations, 44 villages)
GET  /api/stations                  # All 311 camera stations with status & zone attributes
GET  /api/stations/{cam_id}         # Comprehensive Station Report Card & tiger encounter history
POST /api/identify                  # Tiger identification on uploaded camera-trap image
POST /api/prey/identify-check       # Prey detection, species classification & image quality
GET  /api/prey/insights/summary     # Relative abundance, diel overlap & waterhole intelligence
GET  /api/prey/review-queue         # Ambiguous captures requiring ranger confirmation
GET  /api/gallery                   # 62 enrolled tiger profiles, MCP territories & thumbnails
GET  /api/alerts                    # Real-time conflict triage and village approach alerts
```

---

## 🌍 Multi-Lingual Support (i18n)

The dashboard supports instant switching across three languages tailored for Maharashtra forest administration:
- 🇬🇧 **English** (Standard scientific reporting)
- 🇮🇳 **Hindi (हिंदी)** (State-wide administrative communication)
- 🇮🇳 **Marathi (मराठी)** (Local forest beat staff & village community liaison)

---

## 📜 Scientific References & Acknowledgments
- **Ma et al. (2025)**: *A dual-branch deep network for individual tiger re-identification and pose-assisted metric learning*, Ecological Indicators.
- **Wildlife Institute of India (WII) & NTCA**: Monitoring Tiger, Co-predators & Prey in India (Pench Tiger Reserve telemetry calibration).
- **Pench Tiger Reserve Forest Department**: 2024–2025 camera trap grid deployment and monitoring survey data.
