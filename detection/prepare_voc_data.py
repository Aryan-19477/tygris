"""Convert the NTLNP voc_day/voc_night camera-trap detection dataset (Pascal
VOC XML bounding boxes) into a YOLO-format tiger-only detection dataset.

Source layout (per split):
  ntlnp_raw/voc_day/Annotations/*.xml   - one XML per image, VOC bndbox format
  ntlnp_raw/voc_day/JPEGImages/*.jpg

18 species are annotated across both splits; only images containing at least
one AmurTiger box are kept, since the goal is a tiger detector, not a
multi-species one. Other objects in a kept image's box list are dropped -
mixed-species frames become tiger-only labels for this stage.

Output layout (YOLO):
  detection/data/images/{train,val}/*.jpg
  detection/data/labels/{train,val}/*.txt   (class cx cy w h, normalized)
  detection/data/data.yaml
"""
import random
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

NTLNP_ROOT = Path(__file__).parent.parent / "ntlnp_raw"
OUT_ROOT = Path(__file__).parent / "data"
SOURCES = ["voc_day", "voc_night"]
TARGET_CLASS = "AmurTiger"
VAL_FRACTION = 0.15
SEED = 42
# CPU-feasible proof-of-concept subset; raise or drop the cap once GPU
# training is available.
MAX_IMAGES = 1000


def parse_voc_boxes(xml_path, target_class=TARGET_CLASS):
    root = ET.parse(xml_path).getroot()
    size = root.find("size")
    width = int(size.findtext("width"))
    height = int(size.findtext("height"))

    boxes = []
    for obj in root.findall("object"):
        if obj.findtext("name") != target_class:
            continue
        bnd = obj.find("bndbox")
        xmin = float(bnd.findtext("xmin"))
        ymin = float(bnd.findtext("ymin"))
        xmax = float(bnd.findtext("xmax"))
        ymax = float(bnd.findtext("ymax"))
        boxes.append((xmin, ymin, xmax, ymax))
    return boxes, width, height


def to_yolo_line(box, width, height, class_id=0):
    xmin, ymin, xmax, ymax = box
    cx = ((xmin + xmax) / 2) / width
    cy = ((ymin + ymax) / 2) / height
    w = (xmax - xmin) / width
    h = (ymax - ymin) / height
    return f"{class_id} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}"


def collect_tiger_annotations():
    """Return [(xml_path, jpg_path, [boxes], width, height), ...] for every
    image across both splits that has at least one AmurTiger box."""
    found = []
    for source in SOURCES:
        ann_dir = NTLNP_ROOT / source / "Annotations"
        img_dir = NTLNP_ROOT / source / "JPEGImages"
        if not ann_dir.exists():
            print(f"skip {source}: {ann_dir} not found")
            continue
        for xml_path in sorted(ann_dir.glob("*.xml")):
            boxes, width, height = parse_voc_boxes(xml_path)
            if not boxes:
                continue
            jpg_path = img_dir / (xml_path.stem + ".jpg")
            if not jpg_path.exists():
                continue
            found.append((xml_path, jpg_path, boxes, width, height))
    return found


def main():
    annotations = collect_tiger_annotations()
    print(f"Found {len(annotations)} images with at least one {TARGET_CLASS} box "
          f"across {SOURCES}")

    rng = random.Random(SEED)
    rng.shuffle(annotations)
    if MAX_IMAGES and len(annotations) > MAX_IMAGES:
        print(f"Capping to {MAX_IMAGES} images for a CPU-feasible proof of concept "
              f"(raise MAX_IMAGES once GPU training is available)")
        annotations = annotations[:MAX_IMAGES]

    num_val = max(1, int(len(annotations) * VAL_FRACTION))
    val_set = annotations[:num_val]
    train_set = annotations[num_val:]

    for split_name, split_items in [("train", train_set), ("val", val_set)]:
        img_out = OUT_ROOT / "images" / split_name
        lbl_out = OUT_ROOT / "labels" / split_name
        img_out.mkdir(parents=True, exist_ok=True)
        lbl_out.mkdir(parents=True, exist_ok=True)

        for xml_path, jpg_path, boxes, width, height in split_items:
            shutil.copy2(jpg_path, img_out / jpg_path.name)
            lines = [to_yolo_line(b, width, height) for b in boxes]
            (lbl_out / (jpg_path.stem + ".txt")).write_text("\n".join(lines) + "\n")

        print(f"{split_name}: {len(split_items)} images written to {img_out}")

    data_yaml = OUT_ROOT / "data.yaml"
    data_yaml.write_text(
        f"path: {OUT_ROOT.resolve()}\n"
        f"train: images/train\n"
        f"val: images/val\n"
        f"names:\n"
        f"  0: {TARGET_CLASS}\n"
    )
    print(f"\nWrote {data_yaml}")
    print(f"Train: {len(train_set)}  Val: {len(val_set)}")


if __name__ == "__main__":
    main()
