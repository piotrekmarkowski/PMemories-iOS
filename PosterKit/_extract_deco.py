#!/usr/bin/env python3
"""Cut every element out of the travel-scrapbook sheets.

Sheets are already individual elements on a transparent canvas. Method:
alpha>100 -> connected components -> area/size filter -> for any blob that is
clearly two-or-more elements fused (very large + low fill ratio), split it with
a distance-transform + watershed pass. Each element is saved as its own tight
RGBA crop (largest alpha blob kept).
"""
import cv2, numpy as np, os, sys, json

D = os.path.dirname(os.path.abspath(__file__))
SRC = "/Users/admin/Downloads"
OUT = os.path.join(D, "out")

SHEETS = {
    "frames":  "48CFA613-3ECC-49A4-8997-58FE0E87C76A 2.PNG",
    "deco1":   "54E02E8F-B266-4562-9C0D-550F4FAAA2A5.PNG",
    "deco2":   "573EDB9A-2AF1-4C9D-8AA5-B0B1754B0B05.PNG",
    "deco3":   "70966B49-5689-46E4-9132-B9E7C0282715.PNG",
    "deco4":   "37B24E49-C511-4607-8D00-BDD386968F78.PNG",
    "deco5":   "03B5196C-66A1-4610-AF76-241188A78091.PNG",
    "deco6":   "7A9C2432-1F58-4B32-AF29-1B534198C9A5.PNG",
    "deco7":   "86E8FAE5-D05E-4297-A94A-581FB6C015F7.PNG",
    "deco8":   "0776FFD9-2AB7-4904-949B-B5189201DA0A.PNG",
}

ALPHA_T = 100
MIN_AREA = 2200
MIN_WH = 26
PAD = 5
SPLIT_AREA = 120_000          # blobs bigger than this get a watershed split try
SPLIT_FILL = 0.62             # ...but only if bbox fill ratio is below this


def largest_blob(alpha):
    m = (alpha > 30).astype(np.uint8)
    n, lbl, st, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
    if n <= 2:
        return alpha
    keep = 1 + int(np.argmax(st[1:, 4]))
    out = alpha.copy()
    out[lbl != keep] = 0
    return out


def watershed_split(sub_alpha):
    """Return a list of boolean masks, one per sub-element."""
    m = (sub_alpha > ALPHA_T).astype(np.uint8)
    dt = cv2.distanceTransform(m, cv2.DIST_L2, 5)
    peak = dt.max()
    for frac in (0.45, 0.5, 0.55, 0.6):
        seeds = (dt > peak * frac).astype(np.uint8)
        n, lbl = cv2.connectedComponents(seeds, connectivity=8)
        if n - 1 >= 2:
            break
    if n - 1 < 2:
        return [m.astype(bool)]
    markers = np.zeros(m.shape, np.int32)
    for i in range(1, n):
        markers[lbl == i] = i
    markers[m == 0] = n
    cv2.watershed(cv2.cvtColor(m * 255, cv2.COLOR_GRAY2BGR), markers)
    return [(markers == i) for i in range(1, n) if (markers == i).sum() > MIN_AREA]


def process(tag, fname):
    rgba = cv2.imread(os.path.join(SRC, fname), cv2.IMREAD_UNCHANGED)
    H, W = rgba.shape[:2]
    alpha = rgba[:, :, 3]
    m = (alpha > ALPHA_T).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)))
    n, lbl, st, _ = cv2.connectedComponentsWithStats(m, connectivity=8)

    d = os.path.join(OUT, tag)
    os.makedirs(d, exist_ok=True)
    boxes = []
    for i in range(1, n):
        x, y, w, h, area = st[i]
        if area < MIN_AREA or w < MIN_WH or h < MIN_WH:
            continue
        comp = (lbl == i)
        pieces = [comp]
        if area > SPLIT_AREA and area / (w * h) < SPLIT_FILL:
            sub = np.zeros((h, w), np.uint8)
            sub[comp[y:y + h, x:x + w]] = alpha[y:y + h, x:x + w][comp[y:y + h, x:x + w]]
            ms = watershed_split(sub)
            if len(ms) >= 2:
                pieces = []
                for mm in ms:
                    full = np.zeros((H, W), bool)
                    full[y:y + h, x:x + w] = mm
                    pieces.append(full & comp)
        for pc in pieces:
            ys, xs = np.where(pc)
            if len(xs) < MIN_AREA:
                continue
            x0, x1 = max(0, xs.min() - PAD), min(W, xs.max() + PAD)
            y0, y1 = max(0, ys.min() - PAD), min(H, ys.max() + PAD)
            crop = rgba[y0:y1, x0:x1].copy()
            keepmask = pc[y0:y1, x0:x1]
            km = cv2.morphologyEx(keepmask.astype(np.uint8), cv2.MORPH_CLOSE,
                                  cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15)))
            crop[:, :, 3] = np.where(km > 0, crop[:, :, 3], 0)
            crop[:, :, 3] = largest_blob(crop[:, :, 3])
            ys2, xs2 = np.where(crop[:, :, 3] > 8)
            if len(xs2) < MIN_AREA:
                continue
            crop = crop[max(0, ys2.min() - PAD):ys2.max() + PAD,
                        max(0, xs2.min() - PAD):xs2.max() + PAD]
            boxes.append((int(x0), int(y0), crop))

    boxes.sort(key=lambda b: (b[1] // 120, b[0]))
    meta = []
    for idx, (x0, y0, crop) in enumerate(boxes):
        fn = f"{tag}_{idx:02d}.png"
        cv2.imwrite(os.path.join(d, fn), crop)
        meta.append(dict(file=fn, w=int(crop.shape[1]), h=int(crop.shape[0])))
    json.dump(meta, open(os.path.join(d, "_meta.json"), "w"), indent=1)
    print(f"{tag:8s} {len(boxes):3d} elements  ({fname})")
    return len(boxes)


if __name__ == "__main__":
    which = sys.argv[1:] or list(SHEETS)
    total = 0
    for tag in which:
        total += process(tag, SHEETS[tag])
    print(f"\nTOTAL {total} elements")
