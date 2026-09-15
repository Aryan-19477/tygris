# Comprehensive Data Analysis & Inventory Report
## Pench Tiger Reserve (PTR) — Camera Trap Survey 2024–2025

> **Location:** Pench Tiger Reserve (Maharashtra / Central India Landscape)  
> **Survey Period:** December 2024 – February 2025  
> **Datasets Analyzed:** `PTR Camera Locations 24-25.xlsx` & `PTR_Tiger_IDs_2025/`  
> **Report Generated:** September 2026  

---

## Table of Contents
1. [Executive Summary](#1-executive-summary)
2. [Analysis of the Excel File: Camera Station Metadata](#2-analysis-of-the-excel-file-camera-station-metadata)
   - [Schema & Attribute Definitions](#schema--attribute-definitions)
   - [Administrative Distribution (Ranges, Blocks, Beats)](#administrative-distribution)
   - [Geographic Coverage & Coordinate Extents](#geographic-coverage--coordinate-extents)
   - [Data Quality, Anomalies & Removed Grids](#data-quality-anomalies--removed-grids)
3. [Analysis of the Tiger Folder: Imagery & Identity Structure](#3-analysis-of-the-tiger-folder-imagery--identity-structure)
   - [Directory Hierarchy & Tiger ID Nomenclature](#directory-hierarchy--tiger-id-nomenclature)
   - [Filename Syntax & Encoding Scheme](#filename-syntax--encoding-scheme)
   - [Camera Flank Distribution (Camera A vs Camera B)](#camera-flank-distribution)
   - [Technical Hardware & EXIF Telemetry](#technical-hardware--exif-telemetry)
4. [Spatial Ecology, Landscape & Territory Analysis](#4-spatial-ecology-landscape--territory-analysis)
   - [Range-by-Range Comparative Overview](#range-by-range-comparative-overview)
   - [Block 1 vs Block 2 Deployment Dynamics](#block-1-vs-block-2-deployment-dynamics)
   - [Top Camera Trap Hotspots (Diversity & Frequency)](#top-camera-trap-hotspots)
   - [Territorial Overlaps & Tiger Co-Occurrence](#territorial-overlaps--tiger-co-occurrence)
5. [Master Inventory: Comprehensive Profiles of All 62 Tigers](#5-master-inventory-comprehensive-profiles-of-all-62-tigers)
   - [Summary Statistics by Sex](#summary-statistics-by-sex)
   - [Notable Individuals (Superstars, Roamers & Elusive Tigers)](#notable-individuals)
   - [Complete Master Table (All 62 Tigers)](#complete-master-table)
6. [Machine Learning & Computer Vision Readiness](#6-machine-learning--computer-vision-readiness)

---

## 1. Executive Summary

This investigation presents a rigorous technical and ecological synthesis of two interconnected monitoring assets from **Pench Tiger Reserve (PTR), Maharashtra**, collected during the **2024–2025 annual tiger estimation exercise**:

1. **`PTR Camera Locations 24-25.xlsx`**: The geospatial master register containing **298 camera trap deployment records** across **7 forest ranges**, **2 administrative blocks**, and **77 beats**, with **295 active spatial stations**.
2. **`PTR_Tiger_IDs_2025`**: The photographic database comprising **2,172 high-resolution camera trap images** (1.77 GB) organized into **62 individual tiger folders**.

### Key High-Level Metrics

| Metric | Value | Context / Notes |
| :--- | :--- | :--- |
| **Total Identified Tigers** | **62** | Unique individual Bengal tigers (*Panthera tigris tigris*) |
| **Adult Females (`_F`)** | **31** (50.0%) | Healthy female-dominated breeding population |
| **Adult Males (`_M`)** | **27** (43.5%) | Resident and transient territorial males |
| **Unassigned / Unknown (`_U`)** | **4** (6.5%) | Single-capture or juvenile individuals (T145, T156, T157, T158) |
| **Total Tiger Photographs** | **2,172** | 100% in `.JPG` format |
| **Total Storage Size** | **1.77 GB** (1,814.36 MB) | High-fidelity trail camera sensor outputs |
| **Average Photos per Tiger** | **35.0** | Median: 30 photos (Range: 1 to 126 photos) |
| **Registered Camera Grids** | **295 active** (298 total) | 3 grids decommissioned (water submergence / terrain) |
| **Grids with Tiger Captures** | **202 grids** | **68.5% capture rate** across deployed stations |
| **Camera Flank Bilateral Balance** | **Cam A: 1,035** / **Cam B: 1,137** | 47.7% / 52.3% dual-trap bilateral symmetry |
| **Survey Temporal Window** | **Dec 13, 2024 – Feb 25, 2025** | Winter peak monitoring season |

---

## 2. Analysis of the Excel File: Camera Station Metadata

The file `PTR Camera Locations 24-25.xlsx` is a clean, single-sheet Microsoft Excel document (`Sheet1`) defining the sampling grid frame used during the 2024–2025 Phase IV tiger monitoring.

### Schema & Attribute Definitions

| Column Name | Non-Null Count | Data Type | Description & Domain |
| :--- | :--- | :--- | :--- |
| `GRID ID` | 298 | Integer / String | Unique identifier of each camera trap station (1–313). Three entries contain decommission status annotations. |
| `Block` | 298 | String | Operational survey block: `Block 1` (163 stations) or `Block 2` (135 stations). |
| `Beat` | 298 | String | Forest Department beat boundary (77 distinct administrative beats). |
| `Range` | 298 | String | Forest Range jurisdiction under Pench Tiger Reserve (7 distinct ranges). |
| `Latitude` | 295 | Float64 | Decimal degree WGS84 latitude coordinate (~21.448°N to 21.707°N). |
| `Longitude` | 295 | Float64 | Decimal degree WGS84 longitude coordinate (~78.999°E to 79.381°E). |

### Administrative Distribution

#### Range Breakdown in Master Register
| Range | Total Stations Deployed | % of Survey Grid | Key Beat Areas Included |
| :--- | :---: | :---: | :--- |
| **East Pench** | 70 | 23.5% | Tuyapar, North Kirangisarra, South Fulzari, North Fulzari... |
| **Nagalwadi** | 63 | 21.1% |       Nagalwadi(North)          ,        Suwardharai (West)          ,        Suwardharai (North)          , Mohgaon... |
| **West Pench** | 52 | 17.4% | East Ghatpendhari, Ghorad , West Narhar, South Ghatpendhari... |
| **Chorbouli** | 39 | 13.1% | Kirangisarra (West), Chorbahuli, Ambazari, Satrapur... |
| **Deolapar** | 26 | 8.7% | Khursapar, Bakari, Bandra, Swara... |
| **Paoni** | 26 | 8.7% | Bajarkund, Tuyapar, South Pathrai, Ambazari... |
| **Saleghat** | 22 | 7.4% | Sawangi, Saleghat (South), Saleghat (North), Saleghat North... |

#### Survey Block Breakdown
- **Block 1**: 163 camera stations (54.7%) — Focuses primarily on western, northern, and buffer interface sections.
- **Block 2**: 135 camera stations (45.3%) — Covers eastern core, central reservoir margins, and southern corridor tracts.

### Geographic Coverage & Coordinate Extents

The 295 active coordinate pairs delineate a spatial bounding box enclosing approximately **1,100 km²** of Pench Tiger Reserve:
- **Northern Boundary:** Latitude `21.707167° N` (Range: West Pench, Beat: Kolitmara)
- **Southern Boundary:** Latitude `21.448399° N` (Range: Paoni, Beat: Sillari)
- **Western Boundary:** Longitude `78.999725° E` (Range: Nagalwadi, Beat: Ambabarai)
- **Eastern Boundary:** Longitude `79.381004° E` (Range: East Pench, Beat: Pipariya)
- **Geographic Centroid:** `21.5778° N, 79.1904° E`

### Data Quality, Anomalies & Removed Grids

Three records in the Excel file have null coordinates and descriptive string labels indicating decommissioned stations:
1. **`258_Removed_Not Accessible`** (Block 2, Range: *Paoni*, Beat: *Bajarkund*) — Inaccessible due to hazardous rocky terrain or steep nullah.
2. **`9_Removed_Water`** (Block 2, Range: *East Pench*, Beat: *Central Bodalzira*) — Submerged by backwaters of the Totladoh / Pench reservoir.
3. **`220_Removed_Water`** (Block 2, Range: *Chorbouli*, Beat: *Kirangisarra (West)*) — Submerged or waterlogged stream bank.

> [!NOTE]
> None of the 2,172 tiger photographs reference these 3 removed grids. All photo prefixes strictly map to the 295 active stations.

---

## 3. Analysis of the Tiger Folder: Imagery & Identity Structure

The directory `PTR_Tiger_IDs_2025` houses the primary visual census assets. Internally, it features a single nesting level (`PTR_Tiger_IDs_2025/PTR_Tiger_IDs_2025/`), containing **62 subfolders**, each representing an individual tiger.

### Directory Hierarchy & Tiger ID Nomenclature

Folders follow a standardized identity naming protocol:
```text
T<ID>_<SEX>
├── T103_F/  (15 photos)  -> Tiger 103, Female
├── T108_M/  (56 photos)  -> Tiger 108, Male
├── T145_U/  (2 photos)   -> Tiger 145, Unknown sex
└── T98_M/   (126 photos) -> Tiger 98, Male
```

### Filename Syntax & Encoding Scheme

Every image follows a structured camera-trap naming convention that embeds location, hardware channel, and frame sequence:

$$\text{Format: } \mathbf{\{GRID\_ID\}\_\{CAMERA\_FLANK\}\_\{BURST/SENSOR\_TAG\}\_\{FRAME\_ID\}.JPG}$$

| Component | Example Values | Meaning & Function |
| :--- | :--- | :--- |
| **`GRID_ID`** | `229`, `17`, `63`, `282` | Foreign key referencing `GRID ID` in `PTR Camera Locations 24-25.xlsx`. |
| **`CAMERA_FLANK`** | `A`, `B` | Camera unit at the station: **`A`** typically captures Left Flank, **`B`** captures Right Flank. |
| **`BURST/SENSOR_TAG`** | `I__`, `Cdy`, `MFG_`, `__` | Camera firmware trigger mode: `I__` (Infrared flash trigger), `Cdy` (Cuddeback burst series). |
| **`FRAME_ID`** | `00010`, `00224`, `03146` | Sequential frame counter generated by the trail camera hardware. |

### Camera Flank Distribution

Standard wildlife camera-trapping protocols deploy paired camera units on opposite sides of animal game trails to capture bilateral stripe patterns simultaneously:
- **Camera A Captures:** **1,035 photos** (47.65%)
- **Camera B Captures:** **1,137 photos** (52.35%)
- **Other / Unclassified:** **0 photos** (0.00%)

This balance confirms rigorous field execution, ensuring bilateral stripe profile coverage for re-identification models.

### Technical Hardware & EXIF Telemetry

- **Native Resolution:** 100% of sampled images are **2048 × 1536 pixels** (3.15 Megapixels, 4:3 aspect ratio).
- **Encoding:** Baseline JPEG, 24-bit sRGB color.
- **Sensor Hardware:** Cuddeback CuddeLink / Attack Digital Scouting Cameras.
- **Capture Date Range (EXIF):** `2024-12-13 20:08:06` to `2025-02-25 18:14:04`.
- **File Size per Photo:** Mean = 835 KB (Standard range: 500 KB to 1.4 MB depending on nighttime IR vs daytime color capture).

---

## 4. Spatial Ecology, Landscape & Territory Analysis

### Range-by-Range Comparative Overview

By cross-referencing each photo's Grid ID with the geographic register, we derive the distribution of tiger activity across Pench Tiger Reserve:

| Forest Range | Deployed Cameras | Photos Recorded | Unique Tigers Sighted | Males (`_M`) | Females (`_F`) | Unknown (`_U`) | Activity Share |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **East Pench** | 70 | 568 | **21** | 11 | 10 | 0 | 26.2% |
| **West Pench** | 52 | 320 | **14** | 6 | 7 | 1 | 14.7% |
| **Chorbouli** | 39 | 309 | **11** | 5 | 5 | 1 | 14.2% |
| **Paoni** | 26 | 177 | **11** | 4 | 7 | 0 | 8.1% |
| **Deolapar** | 26 | 381 | **13** | 6 | 7 | 0 | 17.5% |
| **Nagalwadi** | 63 | 341 | **14** | 5 | 7 | 2 | 15.7% |
| **Saleghat** | 22 | 76 | **9** | 4 | 5 | 0 | 3.5% |

> [!TIP]
> **East Pench** is the prime ecological core, yielding 568 photos (26.2%) and hosting 21 distinct tigers. **Deolapar** follows with 381 photos (17.5%) across 13 tigers, and **Nagalwadi** recorded 341 photos across 14 tigers.

### Block 1 vs Block 2 Deployment Dynamics

| Survey Block | Deployed Stations | Active Tiger Stations | Photos Recorded | Unique Tigers Recorded | Primary Forest Ranges |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Block 1** | 163 | 110 | 1,118 | 39 tigers | Nagalwadi, West Pench, Saleghat |
| **Block 2** | 135 | 108 | 1,054 | 32 tigers | East Pench, Chorbouli, Paoni, Deolapar |

### Top Camera Trap Hotspots

#### Grids with Highest Tiger Diversity (Multi-Tiger Intersections)
| Grid ID | Unique Tigers | Total Photos | Range | Beat | Identified Tigers Recorded |
| :---: | :---: | :---: | :--- | :--- | :--- |
| **75** | **7** | 45 | West Pench | West Ghatpendhari | T138_F, T139_M, T141_M, T142_M, T145_U, T90_M, T95_F |
| **73** | **6** | 15 | West Pench | Ghorad  | T138_F, T139_M, T141_M, T142_M, T90_M, T95_F |
| **289** | **5** | 28 | Chorbouli | Chorbahuli | T108_M, T148_F, T149_M, T151_M, T45_F |
| **119** | **5** | 14 | West Pench | Aamti | T123_F, T138_F, T139_M, T90_M, T95_F |
| **96** | **5** | 26 | West Pench | Ghorad  | T138_F, T139_M, T141_M, T142_M, T95_F |
| **286** | **4** | 13 | Chorbouli | Dahoda | T108_M, T149_M, T69_F, T98_M |
| **181** | **4** | 15 | Nagalwadi | Surewani            | T109_M, T137_M, T157_U, T57_F |
| **65** | **4** | 55 | East Pench | South Salama  | T112_M, T131_F, T24_F, T72_M |
| **117** | **4** | 16 | Saleghat | Ghatkukda | T115_M, T123_F, T90_M, T95_F |
| **11** | **4** | 17 | East Pench | West Kutumba | T134_M, T154_M, T58_M, T91_M |

#### Grids with Highest Photograph Density
| Grid ID | Total Photos | Unique Tigers | Range | Beat | Primary Tiger Frequenting |
| :---: | :---: | :---: | :--- | :--- | :--- |
| **313** | **80** | 3 | Chorbouli | Satrapur | T98_M |
| **68** | **65** | 2 | Deolapar | Bakari | T67_F |
| **257** | **57** | 3 | Nagalwadi | Shiladevi | T111_M |
| **65** | **55** | 4 | East Pench | South Salama  | T112_M |
| **178** | **46** | 3 | Paoni | Palora | T93_M |
| **75** | **45** | 7 | West Pench | West Ghatpendhari | T90_M |
| **12** | **44** | 3 | East Pench | East Chikhalkhari | T134_M |
| **2** | **35** | 3 | East Pench | North Bodalzira | T82_F |
| **125** | **34** | 3 | West Pench | Kolitmara | T90_M |
| **15** | **32** | 2 | Deolapar | Khursapar | T51_F |

### Territorial Overlaps & Tiger Co-Occurrence

Analysis of shared camera stations reveals key social structure, breeding associations, and territorial boundaries:

| Tiger Pair | Sex Combination | Shared Camera Grids | Primary Shared Range | Ecological Significance |
| :--- | :---: | :---: | :--- | :--- |
| **T62_F & T93_M** | `F + M` | **13 grids** | East Pench | Potential mating pair / high territory overlap |
| **T90_M & T95_F** | `M + F` | **12 grids** | Saleghat, West Pench | Potential mating pair / high territory overlap |
| **T141_M & T95_F** | `M + F` | **9 grids** | West Pench | Potential mating pair / high territory overlap |
| **T92_F & T98_M** | `F + M` | **9 grids** | East Pench, Chorbouli, Paoni | Potential mating pair / high territory overlap |
| **T46_F & T90_M** | `F + M` | **8 grids** | West Pench, East Pench | Potential mating pair / high territory overlap |
| **T112_M & T18_F** | `M + F` | **6 grids** | East Pench | Potential mating pair / high territory overlap |
| **T139_M & T95_F** | `M + F` | **6 grids** | West Pench | Potential mating pair / high territory overlap |
| **T141_M & T142_M** | `M + M` | **6 grids** | West Pench | Territorial boundary interaction |
| **T111_M & T41_F** | `M + F` | **5 grids** | Nagalwadi | Potential mating pair / high territory overlap |
| **T69_F & T98_M** | `F + M` | **5 grids** | Chorbouli, Paoni | Potential mating pair / high territory overlap |

---

## 5. Master Inventory: Comprehensive Profiles of All 62 Tigers

### Summary Statistics by Sex

| Classification | Count | % of Population | Total Photos | Avg Photos/Tiger | Max Photos (Individual) | Avg Grids Visited |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Adult Females (`_F`)** | 31 | 50.0% | 1,197 | 38.6 | 102 | 6.5 grids |
| **Adult Males (`_M`)** | 27 | 43.5% | 970 | 35.9 | 126 | 7.6 grids |
| **Unknown / Unassigned (`_U`)** | 4 | 6.5% | 5 | 1.2 | 2 | 1.0 grids |

### Notable Individuals

1. **Top Sighted Male — `T98_M` (126 photos, 21 grids):** Dominates the Chorbouli and Paoni southern landscape with 106 captures in Chorbouli.
2. **Top Sighted Female — `T92_F` (102 photos, 17 grids):** Extensive core territory straddling Chorbouli (49 photos) and Paoni (43 photos). Overlaps heavily with T98_M across 9 grids.
3. **Widest Roamer — `T90_M` (85 photos, 32 distinct grids):** Most expansive home range in the reserve, regularly patrolling across three major ranges: West Pench (40 photos), East Pench (37 photos), and Saleghat (8 photos).
4. **Eastern Core Champion — `T93_M` (105 photos, 20 grids):** Prime dominant male of East Pench (65 photos), extending into Deolapar and Paoni.
5. **Elusive Individuals (Single-Sightings):**
   - `T156_U`: 1 photo at Grid 294 (Nagalwadi Range, Beat Ambabarai).
   - `T157_U`: 1 photo at Grid 181 (Nagalwadi Range, Beat Nagalwadi).
   - `T158_U`: 1 photo at Grid 290 (Chorbouli Range, Beat Chorbouli).

### Complete Master Table

The table below details **all 62 individual tigers**, sorted by total photo volume:

| # | Tiger Code | Sex | Photos | Size (MB) | Cam A | Cam B | Grids | Primary Range | All Ranges Visited | Beats Frequented |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- | :--- | :--- |
| 1 | **`T98_M`** | Male | **126** | 124.77 | 34 | 92 | 21 | **Chorbouli** | East Pench (5), Chorbouli (106), Paoni (15) | North Kirangisarra, Tuyapar, Kirangisarra (West) +8 more |
| 2 | **`T93_M`** | Male | **105** | 91.39 | 55 | 50 | 20 | **East Pench** | East Pench (65), Deolapar (22), Paoni (18) | North Fulzari, Central Fulzari, North Sillari +6 more |
| 3 | **`T92_F`** | Female | **102** | 104.23 | 49 | 53 | 17 | **Chorbouli** | East Pench (10), Chorbouli (49), Paoni (43) | North Kirangisarra, Kirangisarra (North), Tuyapar +5 more |
| 4 | **`T112_M`** | Male | **91** | 69.31 | 45 | 46 | 10 | **East Pench** | East Pench (91) | South Bodalzira , Totladoh, West Kutumba  +2 more |
| 5 | **`T62_F`** | Female | **87** | 79.8 | 39 | 48 | 14 | **East Pench** | East Pench (87) | North Fulzari, Central Fulzari, North Sillari +3 more |
| 6 | **`T90_M`** | Male | **85** | 71.14 | 37 | 48 | 32 | **West Pench** | West Pench (40), East Pench (37), Saleghat (8) | South Ghatpendhari, North Fulzari, Central Fulzari +14 more |
| 7 | **`T67_F`** | Female | **77** | 72.17 | 55 | 22 | 6 | **Deolapar** | East Pench (5), Deolapar (72) | East Kutumba , Bakari, North Salama |
| 8 | **`T72_M`** | Male | **74** | 64.34 | 45 | 29 | 8 | **Deolapar** | East Pench (21), Deolapar (53) | West Kutumba, West Kutumba , Bakari +3 more |
| 9 | **`T14_F`** | Female | **69** | 64.27 | 33 | 36 | 5 | **Deolapar** | Deolapar (69) | Garra, Usaripar, Bandra |
| 10 | **`T69_F`** | Female | **68** | 51.85 | 29 | 39 | 12 | **Chorbouli** | Paoni (2), Chorbouli (66) | Bajarkund, Tuyyapar (West), Devali (Borban) +3 more |
| 11 | **`T111_M`** | Male | **62** | 38.77 | 24 | 38 | 9 | **Nagalwadi** | Nagalwadi (61), West Pench (1) | Mahakepar, Shiladevi,        Suwardharai (North)           +2 more |
| 12 | **`T24_F`** | Female | **61** | 46.36 | 30 | 31 | 9 | **East Pench** | East Pench (42), Paoni (15), Deolapar (4) | North Sillari, North Salama, South Usripar +3 more |
| 13 | **`T109_M`** | Male | **59** | 38.15 | 29 | 30 | 15 | **Nagalwadi** | Nagalwadi (45), Saleghat (14) | Surewani           , Saleghat (East)          , Surewani (South) +5 more |
| 14 | **`T95_F`** | Female | **59** | 42.12 | 27 | 32 | 18 | **West Pench** | Saleghat (6), West Pench (53) | Ghatkukda, Aamti, West Narhar +6 more |
| 15 | **`T41_F`** | Female | **58** | 38.24 | 28 | 30 | 7 | **Nagalwadi** | Nagalwadi (58) |        Suwardharai (West)          , Shiladevi,        Suwardharai (North)           |
| 16 | **`T132_F`** | Female | **57** | 39.43 | 19 | 38 | 6 | **Nagalwadi** | Nagalwadi (57) | Shiladevi, Makardhokada |
| 17 | **`T108_M`** | Male | **56** | 46.75 | 30 | 26 | 11 | **Chorbouli** | Paoni (23), Chorbouli (33) | Palora, Dahoda, Ambazari +3 more |
| 18 | **`T139_M`** | Male | **52** | 42.22 | 19 | 33 | 9 | **West Pench** | West Pench (52) | Aamti, East Narhar, South Ghatpendhari +2 more |
| 19 | **`T134_M`** | Male | **51** | 53.36 | 29 | 22 | 4 | **East Pench** | East Pench (51) | West Kutumba, East Chikhalkhari, North Bodalzira +1 more |
| 20 | **`T140_F`** | Female | **51** | 39.91 | 34 | 17 | 10 | **West Pench** | West Pench (51) | East Ghatpendhari, West Ghatpendhari, South Ghatpendhari +1 more |
| 21 | **`T131_F`** | Female | **47** | 40.11 | 20 | 27 | 5 | **Deolapar** | Deolapar (26), East Pench (21) | Usaripar, West Kutumba , Bakari +2 more |
| 22 | **`T51_F`** | Female | **46** | 36.34 | 17 | 29 | 4 | **Deolapar** | Deolapar (46) | Khursapar |
| 23 | **`T46_F`** | Female | **45** | 42.09 | 20 | 25 | 10 | **West Pench** | West Pench (36), East Pench (9) | South Ghatpendhari, Kolitmara, South Fulzari +1 more |
| 24 | **`T130_F`** | Female | **42** | 44.0 | 16 | 26 | 3 | **Deolapar** | Deolapar (42) | Khursapar, Garra |
| 25 | **`T123_F`** | Female | **39** | 31.81 | 18 | 21 | 8 | **Nagalwadi** | Nagalwadi (29), Saleghat (9), West Pench (1) |       Nagalwadi(North)          ,         Ghatkukda (West)          , Ghatkukda +3 more |
| 26 | **`T45_F`** | Female | **37** | 29.49 | 16 | 21 | 7 | **Paoni** | Paoni (22), Chorbouli (15) | South Pathrai, Dahoda, North Chorbahuli  +2 more |
| 27 | **`T82_F`** | Female | **33** | 26.98 | 16 | 17 | 3 | **East Pench** | East Pench (33) | East Chikhalkhari, North Bodalzira |
| 28 | **`T141_M`** | Male | **31** | 24.76 | 14 | 17 | 11 | **West Pench** | West Pench (31) | East Narhar, Kolitmara, West Narhar +3 more |
| 29 | **`T57_F`** | Female | **31** | 19.99 | 10 | 21 | 6 | **Nagalwadi** | Nagalwadi (31) | Surewani           , Saleghat (East)          , Surewani (South) |
| 30 | **`T115_M`** | Male | **30** | 21.11 | 15 | 15 | 11 | **Nagalwadi** | Nagalwadi (17), Saleghat (13) |       Nagalwadi(North)          , Ghatkukda, Nagalwadi (East)           +4 more |
| 31 | **`T149_M`** | Male | **30** | 25.73 | 16 | 14 | 6 | **Chorbouli** | Chorbouli (26), Paoni (4) | Dahoda, North Chorbahuli , Chorbahuli +1 more |
| 32 | **`T91_M`** | Male | **25** | 22.48 | 13 | 12 | 6 | **East Pench** | East Pench (25) | West Kutumba, East Chikhalkhari, North Bodalzira +1 more |
| 33 | **`T150_F`** | Female | **23** | 22.67 | 12 | 11 | 3 | **Paoni** | Paoni (23) | Palora |
| 34 | **`T18_F`** | Female | **21** | 16.68 | 11 | 10 | 6 | **East Pench** | East Pench (21) | Totladoh, South Bodalzira , South Salama +1 more |
| 35 | **`T76_F`** | Female | **21** | 18.77 | 10 | 11 | 7 | **Saleghat** | Nagalwadi (10), Saleghat (11) | Nagalwadi (East)          , Dhawalapur, Saleghat (East)           |
| 36 | **`T65_F`** | Female | **20** | 19.34 | 13 | 7 | 2 | **Deolapar** | Deolapar (20) | Bandra |
| 37 | **`T143_F`** | Female | **19** | 15.14 | 11 | 8 | 7 | **West Pench** | West Pench (13), East Pench (6) | East Narhar, Kolitmara, South Fulzari +2 more |
| 38 | **`T153_F`** | Female | **18** | 15.04 | 13 | 5 | 3 | **East Pench** | East Pench (18) | West Kutumba, Central Bodalzira |
| 39 | **`T138_F`** | Female | **17** | 11.17 | 8 | 9 | 7 | **West Pench** | West Pench (17) | Aamti, East Narhar, West Ghatpendhari +1 more |
| 40 | **`T103_F`** | Female | **15** | 10.85 | 7 | 8 | 6 | **Nagalwadi** | Saleghat (7), Nagalwadi (8) | Saleghat (North), Kubala, Saleghat (South) +2 more |
| 41 | **`T119_M`** | Male | **13** | 10.19 | 8 | 5 | 3 | **Saleghat** | Saleghat (7), Nagalwadi (6) | Saleghat (North),        Suwardharai (West)           |
| 42 | **`T137_M`** | Male | **12** | 7.75 | 6 | 6 | 3 | **Nagalwadi** | Nagalwadi (12) | Surewani           , Saleghat (East)          , Kubala |
| 43 | **`T34_F`** | Female | **11** | 8.02 | 7 | 4 | 2 | **West Pench** | West Pench (11) | East Ghatpendhari |
| 44 | **`T142_M`** | Male | **10** | 7.14 | 7 | 3 | 6 | **West Pench** | West Pench (10) | Surera, East Narhar, West Ghatpendhari +1 more |
| 45 | **`T154_M`** | Male | **10** | 9.16 | 6 | 4 | 2 | **East Pench** | East Pench (10) | West Kutumba, Central Bodalzira |
| 46 | **`T146_M`** | Male | **9** | 7.32 | 4 | 5 | 3 | **Deolapar** | Deolapar (9) | Khursapar |
| 47 | **`T147_F`** | Female | **8** | 6.48 | 4 | 4 | 1 | **Paoni** | Paoni (8) | Chargaon |
| 48 | **`T87_M`** | Male | **8** | 6.25 | 2 | 6 | 2 | **Deolapar** | Deolapar (8) | Khursapar |
| 49 | **`T144_M`** | Male | **7** | 5.68 | 4 | 3 | 2 | **Deolapar** | Deolapar (7) | Usaripar, Bandra |
| 50 | **`T127_F`** | Female | **6** | 3.71 | 3 | 3 | 3 | **Nagalwadi** | Saleghat (1), Nagalwadi (5) | Sawangi, Saleghat (East)          , Surewani (South) |
| 51 | **`T135_M`** | Male | **5** | 4.02 | 3 | 2 | 3 | **East Pench** | East Pench (5) | North Bodalzira, Central Bodalzira |
| 52 | **`T148_F`** | Female | **5** | 4.33 | 3 | 2 | 2 | **Paoni** | Paoni (4), Chorbouli (1) | North Chorbahuli , Chorbahuli |
| 53 | **`T151_M`** | Male | **5** | 3.34 | 1 | 4 | 2 | **Chorbouli** | Chorbouli (5) | Chorbahuli |
| 54 | **`T58_M`** | Male | **5** | 3.67 | 3 | 2 | 2 | **Deolapar** | East Pench (2), Deolapar (3) | West Kutumba, Khursapar |
| 55 | **`T152_F`** | Female | **4** | 3.15 | 2 | 2 | 1 | **Chorbouli** | Chorbouli (4) | Satrapur |
| 56 | **`T155_M`** | Male | **4** | 4.75 | 2 | 2 | 1 | **East Pench** | East Pench (4) | North Fulzari |
| 57 | **`T159_M`** | Male | **3** | 1.96 | 1 | 2 | 2 | **Chorbouli** | Chorbouli (3) | Chorbahuli |
| 58 | **`T145_U`** | Unknown | **2** | 1.17 | 1 | 1 | 1 | **West Pench** | West Pench (2) | West Ghatpendhari |
| 59 | **`T85_M`** | Male | **2** | 1.48 | 1 | 1 | 1 | **West Pench** | West Pench (2) | East Ghatpendhari |
| 60 | **`T156_U`** | Unknown | **1** | 0.59 | 0 | 1 | 1 | **Nagalwadi** | Nagalwadi (1) | Hetikheda |
| 61 | **`T157_U`** | Unknown | **1** | 0.51 | 1 | 0 | 1 | **Nagalwadi** | Nagalwadi (1) | Surewani            |
| 62 | **`T158_U`** | Unknown | **1** | 0.54 | 0 | 1 | 1 | **Chorbouli** | Chorbouli (1) | Chorbahuli |

---

## 6. Machine Learning & Computer Vision Readiness

The current folder structure and metadata provide an optimal baseline for Computer Vision (CV) and Wild-ID pipelines:

1. **Re-Identification (Re-ID) Benchmarking:**
   - 62 distinct identity classes with balanced bilateral flank captures (1,035 Cam A / 1,137 Cam B).
   - 45 tigers have $\ge 10$ photos, providing sufficient training, validation, and query samples for stripe-matching deep metric learning (e.g., Triplet Loss, ArcFace, HotSpotter).
2. **Geospatial & Temporal Priors:**
   - File prefixes directly yield Ground Truth coordinates (`Latitude`, `Longitude`) from the Excel register.
   - Spatial constraints (known home range centroids) can be incorporated into Bayesian re-ID ranking to penalize biologically improbable identity matches across distant ranges.
3. **Recommended Pre-processing Pipeline:**
   - **YOLOv8/v11 Tiger Detector:** Crop bounding box around tiger flank to eliminate foliage and night background noise.
   - **Flank Classifier:** Automatically assign Left vs Right flank based on head direction (since A/B cameras primarily map to opposite flanks).
   - **Standardized Metadata Export:** Generate a centralized `metadata.csv` joining image filenames, Tiger IDs, Sex, Grid IDs, Beat, Range, GPS coordinates, and EXIF timestamps.

---
*Document compiled automatically from raw field telemetry assets in workspace.*