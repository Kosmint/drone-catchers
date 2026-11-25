"""Demo-style sky art (the approved Stage 0.5 flight demo look, ported to Roblox).

Everything is flat low-poly, drawn with the same shapes as the demo canvas code:
  cloud_N.png   faceted cloud in neutral shading (shade rim / base / highlight facets);
                tinted in game with ImageColor3 = the demo's per-altitude cloud colour
  planet.png    ringed planet (12 alternating wedges, dusky band, ring back + front)
  moon.png      small faceted moon
  earth.png     top cap of the Earth curve (60 wedges) with the blue atmosphere rim
  sunglow.png   soft radial sun glow
  mount_N.png   4 tiles of the far blue mountain range
Rendered at 4x and downsampled for clean anti-aliased edges.

Usage: python art/demo_sky.py   -> art/out/demo/*.png
"""
import json
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "demo")
os.makedirs(OUT, exist_ok=True)
SS = 4  # supersampling


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


def finish(img, name):
    w, h = img.size
    img = img.resize((w // SS, h // SS), Image.LANCZOS)
    img.save(os.path.join(OUT, name))
    return img.size


def poly(d, pts, fill):
    d.polygon([(x * SS, y * SS) for x, y in pts], fill=fill)


# --------------------------------------------------------------------------- clouds
# neutral tones: the game tints with ImageColor3 = base colour / BASE (SurfaceGui Brightness
# compensates), so hi/mid read lighter and the shade rim darker, as in the demo
BASE, MID, HI, SHADE = 0.93, 0.965, 1.0, 0.82


def grey(v, a=255):
    g = int(round(v * 255))
    return (g, g, g, a)


def make_cloud(rnd):
    n = 4 + int(rnd.random() * 3)
    w = rnd.uniform(90, 190)
    puffs = []
    for i in range(n):
        r = rnd.uniform(0.35, 0.6) * w
        k = 7
        pts = []
        for j in range(k):
            a = j / k * 6.283 + 0.3
            pts.append((math.cos(a) * r * rnd.uniform(0.85, 1.1), math.sin(a) * r * rnd.uniform(0.8, 1.0)))
        puffs.append({
            "dx": (i / (n - 1) - 0.5) * w * 1.4,
            "dy": -math.sin(i / (n - 1) * 3.14) * w * 0.35,
            "r": r, "pts": pts,
        })
    return puffs


def render_cloud(puffs, name, px_per_unit=2.0):
    # bounds in demo units (y down)
    xs, ys = [], []
    for p in puffs:
        for q in p["pts"]:
            xs.append(p["dx"] + q[0])
            ys.append(p["dy"] + q[1])
            ys.append(p["dy"] + q[1] + p["r"] * 0.22)
    pad = 4
    x0, x1, y0, y1 = min(xs) - pad, max(xs) + pad, min(ys) - pad, max(ys) + pad
    W = int(math.ceil((x1 - x0) * px_per_unit))
    H = int(math.ceil((y1 - y0) * px_per_unit))
    img = canvas(W, H)
    d = ImageDraw.Draw(img)

    def tp(x, y):
        return ((x - x0) * px_per_unit, (y - y0) * px_per_unit)

    for p in puffs:  # shade rim (offset down)
        poly(d, [tp(p["dx"] + q[0], p["dy"] + q[1] + p["r"] * 0.22) for q in p["pts"]], grey(SHADE))
    for p in puffs:
        pts = [tp(p["dx"] + q[0], p["dy"] + q[1]) for q in p["pts"]]
        poly(d, pts, grey(BASE))
        ctr = tp(p["dx"], p["dy"])
        poly(d, [ctr, pts[4], pts[5]], grey(HI))
        poly(d, [ctr, pts[5], pts[6]], grey(MID))
    size = finish(img, name)
    # where the cloud origin (demo cloud x,y) sits inside the image, and its size in demo units
    return {
        "file": name, "px": size,
        "unitsW": x1 - x0, "unitsH": y1 - y0,
        "originU": (0 - x0) / (x1 - x0), "originV": (0 - y0) / (y1 - y0),
    }


# --------------------------------------------------------------------------- space bodies
def render_planet():
    pr = 120.0  # demo radius 70 -> drawn larger for resolution; game scales by demo units
    W, H = 512, 300
    cx, cy = W / 2, H / 2
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    rot = -0.35

    def ring_pts(a0, a1, rx, ry, steps=80):
        out = []
        for i in range(steps + 1):
            a = a0 + (a1 - a0) * i / steps
            x, y = math.cos(a) * rx, math.sin(a) * ry
            out.append((cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
        return out

    def ring(a0, a1, color):
        lw = 7 * pr / 70
        outer = ring_pts(a0, a1, pr * 1.8 + lw / 2, pr * 0.42 + lw / 2)
        inner = ring_pts(a0, a1, pr * 1.8 - lw / 2, pr * 0.42 - lw / 2)
        poly(d, outer + inner[::-1], color)

    ring(math.pi, 2 * math.pi, (255, 214, 190, 140))  # back half (behind the planet)
    n = 12
    for i in range(n):
        a0, a1 = i / n * 6.283, (i + 1) / n * 6.283
        poly(d, [(cx, cy), (cx + math.cos(a0) * pr, cy + math.sin(a0) * pr), (cx + math.cos(a1) * pr, cy + math.sin(a1) * pr)],
             hexc("#f2a7a0") + (255,) if i % 2 else hexc("#f6b8a8") + (255,))
    band = Image.new("RGBA", img.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    poly(bd, [(cx - pr * 0.95, cy - pr * 0.15), (cx + pr * 0.95, cy - pr * 0.3), (cx + pr * 0.95, cy - pr * 0.05), (cx - pr * 0.95, cy + pr * 0.12)], (206, 120, 140, 140))
    # clip band to the planet disc
    mask = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(mask)
    poly(md, [(cx + math.cos(i / n * 6.283) * pr, cy + math.sin(i / n * 6.283) * pr) for i in range(n)], 255)
    band.putalpha(Image.fromarray(np.minimum(np.array(band.getchannel("A")), np.array(mask))))
    img = Image.alpha_composite(img, band)
    d = ImageDraw.Draw(img)
    ring(0, math.pi, (255, 214, 190, 191))  # front half
    size = finish(img, "planet.png")
    return {"file": "planet.png", "px": size, "radiusPx": pr}


def render_moon():
    r = 110.0
    W = H = 240
    cx, cy = W / 2, H / 2
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    n = 10
    for i in range(n):
        a0, a1 = i / n * 6.283 - 1.2, (i + 1) / n * 6.283 - 1.2
        c = hexc("#e3def0") if i % 2 else hexc("#d3cde6")
        poly(d, [(cx, cy), (cx + math.cos(a0) * r, cy + math.sin(a0) * r), (cx + math.cos(a1) * r, cy + math.sin(a1) * r)], c + (255,))
    # shadowed lower-left facets (light from the upper right, like the demo sun)
    for i in (5, 6, 7):
        a0, a1 = i / n * 6.283 - 1.2, (i + 1) / n * 6.283 - 1.2
        poly(d, [(cx, cy), (cx + math.cos(a0) * r, cy + math.sin(a0) * r), (cx + math.cos(a1) * r, cy + math.sin(a1) * r)], hexc("#b7b0cf") + (255,))
    for (ox, oy, cr) in ((-0.3, -0.2, 0.2), (0.32, 0.25, 0.14), (0.05, 0.45, 0.1)):
        pts = [(cx + ox * r + math.cos(j / 6 * 6.283) * cr * r, cy + oy * r + math.sin(j / 6 * 6.283) * cr * r * 0.85) for j in range(6)]
        poly(d, pts, hexc("#bdb6d4") + (255,))
    size = finish(img, "moon.png")
    return {"file": "moon.png", "px": size, "radiusPx": r}


def render_earth():
    # demo: r = 1500 units, atmosphere rim radial gradient r*0.98 -> r*1.06, 60 wedges (3 colours)
    R = 1500.0
    cap = 720.0  # how deep below the top of the curve the image reaches (units)
    halfw = math.sqrt(R * R - (R - cap) ** 2) + 40
    rim = R * 1.06
    top = rim - R  # glow above the curve
    ppu = 0.42  # px per unit (soft content: rim glow + low-contrast wedges)
    W = int(2 * halfw * ppu)
    H = int((cap + top) * ppu)
    cx, cy = W / 2, (R + top) * ppu
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / ppu
    # rim glow (alpha .9 at r*0.98 fading to 0 at r*1.06)
    t = np.clip((dist - R * 0.98) / (R * 0.08), 0, 1)
    glow_a = 0.9 * (1 - t)
    rgb = np.zeros((H, W, 3), np.float32)
    rgb[...] = np.array([120, 210, 255], np.float32) / 255
    alpha = np.where(dist <= rim, glow_a, 0)
    # wedges
    ang = np.arctan2(yy - cy, xx - cx)  # -pi..0 on the upper half
    k = np.floor((ang - math.pi) % (2 * math.pi) / math.pi * 60).astype(int) % 3
    cols = np.array([hexc("#3b9c8f"), hexc("#4aa6c9"), hexc("#3a8fb8")], np.float32) / 255
    inside = dist <= R
    # anti-aliased limb
    edge = np.clip((R - dist) * ppu + 0.5, 0, 1)
    wc = cols[k]
    rgb = rgb * (1 - edge[..., None]) + wc * edge[..., None]
    alpha = np.maximum(alpha, edge)
    img = Image.fromarray((np.dstack([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)[..., None]]) * 255).astype(np.uint8), "RGBA")
    img.save(os.path.join(OUT, "earth.png"))
    return {"file": "earth.png", "px": img.size, "unitsW": 2 * halfw, "unitsH": cap + top, "topU": top}


def render_sunglow():
    S = 512
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    r = np.sqrt((xx - S / 2) ** 2 + (yy - S / 2) ** 2) / (S / 2)
    # demo stops: 0 -> (255,250,230,.9); .2 -> (255,236,200,.5); 1 -> (255,220,180,0)
    a = np.interp(r, [0, 0.2, 1.0], [0.9, 0.5, 0.0])
    c0, c1, c2 = np.array([255, 250, 230]), np.array([255, 236, 200]), np.array([255, 220, 180])
    rgb = np.where((r < 0.2)[..., None], c0 + (c1 - c0) * (r / 0.2)[..., None], c1 + (c2 - c1) * np.clip((r - 0.2) / 0.8, 0, 1)[..., None]) / 255
    img = Image.fromarray((np.dstack([rgb, np.clip(a, 0, 1)[..., None]]) * 255).astype(np.uint8), "RGBA")
    img.save(os.path.join(OUT, "sunglow.png"))
    return {"file": "sunglow.png", "px": img.size}


def render_mountains(rnd):
    # demo: peaks every 260 units from -2600..2600, heights 160..360, two-tone faces, solid base
    peaks = []
    x = -2600
    while x <= 2600:
        peaks.append((x, rnd.uniform(160, 360)))
        x += 260
    tiles = []
    tile_units = 1300
    bottom = -340  # fill below the base line (units)
    topu = 380
    ppu = 0.79
    for ti in range(4):
        ux0 = -2600 + ti * tile_units
        W = int(tile_units * ppu)
        H = int((topu - bottom) * ppu)
        img = canvas(W, H)
        d = ImageDraw.Draw(img)

        def tp(xu, hu):
            return ((xu - ux0) * ppu, (topu - hu) * ppu)

        poly(d, [tp(ux0 - 5, 0), tp(ux0 + tile_units + 5, 0), tp(ux0 + tile_units + 5, bottom), tp(ux0 - 5, bottom)], hexc("#7489b3") + (255,))
        for i in range(len(peaks) - 1):
            (x0, h0), (x1, _) = peaks[i], peaks[i + 1]
            mid = (x0 + x1) / 2
            poly(d, [tp(x0, 0), tp(mid, h0), tp(mid, 0)], hexc("#8fa4c8") + (255,))
            poly(d, [tp(mid, 0), tp(mid, h0), tp(x1, 0)], hexc("#7489b3") + (255,))
        name = f"mount_{ti + 1}.png"
        size = finish(img, name)
        tiles.append({"file": name, "px": size, "x0": ux0, "unitsW": tile_units, "top": topu, "bottom": bottom})
    return tiles


def main():
    rnd = random.Random(7)
    meta = {"clouds": []}
    for i in range(8):
        meta["clouds"].append(render_cloud(make_cloud(rnd), f"cloud_{i + 1}.png"))
    meta["planet"] = render_planet()
    meta["moon"] = render_moon()
    meta["earth"] = render_earth()
    meta["sunglow"] = render_sunglow()
    meta["mountains"] = render_mountains(random.Random(11))
    with open(os.path.join(OUT, "meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
    print(json.dumps(meta, indent=1))


if __name__ == "__main__":
    main()
