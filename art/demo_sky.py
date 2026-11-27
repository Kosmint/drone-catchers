"""Demo-style sky art (the approved Stage 0.5 flight demo look, ported to Roblox).

Everything is flat low-poly, drawn with the same shapes as the demo canvas code:
  cloud_N.png   faceted cloud in neutral shading (shade rim / base / highlight facets);
                tinted in game with ImageColor3 = the demo's per-altitude cloud colour
  planet.png    ringed planet (12 alternating wedges, dusky band, ring back + front)
  moon.png      small faceted moon
  earth_l/r.png top cap of the Earth: faceted low-poly globe (ocean, continents, ice, cloud
                bands) with the blue atmosphere rim, split in two tiles
  sunglow.png   soft radial sun glow
  mount_N.png   4 tiles of the far blue mountain range
Rendered at 4x and downsampled for clean anti-aliased edges.

Usage: python art/demo_sky.py         -> art/out/demo/*.png
       python art/demo_sky.py earth   -> only the Earth tiles (earth_l.png, earth_r.png)
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


# Earth: flat low-poly globe instead of the demo's 60 colour wedges (they read as a beach ball).
# The cap is the top of a sphere seen side-on (orthographic), so the shapes foreshorten toward
# the limb like a real planet. A lat/lon grid is cut into triangles; each triangle gets one flat
# colour (ocean / land / ice) lit by a fixed sun from the upper left = the faceted demo look.
# toned down: the Edge of Space colour correction adds ~+0.28 saturation in game
EARTH_OCEAN = [hexc("#336f9c"), hexc("#3877a3"), hexc("#3c7fa9")]
EARTH_LAND = [hexc("#5e9468"), hexc("#578c61"), hexc("#669c6e"), hexc("#b8aa82")]
EARTH_ICE = hexc("#e6f2f8")
# original, stylised continents as (lon, lat) outlines in degrees (not traced from any map)
EARTH_CONTINENTS = [
    [(-78, 38), (-70, 47), (-58, 55), (-46, 63), (-32, 61), (-24, 54), (-28, 45), (-40, 40), (-52, 34), (-66, 32)],
    [(4, 44), (12, 53), (24, 60), (38, 67), (54, 64), (66, 56), (72, 46), (60, 40), (44, 37), (30, 39), (16, 38)],
    [(-12, 66), (-4, 73), (8, 75), (14, 70), (6, 64), (-4, 62)],
    [(70, 66), (78, 72), (88, 70), (84, 64)],
    [(-90, 58), (-82, 64), (-74, 62), (-80, 56)],
]
EARTH_CLOUDS = [  # thin bands: (lon0, lon1, lat, half-thickness in degrees)
    (-88, -30, 47, 1.6), (-20, 40, 56, 1.3), (30, 86, 43, 1.5), (-60, 10, 69, 1.1), (50, 90, 61, 1.0),
]


def _inside(poly, x, y):
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c


def render_earth():
    # demo geometry kept: r = 1500 units, atmosphere rim r*0.98 -> r*1.06, top cap 720 units deep
    R = 1500.0
    cap = 720.0
    halfw = math.sqrt(R * R - (R - cap) ** 2) + 40
    rim = R * 1.06
    top = rim - R  # glow above the curve
    ppu = 0.75  # px per unit: about 2x the old art, split into two tiles (Roblox max 1024 px)
    W = int(2 * halfw * ppu) // 2 * 2
    H = int((cap + top) * ppu)
    cx, cy = W / 2, (R + top) * ppu
    rnd = random.Random(23)

    # 1. atmosphere glow (smooth, numpy) as the bottom layer
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / ppu
    t = np.clip((dist - R * 0.98) / (R * 0.08), 0, 1)
    glow_a = np.where(dist <= rim, 0.9 * (1 - t) ** 1.4, 0)
    glow = np.zeros((H, W, 4), np.float32)
    glow[..., :3] = np.array([120, 210, 255], np.float32)
    glow[..., 3] = glow_a * 255
    base = Image.fromarray(glow.astype(np.uint8), "RGBA")

    # 2. faceted globe (PIL, supersampled)
    globe = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(globe)
    light = np.array([-0.45, 0.62, 0.64])
    light /= np.linalg.norm(light)

    def proj(lon, lat):  # sphere point -> image px (supersampled) and its normal
        lo, la = math.radians(lon), math.radians(lat)
        n = np.array([math.cos(la) * math.sin(lo), math.sin(la), math.cos(la) * math.cos(lo)])
        return ((cx + n[0] * R * ppu) * SS, (cy - n[1] * R * ppu) * SS), n

    def shade(col, n):
        k = 0.9 + 0.16 * max(0.0, float(n @ light))
        return tuple(int(min(255, c * k)) for c in col) + (255,)

    # jittered lat/lon grid over the visible cap (lat >= 26, front hemisphere)
    lats = [26 + i * 4.0 for i in range(17)] + [90.0]
    lons = [-92 + j * 4.0 for j in range(47)]
    grid = {}
    for i, la in enumerate(lats):
        for j, lo in enumerate(lons):
            jl = 0 if la >= 90 else rnd.uniform(-1.1, 1.1)
            grid[(i, j)] = (lo + rnd.uniform(-1.2, 1.2), min(90.0, la + jl))
    for i in range(len(lats) - 1):
        for j in range(len(lons) - 1):
            a, b, c2, e = grid[(i, j)], grid[(i, j + 1)], grid[(i + 1, j + 1)], grid[(i + 1, j)]
            for tri in ((a, b, c2), (a, c2, e)):
                clon = sum(p[0] for p in tri) / 3
                clat = sum(p[1] for p in tri) / 3
                if True:
                    land = any(_inside(poly, clon, clat) for poly in EARTH_CONTINENTS)
                    if land:  # mostly greens, a few sandy facets
                        col = EARTH_LAND[3] if rnd.random() < 0.06 else EARTH_LAND[rnd.randrange(3)]
                    else:
                        col = EARTH_OCEAN[rnd.randrange(len(EARTH_OCEAN))]
                pts, normals = zip(*(proj(lo, la) for lo, la in tri))
                nrm = sum(normals) / 3
                d.polygon(list(pts), fill=shade(col, nrm))

    # polar ice: a smooth cap above lat 82 (bounded by the limb meridians), not jagged facets
    ice = [proj(lo, 82 + 1.2 * math.sin(lo * 0.21)) [0] for lo in range(-90, 91, 3)]
    ice += [proj(90, la)[0] for la in range(83, 91)] + [proj(-90, la)[0] for la in range(90, 82, -1)]
    d.polygon(ice, fill=shade(EARTH_ICE, np.array([0.0, 0.97, 0.24])))

    # cloud streaks: tapered, slightly wavy, two thin strands per band, semi-transparent
    cl = Image.new("RGBA", globe.size, (0, 0, 0, 0))
    dc = ImageDraw.Draw(cl)
    for lo0, lo1, la, hw in EARTH_CLOUDS:
        for strand in range(2):
            off = (strand - 0.5) * hw * 1.3
            a0 = lo0 + strand * (lo1 - lo0) * 0.18
            a1 = lo1 - (1 - strand) * (lo1 - lo0) * 0.15
            steps = max(4, int((a1 - a0) / 3))
            upper, lower = [], []
            for s in range(steps + 1):
                u = s / steps
                lo = a0 + (a1 - a0) * u
                w = hw * (0.75 - 0.25 * strand) * math.sin(math.pi * u) ** 0.8
                mid = la + off + 0.6 * math.sin(u * 7 + strand * 2)
                upper.append(proj(lo, mid + w)[0])
                lower.append(proj(lo, mid - w)[0])
            dc.polygon(upper + lower[::-1], fill=(248, 252, 255, 175))
    globe = Image.alpha_composite(globe, cl)

    # clip to the disc (anti-aliased limb) and add a thin bright limb line
    mask = Image.new("L", globe.size, 0)
    ImageDraw.Draw(mask).ellipse([(cx - R * ppu) * SS, (cy - R * ppu) * SS, (cx + R * ppu) * SS, (cy + R * ppu) * SS], fill=255)
    globe.putalpha(Image.fromarray(np.minimum(np.array(globe.getchannel("A")), np.array(mask))))
    limb = Image.new("RGBA", globe.size, (0, 0, 0, 0))
    lw = int(4 * SS)
    ImageDraw.Draw(limb).ellipse([(cx - R * ppu) * SS + lw / 2, (cy - R * ppu) * SS + lw / 2, (cx + R * ppu) * SS - lw / 2, (cy + R * ppu) * SS - lw / 2], outline=(170, 230, 255, 150), width=lw)
    globe = Image.alpha_composite(globe, limb)
    globe = globe.resize((W, H), Image.LANCZOS)

    img = Image.alpha_composite(base, globe)
    # two tiles side by side (each <= 1024 px wide for Roblox)
    half = W // 2
    files = []
    for k, name in enumerate(("earth_l.png", "earth_r.png")):
        img.crop((k * half, 0, (k + 1) * half, H)).save(os.path.join(OUT, name))
        files.append(name)
    img.save(os.path.join(OUT, "earth_preview.png"))
    return {"files": files, "px": [W, H], "tilePx": [half, H], "unitsW": 2 * halfw, "unitsH": cap + top, "topU": top}


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
    import sys
    if "earth" in sys.argv[1:]:
        # re-render only the Earth and update its entry in meta.json
        path = os.path.join(OUT, "meta.json")
        meta = json.load(open(path)) if os.path.exists(path) else {}
        meta["earth"] = render_earth()
        with open(path, "w") as f:
            json.dump(meta, f, indent=1)
        print(json.dumps(meta["earth"], indent=1))
        return
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
