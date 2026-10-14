"""Regenerate the app icon's layers from the atlas: one smooth, separated shape per lobe.

The icon (CortiQuizSwift/CortiQuizSwift/AppIcon.icon, an Icon Composer document) is the
brain seen from the left, split into frontal, parietal, temporal and occipital lobes,
cerebellum and brainstem. icon.json makes each a Liquid Glass piece and fills the frontal
lobe with the accent pink. This script only rewrites the PNGs in AppIcon.icon/Assets;
colors and glass settings live in icon.json.

1. Classifies every brain structure in atlasStructure.json by lobe.
2. Renders the lobes from the left in flat ID colors (render_lobes.swift, SceneKit).
3. Smooths the partition (each pixel goes to the lobe with the most coverage nearby, so
   gyral parcel edges become clean curves), separates the pieces with a small gap, and
   writes a 1024 px white mask per lobe.

Usage (macOS with Xcode; requires `pip install pillow numpy`):
    python3 tools/icon/make_icon_layers.py

Preview the result with Icon Composer, or:
    ictool AppIcon.icon --export-image --output-file icon.png --platform iOS \
        --rendition Default --width 1024 --height 1024 --scale 1
"""

import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
APP = os.path.join(REPO, "CortiQuizSwift", "CortiQuizSwift")
ATLAS = os.path.join(APP, "atlasStructure.json")
MODELS = os.path.join(APP, "BrainModels")
ASSETS = os.path.join(APP, "AppIcon.icon", "Assets")

# Must match render_lobes.swift. The insula peeks out above the temporal lobe; it joins it.
LOBE_COLORS = {
    "frontal": [(255, 0, 0)],
    "parietal": [(0, 255, 0)],
    "temporal": [(0, 0, 255), (0, 128, 0)],
    "occipital": [(255, 255, 0)],
    "cerebellum": [(255, 0, 255)],
    "brainstem": [(0, 255, 255)],
}

CANVAS = 1024
WIDTH = 0.78         # brain width, as a fraction of the canvas
GAP = 16             # px between pieces, at 1024
PARTITION_BLUR = 48  # px at the 2048 render: how much lobe boundaries are smoothed
OUTLINE_BLUR = 18    # px at the 2048 render: how much the outline is smoothed


def classify_lobes():
    """(OBJ file, lobe) for every brain structure the app renders."""
    entries = json.load(open(ATLAS))
    by_id = {e["@id"]: e for e in entries}
    parent = {}
    for e in entries:
        if e.get("@type") == "Group":
            for member in e.get("member", []):
                parent[member] = e["@id"]
    files = {
        e["@id"]: e["source"].replace("models/", "").replace(".vtk", ".obj")
        for e in entries if e.get("@type") == "DataSource" and "source" in e
    }

    def path(i):
        names = []
        while i in parent:
            i = parent[i]
            names.append(by_id[i].get("annotation", {}).get("name", i))
        return " / ".join(reversed(names))

    rows = []
    for e in entries:
        if e.get("@type") != "Structure":
            continue
        model = None
        for selector in e.get("sourceSelector") or []:
            kinds = selector.get("@type")
            kinds = kinds if isinstance(kinds, list) else [kinds]
            if any("Geometry" in k for k in kinds) and selector.get("dataSource") in files:
                model = files[selector["dataSource"]]
                break
        if not model or model.startswith("Model_3_"):           # skin
            continue
        number = model.split("_")[1]
        if number.isdigit() and 4001 <= int(number) <= 4100:     # muscles
            continue
        name = e["annotation"]["name"]
        if any(k in name for k in ("white matter", "ventricle", "aqueduct")):
            continue                                              # inside; never seen
        p = path(e["@id"])
        lobe = "other"
        for key, label in [("frontal lobe", "frontal"), ("parietal lobe", "parietal"),
                           ("temporal lobe", "temporal"), ("occipital lobe", "occipital"),
                           ("cerebellum", "cerebellum"), ("insula", "insula")]:
            if key in p:
                lobe = label
        if lobe == "other" and ("midbrain" in p or any(k in name for k in ("pons", "medulla"))):
            lobe = "brainstem"
        rows.append((model, lobe))
    return rows


def render_id_map(rows, workdir):
    tsv = os.path.join(workdir, "lobes.tsv")
    with open(tsv, "w") as f:
        f.write("\n".join(f"{model}\t{lobe}" for model, lobe in rows))
    binary = os.path.join(workdir, "render_lobes")
    subprocess.run(["xcrun", "swiftc", "-O", os.path.join(HERE, "render_lobes.swift"), "-o", binary], check=True)
    out = os.path.join(workdir, "lobes.png")
    subprocess.run([binary, tsv, MODELS, out, "2048"], check=True)
    return np.array(Image.open(out).convert("RGB")).astype(int)


def make_layers(ids):
    h, w, _ = ids.shape
    order = list(LOBE_COLORS)
    raw = {}
    for lobe, colors in LOBE_COLORS.items():
        m = np.zeros((h, w), bool)
        for c in colors:
            m |= np.abs(ids - np.array(c)).sum(axis=2) < 60
        raw[lobe] = m
    union = np.logical_or.reduce(list(raw.values()))
    ys, xs = np.where(union)
    pad = 80
    x0, y0, x1, y1 = xs.min() - pad, ys.min() - pad, xs.max() + pad, ys.max() + pad

    def blurred(mask, radius):
        im = Image.fromarray((mask * 255).astype(np.uint8)).crop((x0, y0, x1, y1))
        return np.array(im.filter(ImageFilter.GaussianBlur(radius))).astype(float) / 255

    outline = blurred(union, OUTLINE_BLUR) > 0.5
    label = np.argmax(np.stack([blurred(raw[k], PARTITION_BLUR) for k in order]), axis=0)

    scale = CANVAS * WIDTH / (x1 - x0 - 2 * pad)
    out_w, out_h = int((x1 - x0) * scale), int((y1 - y0) * scale)
    ox = (CANVAS - out_w) // 2
    oy = (CANVAS - out_h) // 2 + int(CANVAS * 0.015)

    os.makedirs(ASSETS, exist_ok=True)
    for i, lobe in enumerate(order):
        piece = Image.fromarray((((label == i) & outline) * 255).astype(np.uint8))
        piece = piece.resize((out_w, out_h), Image.LANCZOS)
        mask = Image.new("L", (CANVAS, CANVAS), 0)
        mask.paste(piece, (ox, oy))
        mask = mask.point(lambda v: 255 if v > 127 else 0)
        mask = mask.filter(ImageFilter.MinFilter(GAP // 2 * 2 + 1)).filter(ImageFilter.GaussianBlur(1.0))
        layer = Image.new("RGBA", (CANVAS, CANVAS), (255, 255, 255, 0))
        layer.putalpha(mask)
        layer.save(os.path.join(ASSETS, f"{lobe}.png"))
        print("wrote", os.path.relpath(os.path.join(ASSETS, f"{lobe}.png"), REPO))


def main():
    with tempfile.TemporaryDirectory() as workdir:
        make_layers(render_id_map(classify_lobes(), workdir))


if __name__ == "__main__":
    sys.exit(main())
