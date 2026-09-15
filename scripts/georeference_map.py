"""
Georeferences the real Pench Tiger Reserve map export (Dataset/.../map.png) against
the real camera GPS list (PTR Camera Locations 24-25.xlsx) to digitize the true
Core/Buffer zone outline and per-range sub-region stats.

Method:
1. Detect the ~298 white "Camera Trap Location" dot markers in map.png via HSV
   color threshold + contour circularity filtering.
2. Fit a north-up affine pixel->lat/lon transform (independent linear scale+offset
   per axis, no rotation - valid for a small, north-up Esri export) by rank-matching
   sorted detected-dot pixel coordinates against sorted real xlsx lat/lon values.
3. Trace the Core (dark green) and Core+Buffer (dark+light green) zone contours via
   HSV color thresholding + cv2.findContours, simplify, and convert pixel -> lat/lon.
4. Compute the 7 real sub-regions (one per xlsx "Range") with real centroid/area/zone.

Outputs printed Python literals for CORE_BOUNDARY / BUFFER_BOUNDARY / SUB_REGIONS,
meant to be reviewed and pasted into backend/app/simulation/pench_environment.py
(this script does not modify any files itself).
"""
import json
import math
import os

import cv2
import numpy as np
import pandas as pd

BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DATASET_DIR = os.path.join(BASE, "Dataset", "PTR_Tiger_IDs_2025", "PTR_Tiger_IDs_2025")
MAP_PNG = os.path.join(DATASET_DIR, "map.png")
CAMERA_XLSX = os.path.join(DATASET_DIR, "PTR Camera Locations 24-25.xlsx")


def detect_camera_dots(img):
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    lower_white = np.array([0, 0, 200])
    upper_white = np.array([180, 60, 255])
    mask = cv2.inRange(hsv, lower_white, upper_white)
    contours, _ = cv2.findContours(mask, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)

    candidates = []
    for c in contours:
        area = cv2.contourArea(c)
        if area < 8 or area > 150:
            continue
        perim = cv2.arcLength(c, True)
        if perim == 0:
            continue
        circularity = 4 * np.pi * area / (perim * perim)
        (x, y), radius = cv2.minEnclosingCircle(c)
        if radius < 3.6 or radius > 4.5 or circularity < 0.75:
            continue
        # Exclude legend swatch (top-left) and compass/scale-bar area (bottom-right)
        if 60 <= x <= 340 and 90 <= y <= 220:
            continue
        if x > 1150 and y > 800:
            continue
        candidates.append((x, y))
    return candidates


def fit_affine(dots, df):
    def resample(arr, n):
        if len(arr) == n:
            return arr
        idx = np.linspace(0, len(arr) - 1, n)
        return np.interp(idx, np.arange(len(arr)), arr)

    xs = np.array(sorted(x for x, y in dots))
    ys = np.array(sorted(y for x, y in dots))
    lons = np.array(sorted(df["Longitude"].values))
    lats_asc = np.array(sorted(df["Latitude"].values))
    lats_desc = lats_asc[::-1]

    n = min(len(xs), len(lons))
    a, b = np.polyfit(resample(lons, n), resample(xs, n), 1)
    n2 = min(len(ys), len(lats_desc))
    c, d = np.polyfit(resample(lats_desc, n2), resample(ys, n2), 1)
    return a, b, c, d


def trace_zone_polygons(img, transform):
    a, b, c, d = transform

    def px_to_latlon(x, y):
        return (y - d) / c, (x - b) / a

    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    mask_core = cv2.inRange(hsv, (40, 60, 160), (52, 255, 232))
    mask_total = cv2.inRange(hsv, (30, 60, 160), (55, 255, 255))

    kernel = np.ones((5, 5), np.uint8)
    for m in (mask_core, mask_total):
        cv2.morphologyEx(m, cv2.MORPH_CLOSE, kernel, iterations=2, dst=m)
        cv2.morphologyEx(m, cv2.MORPH_OPEN, kernel, iterations=1, dst=m)

    def largest_polygon(mask, epsilon_frac=0.0015):
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        c0 = max(contours, key=cv2.contourArea)
        peri = cv2.arcLength(c0, True)
        approx = cv2.approxPolyDP(c0, epsilon_frac * peri, True)
        return approx.reshape(-1, 2)

    core_pts = largest_polygon(mask_core)
    buffer_pts = largest_polygon(mask_total)

    def to_latlon_ring(pts):
        ring = [list(px_to_latlon(x, y)) for x, y in pts]
        ring.append(ring[0])
        return [[round(lat, 5), round(lon, 5)] for lat, lon in ring]

    return to_latlon_ring(core_pts), to_latlon_ring(buffer_pts)


def is_point_in_polygon(lat, lon, polygon):
    n = len(polygon)
    inside = False
    p1x, p1y = polygon[0][1], polygon[0][0]
    for i in range(n + 1):
        p2x, p2y = polygon[i % n][1], polygon[i % n][0]
        if min(p1y, p2y) < lat <= max(p1y, p2y):
            if lon <= max(p1x, p2x):
                if p1y != p2y:
                    xinters = (lat - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                if p1x == p2x or lon <= xinters:
                    inside = not inside
        p1x, p1y = p2x, p2y
    return inside


def build_sub_regions(df, core_boundary):
    habitat_labels = {
        "East Pench": "Teak-Bamboo Dense Forest",
        "West Pench": "Mixed Deciduous Riparian",
        "Deolapar": "Open Scrub Deciduous",
        "Chorbouli": "Dry Teak Secondary Forest",
        "Saleghat": "Rocky Ridge Forest",
        "Paoni": "Agricultural Fringe",
        "Nagalwadi": "Grassland Scrub",
    }
    sub_regions = []
    for range_name, grp in df.groupby(df["Range"].str.strip()):
        lats, lons = grp["Latitude"].values, grp["Longitude"].values
        c_lat, c_lon = float(np.mean(lats)), float(np.mean(lons))
        core_votes = sum(1 for la, lo in zip(lats, lons) if is_point_in_polygon(la, lo, core_boundary))
        zone = "CORE" if core_votes >= len(lats) / 2 else "BUFFER"
        area_km2 = 40.0
        if len(lats) >= 3:
            y = (lats - c_lat) * 111.32
            x = (lons - c_lon) * (111.32 * math.cos(math.radians(c_lat)))
            try:
                from scipy.spatial import ConvexHull
                area_km2 = round(float(ConvexHull(np.column_stack([x, y])).volume), 1)
            except Exception:
                pass
        sub_regions.append({
            "name": f"{range_name} Range", "zone": zone,
            "center": [round(c_lat, 5), round(c_lon, 5)], "area_km2": area_km2,
            "habitat": habitat_labels.get(range_name, "Mixed Forest"),
        })
    return sub_regions


def main():
    img = cv2.imread(MAP_PNG)
    df = pd.read_excel(CAMERA_XLSX).dropna(subset=["Latitude", "Longitude"])

    dots = detect_camera_dots(img)
    print(f"Detected {len(dots)} camera dots (xlsx has {len(df)} real stations)")

    a, b, c, d = fit_affine(dots, df)
    print(f"Affine transform: pixel_x = {a:.4f}*lon + {b:.4f}, pixel_y = {c:.4f}*lat + {d:.4f}")

    core_boundary, buffer_boundary = trace_zone_polygons(img, (a, b, c, d))
    print(f"CORE_BOUNDARY: {len(core_boundary)} points, BUFFER_BOUNDARY: {len(buffer_boundary)} points")

    sub_regions = build_sub_regions(df, core_boundary)
    for sr in sub_regions:
        print(sr)

    out = {"core_boundary": core_boundary, "buffer_boundary": buffer_boundary, "sub_regions": sub_regions}
    out_path = os.path.join(BASE, "scripts", "_georeference_output.json")
    with open(out_path, "w") as f:
        json.dump(out, f, indent=2)
    print(f"Wrote {out_path} for review (not auto-applied to pench_environment.py)")


if __name__ == "__main__":
    main()
