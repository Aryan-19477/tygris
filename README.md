# 🐅 TYGRIS: Wildlife Intelligence, Spatio-Temporal Ecological Simulation & Tiger Re-ID Platform

**TYGRIS** is an end-to-end wildlife monitoring, spatio-temporal ecological intelligence, and individual tiger re-identification platform developed for the **Vikasit Nagpur Hackathon 2026**. 

The system combines paper-faithful computer vision (dual-branch deep feature extraction, background segmentation, and 15-point anatomical pose tracking based on *Ma et al., Ecological Indicators 2025*) with an agent-based ecological simulation engine calibrated against the **Wildlife Institute of India (WII) 2021 Pench Tiger Reserve Monitoring Report** (311 camera trap stations, 8,415 trap nights, individual home range MCPs, and perimeter village conflict alerts).

---

## 🚀 Key Modules & Architecture

### 1. **Next.js 16 Interactive Web Dashboard (`frontend-v2/`)**
- **Framework**: Next.js 16, React 19, Tailwind CSS v4, Motion, Phosphor Icons, Leaflet GIS.
- **Interactive GIS Map**: Live rendering of 311 WII camera trap stations, core/buffer park boundaries, 44 peripheral villages, and individual tiger 100% Minimum Convex Polygon (MCP) territories.
- **5-Stage Re-ID Pipeline Visualizer**: Step-through audit from raw photo ingestion to DDRNet body segmentation, 5% padded crop, dual-branch feature matching, and 15-point keypoint skeleton overlay.
- **Telemetry & Alert Feed**: Live conflict triage (🟢 Safe, 🟡 Caution, 🔴 Critical village approach alerts) with voice broadcast integration.
- **Tiger Directory & Gallery**: Detailed profiles with sighting histories, sex, life stage, philopatry status, and vector embeddings.

### 2. **FastAPI Ecological Intelligence & Vision Backend (`backend/`)**
- **REST Endpoints (`backend/app/api/`)**:
  - `/identify`: 5-stage visual inference, dual-branch late fusion, and burst clustering.
  - `/gallery`: Enrolled individual tiger profiles and polygon boundaries.
  - `/gis`: GeoJSON layers for Pench core/buffer zones, 311 camera trap stations, and villages.
  - `/alerts`: Conflict triage, alert generation, and village proximity metrics.
  - `/review`: Human-in-the-loop review queue for ambiguous or open-world tiger sightings.
  - `/embedding`: 2D PCA/UMAP projections of 64-D metric embeddings.
- **Simulation Engine (`backend/app/simulation/`)**: Agent-based tiger movement model with probabilistic step selection, core vs buffer prey densities, and 20 behavioral anomaly classes.

### 3. **Operational Scripts & Utilities (`scripts/`)**
- `run_dev.py`: Concurrent development launcher starting both FastAPI (port 8420) and Next.js (port 3002).
- `populate_tiger_assets.py` & `align_groundtruth_tiger_profiles.py`: Asset linking and gallery alignment.
- `rebuild_accurate_poses.py`: 15-point anatomical pose skeleton generator.

---

## 📂 Repository Structure

```
vikasit/
├── backend/                  # FastAPI Backend Server & ML Engine
│   ├── app/
│   │   ├── api/              # REST Endpoints (alerts, gallery, gis, identify, etc.)
│   │   ├── ml/               # Re-ID pipeline, fusion, pose, and ecology logic
│   │   └── simulation/       # Pench GIS environment & agent movement engine
│   ├── data/                 # Vector galleries, GeoJSON boundaries, and database
│   ├── main.py               # FastAPI entrypoint (port 8420)
│   └── requirements.txt      # Python dependencies
│
├── frontend-v2/              # Next.js 16 Glassmorphic Web Dashboard
│   ├── public/               # Tiger profile photos, maps, and UI assets
│   ├── src/
│   │   ├── app/              # Next.js App Router (pages, layout, globals)
│   │   └── components/       # MapView, PipelineVisualizer, PoseViewer, etc.
│   ├── package.json
│   └── tsconfig.json
│
├── docs/                     # Scientific papers, architectural specs, and notes
├── scripts/                  # Development and data pipeline scripts
├── implementation_plan.md    # Comprehensive system design document
├── start.bat                 # One-click Windows development launcher
└── README.md
```

---

## ⚡ Quick Start Guide

### Prerequisites
- **Python 3.10+**
- **Node.js 18+** and **npm**

### 1. Clone & Setup
```bash
git clone <REPO_URL>
cd vikasit
```

### 2. Install Dependencies

**Backend:**
```bash
cd backend
pip install -r requirements.txt
cd ..
```

**Frontend (v2):**
```bash
cd frontend-v2
npm install
cd ..
```

### 3. Launch Development Servers

Run the automated one-click launcher:
```bash
python scripts/run_dev.py
```
*(On Windows, you can simply double-click `start.bat`)*

- **Web Dashboard**: [http://localhost:3002](http://localhost:3002)
- **FastAPI Documentation**: [http://localhost:8420/docs](http://localhost:8420/docs)
- **API Health**: [http://localhost:8420/](http://localhost:8420/)

---

## 📜 Documentation & References
- `implementation_plan.md`: Comprehensive system architecture and implementation blueprint.
- `docs/1-s2.0-S1470160X25001566-main.pdf`: *Ma et al., Ecological Indicators (2025)* - Dual-Branch Tiger Re-ID Paper.
- `VIKASIT NAGPUR HACKATHON 2026.pdf`: Hackathon competition guidelines and challenge formulation.
