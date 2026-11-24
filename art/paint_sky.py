"""
Drone Catchers - procedural painted sky & cloud layers (original art, generated).

Style target: soft painterly anime/Astroneer-like skies: luminous gradients, a glowing
sun with glare, layered cloud seas with sun-lit rims and lavender shadows, and
gentle cel-style colour steps.

Usage:  python art/paint_sky.py [names...]      (no names = paint everything)
Output: art/out/<name>.png  (max 1024 px on the long side, Roblox's upload limit)

Images are painted at 2x and downsampled for clean edges. Cloud layers tile in X.
"""
import os
import sys
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)

# --------------------------------------------------------------------------- helpers

def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def fbm(h, w, seed, beta=2.2, ax=1.0, ay=1.0, lo=1.5):
    """Periodic (tileable) fractal noise via spectral synthesis. ax>ay stretches features in X."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((h, w))
    fy = np.fft.fftfreq(h)[:, None] * h
    fx = np.fft.fftfreq(w)[None, :] * w
    k = np.sqrt((fx * ax) ** 2 + (fy * ay) ** 2)
    k[0, 0] = 1.0
    amp = 1.0 / np.maximum(k, lo) ** (beta / 2 + 0.5)
    amp[0, 0] = 0.0
    n = np.real(np.fft.ifft2(np.fft.fft2(white) * amp))
    n -= n.min()
    n /= max(n.max(), 1e-6)
    return n.astype(np.float32)


def ramp(t, stops):
    """Map t (0..1) through colour stops [(pos, rgb), ...]."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,), np.float32)
    pos = [s[0] for s in stops]
    cols = [s[1] for s in stops]
    for i in range(len(stops) - 1):
        a, b = pos[i], pos[i + 1]
        m = (t >= a) & (t <= b)
        f = ((t[m] - a) / max(b - a, 1e-6))[:, None]
        out[m] = cols[i] * (1 - f) + cols[i + 1] * f
    out[t < pos[0]] = cols[0]
    out[t > pos[-1]] = cols[-1]
    return out


def painterly_steps(t, levels, noise, jitter=0.06, soft=0.35):
    """Quantise t into soft cel bands with organic (noisy) band edges."""
    tj = np.clip(t + (noise - 0.5) * jitter, 0, 1) * levels
    base = np.floor(tj)
    frac = tj - base
    frac = smoothstep(0.5 - soft / 2, 0.5 + soft / 2, frac)
    return np.clip((base + frac) / levels, 0, 1)


def save(name, rgb, alpha=None, size=None):
    rgb = np.clip(rgb, 0, 1)
    if alpha is None:
        img = Image.fromarray((rgb * 255).astype(np.uint8), "RGB")
    else:
        a = np.clip(alpha, 0, 1)
        # transparent padding rows: tiled textures wrap when filtered, so an opaque bottom
        # row would bleed into the top edge as a thin line (and vice versa)
        hh = a.shape[0]
        v = np.arange(hh, dtype=np.float32)[:, None] / hh
        a = a * smoothstep(0.0, 0.025, v) * smoothstep(1.0, 0.985, v)
        img = Image.fromarray((np.dstack([rgb, a[..., None]]) * 255).astype(np.uint8), "RGBA")
    if size:
        img = img.resize(size, Image.LANCZOS)
    path = os.path.join(OUT, name + ".png")
    img.save(path, optimize=True)
    print("saved", path, img.size)


def blob_field(h, w, blobs, wrap=True):
    """Sum of soft round billows. blobs: list of (x, y, r, strength). Wraps in X."""
    f = np.zeros((h, w), np.float32)
    for (bx, by, r, s) in blobs:
        rr = int(r * 2.2) + 2
        y0, y1 = max(0, int(by) - rr), min(h, int(by) + rr)
        if y1 <= y0:
            continue
        ys = np.arange(y0, y1, dtype=np.float32)[:, None]
        for ox in ((-w, 0, w) if wrap else (0,)):
            cx = bx + ox
            x0, x1 = max(0, int(cx) - rr), min(w, int(cx) + rr)
            if x1 <= x0:
                continue
            xs = np.arange(x0, x1, dtype=np.float32)[None, :]
            d2 = ((xs - cx) ** 2 + (ys - by) ** 2) / (r * r)
            f[y0:y1, x0:x1] += s * np.exp(-d2 * 1.6)
    return f


def shade_clouds(H, alpha, sun_xy, light_up=1.0, rim_w=0.08, sun_glow=0.35, seed=0):
    """Painterly light value 0..1 for a cloud height field H (higher = closer/thicker)."""
    h, w = H.shape
    Hs = gaussian_filter(H, 2.0)
    gy, gx = np.gradient(Hs)
    # light from the sun: above the clouds and slightly toward the sun's x
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    lx = np.clip((sun_xy[0] - xx) / w, -1, 1) * 0.6
    ly = -light_up
    nx, ny = -gx * 18, -gy * 18
    nz = np.ones_like(nx) * 1.0
    nl = np.sqrt(nx * nx + ny * ny + nz * nz)
    lz = 0.55
    ll = np.sqrt(lx * lx + ly * ly + lz * lz)
    diffuse = (nx * lx + ny * ly + nz * lz) / (nl * ll)
    diffuse = np.clip(diffuse * 0.5 + 0.5, 0, 1)
    # silver lining: thin band just inside the silhouette, strongest on top edges
    inner = gaussian_filter(alpha, 3.0)
    edge = np.clip((1 - inner) * alpha * 2.2, 0, 1)
    top = np.clip(-gaussian_filter(np.gradient(alpha, axis=0), 2.0) * 25, 0, 1)
    rim = edge * (0.35 + 0.65 * top)
    # overexposed glow near the sun (backlit translucency)
    d = np.sqrt(((xx - sun_xy[0]) / w) ** 2 + ((yy - sun_xy[1]) / h * 0.6) ** 2)
    glow = np.exp(-(d / sun_glow) ** 2)
    detail = fbm(h, w, seed + 7, beta=2.6, ax=2.5, ay=1.0)
    L = 0.55 * diffuse + 0.45 * rim + 0.35 * glow + 0.12 * (detail - 0.5)
    return np.clip(L, 0, 1), glow, detail


# --------------------------------------------------------------------------- palettes

PAL_DAY = [  # cloud light ramp: shadow -> mid -> light -> sun-lit highlight
    (0.00, hexc("6f6aa8")),
    (0.22, hexc("968cc9")),
    (0.42, hexc("c4b2dc")),
    (0.60, hexc("ecd6e6")),
    (0.78, hexc("fdeee9")),
    (0.90, hexc("fff7ee")),
    (1.00, hexc("ffe6c2")),
]

# --------------------------------------------------------------------------- paintings

def sky_low():
    """Day sky backdrop: deep blue top -> cyan -> pale horizon with warm band, sun + glare."""
    W, H = 2048, 896
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = yy / H
    hz = 0.47  # horizon line (fraction from top)
    sky = ramp(v / hz, [
        (0.00, hexc("2a55ad")),
        (0.35, hexc("3a7fd3")),
        (0.62, hexc("5ea9e6")),
        (0.84, hexc("a8d6f0")),
        (0.94, hexc("f2dccb")),
        (1.00, hexc("ffd2a8")),
    ])
    below = ramp((v - hz) / (1 - hz), [
        (0.0, hexc("ffe2c4")),
        (0.25, hexc("f1d6e6")),
        (1.0, hexc("cdbde6")),
    ])
    col = np.where((v < hz)[..., None], sky, below)
    sun = np.array([W * 0.58, H * (hz - 0.035)], np.float32)
    dx, dy = (xx - sun[0]) / W, (yy - sun[1]) / H
    r = np.sqrt(dx * dx + (dy * 0.55) ** 2)
    # warm horizon band, brightest under the sun
    band = np.exp(-((v - hz) / 0.035) ** 2) * (0.55 + 0.45 * np.exp(-(dx / 0.35) ** 2))
    col = col + band[..., None] * (hexc("ffd9a8") - col) * 0.75
    # pink-lilac haze bands left/right of the sun near the horizon
    haze = np.exp(-((v - (hz - 0.05)) / 0.04) ** 2) * (1 - np.exp(-(dx / 0.25) ** 2))
    col = col + haze[..., None] * (hexc("e9c3df") - col) * 0.25
    # high wisps (sun-lit cirrus), streaky
    wisp = fbm(H, W, 11, beta=2.4, ax=6.0, ay=1.0)
    wm = smoothstep(0.58, 0.8, wisp) * smoothstep(hz, hz - 0.28, v) * smoothstep(hz - 0.42, hz - 0.2, v)
    wcol = ramp(np.clip(1 - r * 2.2, 0, 1), [(0, hexc("dcd6f2")), (0.6, hexc("ffe9e0")), (1, hexc("fff6e6"))])
    col = col * (1 - wm[..., None] * 0.55) + wcol * wm[..., None] * 0.55
    # sun: core + bloom + halo
    # (the in-game camera sees only the middle ~60% of this image, so keep the halo tight)
    core = np.exp(-(r / 0.01) ** 2)
    bloom = np.exp(-(r / 0.045) ** 2) * 0.8
    halo = np.exp(-(r / 0.13) ** 2) * 0.3
    glare = (core + bloom + halo)[..., None]
    col = col + glare * (hexc("fffbf0") - col) * np.clip(glare, 0, 1)
    # vertical light pillar and a horizontal streak through the sun
    pillar = np.exp(-(dx / 0.0025) ** 2) * np.exp(-(np.abs(dy) / 0.32)) * 0.9
    pillar += np.exp(-(dx / 0.012) ** 2) * np.exp(-(np.abs(dy) / 0.22)) * 0.35
    streak = np.exp(-(dy / 0.006) ** 2) * np.exp(-(np.abs(dx) / 0.18)) * 0.6
    lines = np.clip(pillar + streak, 0, 1)[..., None]
    col = col + lines * (hexc("fffaf0") - col)
    # very soft brush grain
    grain = fbm(H, W, 3, beta=1.2) - 0.5
    col = col + grain[..., None] * 0.015
    save("sky_low", col, size=(1024, 448))


class LobePainter:
    """Paints cloud lobes back-to-front onto an RGBA canvas (premultiplied-free 'over').

    Each lobe: irregular soft ellipse (edge broken up by noise -> no circles),
    sphere-like shading lit from the sun side, a back-lit silver rim on the top edge,
    painterly colour steps, and optional distance haze.
    """

    def __init__(self, W, H, seed, palette, sun_xy, wrap=True):
        self.W, self.H = W, H
        self.col = np.zeros((H, W, 3), np.float32)
        self.alpha = np.zeros((H, W), np.float32)
        self.palette = palette
        self.sun = sun_xy
        self.wrap = wrap
        self.edge_noise = fbm(H, W, seed + 101, beta=2.0, ax=1.0, ay=1.0)
        self.fine = fbm(H, W, seed + 202, beta=1.4, ax=2.0, ay=1.0)
        self.brush = fbm(H, W, seed + 303, beta=1.9, ax=7.0, ay=1.0)

    def lobe(self, cx, cy, r, squash=0.62, haze=0.0, haze_col=None, light=1.0, rough=0.55):
        W, H = self.W, self.H
        ry = r * squash
        rr_x, rr_y = int(r * 1.35) + 2, int(ry * 1.35) + 2
        y0, y1 = max(0, int(cy) - rr_y), min(H, int(cy) + rr_y)
        if y1 <= y0:
            return
        for ox in ((-W, 0, W) if self.wrap else (0,)):
            x_c = cx + ox
            x0, x1 = max(0, int(x_c) - rr_x), min(W, int(x_c) + rr_x)
            if x1 <= x0:
                continue
            ys = np.arange(y0, y1, dtype=np.float32)[:, None]
            xs = np.arange(x0, x1, dtype=np.float32)[None, :]
            u = (xs - x_c) / r
            v = (ys - cy) / ry
            en = self.edge_noise[y0:y1, x0:x1]
            fn = self.fine[y0:y1, x0:x1]
            d = np.sqrt(u * u + v * v)
            # flatter bottom: lobes sit on the layer below
            d = np.where(v > 0, np.sqrt(u * u + (v * 1.35) ** 2), d)
            # break the outline: big lumps + fine fluff (relative to lobe size)
            d = d + (en - 0.5) * rough + (fn - 0.5) * rough * 0.6
            a = smoothstep(1.02, 0.8, d)
            if not a.any():
                continue
            nz = np.sqrt(np.clip(1 - np.clip(d, 0, 1) ** 2, 0, 1))
            # light: from above and toward the sun's x, slightly from behind
            lx = np.clip((self.sun[0] - x_c) / W, -1, 1) * 0.7
            L = np.array([lx, -1.0, 0.45], np.float32)
            L /= np.linalg.norm(L)
            diff = np.clip(u * L[0] + v * L[1] + nz * L[2], -1, 1) * 0.5 + 0.5
            rim = np.clip((1 - nz) ** 2.2 * np.clip(-v * 1.2 + 0.3, 0, 1), 0, 1)
            sd = np.sqrt(((x_c - self.sun[0]) / W) ** 2 + ((cy - self.sun[1]) / H * 0.6) ** 2)
            sunboost = np.exp(-(sd / 0.45) ** 2)
            val = (0.72 * diff + 0.5 * rim * (0.6 + 0.8 * sunboost)) * light + 0.18 * sunboost
            val = val + (self.brush[y0:y1, x0:x1] - 0.5) * 0.08
            val = painterly_steps(np.clip(val, 0, 1), 7, fn, jitter=0.12, soft=0.65)
            c = ramp(val, self.palette)
            if haze > 0:
                c = c * (1 - haze) + (haze_col if haze_col is not None else hexc("fbeee8")) * haze
            # proper (unpremultiplied) "over" so soft edges never blend toward black
            dst_a = self.alpha[y0:y1, x0:x1]
            out_a = a + dst_a * (1 - a)
            safe = np.maximum(out_a, 1e-5)[..., None]
            self.col[y0:y1, x0:x1] = (c * a[..., None] + self.col[y0:y1, x0:x1] * (dst_a * (1 - a))[..., None]) / safe
            self.alpha[y0:y1, x0:x1] = out_a

    def clump_union(self, rng, cx, cy, r, n, squash, haze=0.0, haze_col=None, light=1.0, rough=0.35):
        """One cloud mass shaded as a single surface: union height field of many lobes.
        Continuous light across lobes (creases, no separate bubbles); rim only on the outer edge."""
        W, H = self.W, self.H
        lobes = [(cx + (k - 1) * r * 0.7, cy + r * squash * 0.25, r * rng.uniform(0.7, 0.95), 0.0) for k in range(3)]
        for i in range(n):
            ang = rng.uniform(-np.pi * 0.95, -np.pi * 0.05)
            dist = rng.uniform(0.15, 1.0) * r
            lr = r * rng.uniform(0.3, 0.6)
            lobes.append((cx + np.cos(ang) * dist * 1.35, cy + np.sin(ang) * dist * squash, lr, rng.uniform(0, 0.3)))
        x0 = int(min(l[0] - l[2] * 1.3 for l in lobes)); x1 = int(max(l[0] + l[2] * 1.3 for l in lobes)) + 1
        y0 = int(min(l[1] - l[2] * squash * 1.3 for l in lobes)); y1 = int(max(l[1] + l[2] * squash * 1.3 for l in lobes)) + 1
        bw, bh = x1 - x0, y1 - y0
        ys = np.arange(y0, y1, dtype=np.float32)[:, None]
        xs = np.arange(x0, x1, dtype=np.float32)[None, :]
        Hf = np.full((bh, bw), -1.0, np.float32)
        # sample canvas-space noise (wrapping) for edge breakup
        yi = np.clip(np.arange(y0, y1), 0, H - 1)[:, None]
        xi = (np.arange(x0, x1) % W)[None, :]
        en = self.edge_noise[yi, xi]
        fn = self.fine[yi, xi]
        for (lx_, ly_, lr, lz) in lobes:
            u = (xs - lx_) / lr
            v = (ys - ly_) / (lr * squash)
            v = np.where(v > 0, v * 1.3, v)
            d2 = u * u + v * v
            h = np.sqrt(np.clip(1 - d2, 0, 1)) * lr + lz * r
            h = np.where(d2 < 1, h, -1)
            Hf = np.maximum(Hf, h)
        inside = (Hf > 0).astype(np.float32)
        # soft, broken edge from a blurred mask + noise
        m = gaussian_filter(inside, max(1.0, r * 0.06))
        m = m + (en - 0.5) * rough + (fn - 0.5) * rough * 0.5
        a = smoothstep(0.42, 0.62, m)
        Hs = gaussian_filter(np.maximum(Hf, 0), max(1.0, r * 0.05))
        gy, gx = np.gradient(Hs)
        nx_, ny_, nz_ = -gx, -gy, np.ones_like(gx) * 0.9
        nl = np.sqrt(nx_ ** 2 + ny_ ** 2 + nz_ ** 2)
        lxd = np.clip((self.sun[0] - cx) / W, -1, 1) * 0.7
        Lv = np.array([lxd, -1.0, 0.5], np.float32); Lv /= np.linalg.norm(Lv)
        diff = np.clip((nx_ * Lv[0] + ny_ * Lv[1] + nz_ * Lv[2]) / nl, -1, 1) * 0.5 + 0.5
        # crease shadows: where the union surface dips between lobes
        crease = np.clip((gaussian_filter(Hs, r * 0.12) - Hs) / (r * 0.08), 0, 1)
        # outer silver lining, strongest along the top edge
        inner = gaussian_filter(a, max(1.0, r * 0.05))
        edge = np.clip((1 - inner) * a * 2.4, 0, 1)
        topness = np.clip(-np.gradient(gaussian_filter(a, 2.0), axis=0) * r * 0.08, 0, 1)
        rim = edge * (0.3 + 0.7 * topness)
        sd = np.sqrt(((cx - self.sun[0]) / W) ** 2 + ((cy - self.sun[1]) / H * 0.6) ** 2)
        sunboost = np.exp(-(sd / 0.45) ** 2)
        val = (0.78 * diff - 0.35 * crease + 0.55 * rim * (0.6 + 0.8 * sunboost)) * light + 0.15 * sunboost
        val = val + (self.brush[yi, xi] - 0.5) * 0.08
        val = painterly_steps(np.clip(val, 0, 1), 7, fn, jitter=0.12, soft=0.65)
        c = ramp(val, self.palette)
        if haze > 0:
            c = c * (1 - haze) + (haze_col if haze_col is not None else hexc("fbeee8")) * haze
        # composite (clip to canvas, wrap in X)
        cy0, cy1 = max(0, y0), min(H, y1)
        if cy1 <= cy0:
            return
        sy0, sy1 = cy0 - y0, cy1 - y0
        for ox in (-W, 0, W):
            dx0, dx1 = max(0, x0 + ox), min(W, x1 + ox)
            if dx1 <= dx0:
                continue
            sx0, sx1 = dx0 - (x0 + ox), dx1 - (x0 + ox)
            aa = a[sy0:sy1, sx0:sx1]
            cc = c[sy0:sy1, sx0:sx1]
            dst_a = self.alpha[cy0:cy1, dx0:dx1]
            out_a = aa + dst_a * (1 - aa)
            safe = np.maximum(out_a, 1e-5)[..., None]
            self.col[cy0:cy1, dx0:dx1] = (cc * aa[..., None] + self.col[cy0:cy1, dx0:dx1] * (dst_a * (1 - aa))[..., None]) / safe
            self.alpha[cy0:cy1, dx0:dx1] = out_a

    def clump(self, rng, cx, cy, r, n, squash, haze, haze_col=None, spread=1.0):
        """A cloud mass: big lobes at the back/bottom, smaller ones piling on top."""
        lobes = []
        for i in range(n):
            ang = rng.uniform(-np.pi, 0)  # upper half
            dist = rng.uniform(0.2, 0.95) * r * spread
            lr = r * rng.uniform(0.22, 0.55)  # many smaller lobes = cauliflower, not bubbles
            lobes.append((cx + np.cos(ang) * dist * 1.4, cy + np.sin(ang) * dist * squash, lr))
        # wide base lobes first (they are behind), then upper lobes
        for k in range(3):
            self.lobe(cx + (k - 1) * r * 0.75 + rng.uniform(-0.1, 0.1) * r, cy + r * squash * 0.15,
                      r * rng.uniform(0.8, 1.05), squash * 0.8, haze, haze_col)
        lobes.sort(key=lambda l: (l[1], -l[2]))  # top first, so lower/front lobes overlap them
        for (x, y, lr) in lobes:
            self.lobe(x, y, lr, squash, haze, haze_col)


def sea_painted(seed, W, H, rows, r_range, top_frac, sun_xy, palette, squash, haze_far, clump_n, gap=0.25):
    """Rows of cloud clumps receding to the horizon (top) - painted back-to-front."""
    rng = np.random.default_rng(seed)
    P = LobePainter(W, H, seed, palette, sun_xy)
    haze_col = hexc("fbeadf")
    for i in range(rows):
        t = i / max(rows - 1, 1)  # 0 = far row (top), 1 = near row (bottom)
        y = H * (top_frac + (1 - top_frac) * (t ** 1.25))
        r = r_range[0] + (r_range[1] - r_range[0]) * (t ** 1.1)
        n = max(2, int(W / (r * 2.1)))
        xs = (np.arange(n) + rng.uniform(-0.45, 0.45, n)) * W / n + rng.uniform(0, W / n)
        for x in xs:
            if rng.uniform() < gap and i < rows - 1:
                continue  # gaps between clumps let the layer behind show through
            haze = haze_far * (1 - t) ** 1.5
            # rows are not lines: scatter clumps up/down by up to half a row
            jitter = rng.uniform(-0.5, 0.5) * (H * (1 - top_frac) / rows)
            size = r * rng.choice([0.6, 0.85, 1.0, 1.3, 1.6], p=[0.2, 0.3, 0.25, 0.17, 0.08])
            P.clump(rng, x % W, y + jitter, size, clump_n, squash, haze, haze_col)
    return P


def sea_layer(name, seed, W, H, rows, r_range, top_frac, sun_xy, palette, squash=0.55, detail_amp=0.18, wisp=0.0):
    """A tileable band of a cloud sea seen at a grazing angle (rows of billows)."""
    rng = np.random.default_rng(seed)
    blobs = []
    for i in range(rows):
        t = i / max(rows - 1, 1)  # 0 = back row (top), 1 = front row (bottom)
        y = H * (top_frac + (1 - top_frac) * (t ** 1.15)) + rng.uniform(-6, 6)
        r = r_range[0] + (r_range[1] - r_range[0]) * t
        n = int(W / (r * 1.1)) + 2
        for k in range(n):
            x = (k + rng.uniform(-0.35, 0.35)) * W / n
            rr = r * rng.uniform(0.7, 1.25)
            blobs.append((x, y - rr * 0.15, rr, rng.uniform(0.85, 1.15)))
    F = blob_field(H, W, blobs)
    # squash billows vertically (seen from a low angle) by sampling stretched
    F = gaussian_filter(F, (1.0, 1.0))
    det = fbm(H, W, seed + 1, beta=2.3, ax=3.0, ay=1.0)
    Hh = F + (det - 0.5) * detail_amp * F.max()
    thr = 0.55 * np.percentile(Hh, 70)
    alpha = smoothstep(thr * 0.85, thr * 1.15, Hh)
    # fade the far edge into haze
    yy = np.mgrid[0:H, 0:W][0].astype(np.float32) / H
    alpha *= smoothstep(top_frac - 0.12, top_frac + 0.15, yy) if top_frac > 0.02 else 1.0
    if wisp > 0:
        wn = fbm(H, W, seed + 3, beta=2.0, ax=8.0, ay=1.0)
        alpha = np.clip(alpha + smoothstep(0.6, 0.85, wn) * wisp * smoothstep(top_frac - 0.2, top_frac, yy), 0, 1)
    L, glow, d2 = shade_clouds(Hh / max(Hh.max(), 1e-6), alpha, sun_xy, seed=seed)
    Lp = painterly_steps(L, 6, d2, jitter=0.08, soft=0.45)
    col = ramp(Lp, palette)
    # brush streaks + haze toward the far edge
    streak = fbm(H, W, seed + 5, beta=1.8, ax=10.0, ay=1.0) - 0.5
    col = col + streak[..., None] * 0.04
    farhaze = smoothstep(top_frac + 0.35, top_frac, yy)[..., None]
    col = col * (1 - farhaze * 0.45) + hexc("fbeee8") * farhaze * 0.45
    return col, alpha


def rolling_sheet(seed, W, H, top_frac, rows, sun_xy, palette, haze_top=0.65, wisp=0.5, warp=2.2, billow_r=0.0):
    """Continuous cloud sea seen at a grazing angle: wavy rolls, lit ridge tops, lilac troughs.
    Returns (rgb, alpha)."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = yy / H
    z = np.clip((v - top_frac) / (1 - top_frac), 0, 1)            # 0 at the far edge, 1 at the bottom
    p = z ** 1.55                                                     # perspective: rolls grow toward us
    w1 = fbm(H, W, seed, beta=2.4, ax=4.0, ay=1.0)                    # wavy rows
    w2 = fbm(H, W, seed + 1, beta=2.0, ax=1.5, ay=1.0)                # lumpiness
    phase = p * rows + (w1 - 0.5) * warp + (w2 - 0.5) * 0.6
    s = phase - np.floor(phase)                                       # 0 = ridge top, 1 = trough
    # light: ridge tops bright, falling into shadow toward the next ridge (soft sawtooth)
    lit = 1 - smoothstep(0.0, 0.7, s)
    lit = lit * 0.8 + 0.2 * smoothstep(0.88, 1.0, s)                 # back-lit lip just before the next ridge
    lump = fbm(H, W, seed + 2, beta=2.6, ax=1.2, ay=1.0)
    lit = np.clip(lit * (0.75 + 0.5 * lump), 0, 1)
    d = np.sqrt(((xx - sun_xy[0]) / W) ** 2 + ((yy - sun_xy[1]) / H * 0.5) ** 2)
    sunboost = np.exp(-(d / 0.3) ** 2)
    val = np.clip(0.05 + 0.85 * lit + 0.2 * sunboost * (1 - z * 0.6), 0, 1)
    val = painterly_steps(val, 7, lump, jitter=0.12, soft=0.6)
    col = ramp(val, palette)
    # distance haze: far rows melt into the bright horizon
    hz = (1 - z) ** 2.2 * haze_top
    hzcol = ramp(np.clip(1 - d * 1.6, 0, 1), [(0, hexc("efd6e8")), (0.6, hexc("ffe9dc")), (1, hexc("fff3e0"))])
    col = col * (1 - hz[..., None]) + hzcol * hz[..., None]
    # top edge: ragged, with wispy streaks above it
    edge = top_frac + (lump - 0.5) * 0.05 + (w1 - 0.5) * 0.04
    alpha = smoothstep(edge - 0.01, edge + 0.04, v)
    if billow_r > 0:
        # billowy silhouette: a chain of soft cloud bumps along the top edge (wraps in X)
        rng = np.random.default_rng(seed + 9)
        blobs, x = [], 0.0
        while x < W:
            r = billow_r * rng.uniform(0.55, 1.35)
            blobs.append((x, H * top_frac + r * rng.uniform(0.25, 0.75), r, 1.0))
            if rng.uniform() < 0.55:  # small bumps on top of big ones
                blobs.append((x + rng.uniform(-0.4, 0.4) * r, H * top_frac + r * 0.1, r * rng.uniform(0.35, 0.6), 1.0))
            x += r * rng.uniform(0.9, 1.5)
        B = blob_field(H, W, blobs)
        B = B + (fbm(H, W, seed + 10, beta=1.6) - 0.5) * 0.35
        bmask = smoothstep(0.35, 0.55, B)
        alpha = np.maximum(alpha, bmask)
        # light the bumps: bright tops (silver lining), shadowed undersides
        gyb = np.gradient(gaussian_filter(B, billow_r * 0.12), axis=0)
        # image y grows downward: on a bump's top edge B increases with y (gyb > 0)
        top_lit = np.clip(gyb * billow_r * 1.4, 0, 1)
        rim = np.clip((1 - gaussian_filter(bmask, billow_r * 0.06)) * bmask * 2.5, 0, 1) * (0.4 + 0.6 * top_lit)
        under = np.clip(-gyb * billow_r * 1.2, 0, 1) * bmask
        lumpy = fbm(H, W, seed + 11, beta=2.2, ax=1.3, ay=1.0)
        bval = np.clip(0.46 + 0.3 * top_lit - 0.16 * under + 0.32 * rim + 0.2 * sunboost + (lumpy - 0.5) * 0.35, 0, 0.9)
        bval = painterly_steps(bval, 7, lump, jitter=0.14, soft=0.65)
        bcol = ramp(bval, palette)
        wgt = (bmask * smoothstep(top_frac + 0.3, top_frac + 0.04, v))[..., None]
        col = col * (1 - wgt) + bcol * wgt
    if wisp > 0:
        ws = fbm(H, W, seed + 3, beta=2.0, ax=9.0, ay=1.0)
        alpha = np.maximum(alpha, smoothstep(0.62, 0.86, ws) * wisp * smoothstep(edge - 0.12, edge, v))
    grain = fbm(H, W, seed + 4, beta=1.7, ax=8.0) - 0.5
    col = np.clip(col + grain[..., None] * 0.03, 0, 1)
    return col, alpha


def finish_layer(P, top_frac, solid_bottom=True):
    """Fill the base under the clumps (it is a sea, not floating clouds) and add brush grain."""
    H, W = P.alpha.shape
    yy = np.mgrid[0:H, 0:W][0].astype(np.float32) / H
    if solid_bottom:
        under = smoothstep(top_frac + 0.25, top_frac + 0.55, yy)
        base = ramp(np.full((H, W), 0.42, np.float32), P.palette)
        a = under * (1 - P.alpha)
        P.col = P.col * (1 - a[..., None]) + base * a[..., None]
        P.alpha = np.clip(P.alpha + a, 0, 1)
    grain = fbm(H, W, 909, beta=1.6, ax=6.0) - 0.5
    P.col = np.clip(P.col + grain[..., None] * 0.025, 0, 1)
    return P.col, P.alpha


def overlay_clumps(base_col, base_a, seed, W, H, sun_xy, palette, count, y_range, r_range, squash, haze, clump_n):
    """Paint a few cloud clumps rising out of a sheet (back to front by y)."""
    rng = np.random.default_rng(seed)
    P = LobePainter(W, H, seed, palette, sun_xy)
    P.col, P.alpha = base_col.copy(), base_a.copy()
    items = []
    for _ in range(count):
        y = rng.uniform(*y_range) * H
        t = (y / H - y_range[0]) / max(y_range[1] - y_range[0], 1e-6)
        items.append((y, rng.uniform(0, W), (r_range[0] + (r_range[1] - r_range[0]) * t) * rng.uniform(0.7, 1.3), t))
    items.sort()
    for (y, x, r, t) in items:
        P.clump_union(rng, x, y, r, clump_n, squash, haze * (1 - t), hexc("fbeadf"))
    return P.col, P.alpha


def sea_far():
    W, H = 2048, 512
    sun = (W * 0.58, -H * 0.35)
    col, a = rolling_sheet(21, W, H, top_frac=0.12, rows=9, sun_xy=sun, palette=PAL_DAY, haze_top=0.75, wisp=0.55)
    save("sea_far", col, a, size=(1024, 256))


def sea_mid():
    W, H = 2048, 640
    sun = (W * 0.58, -H * 0.8)
    col, a = rolling_sheet(33, W, H, top_frac=0.2, rows=5, sun_xy=sun, palette=PAL_DAY, haze_top=0.4, wisp=0.35,
                           warp=2.8, billow_r=26)
    save("sea_mid", col, a, size=(1024, 320))


def sea_near():
    W, H = 2048, 768
    sun = (W * 0.58, -H * 1.2)
    col, a = rolling_sheet(47, W, H, top_frac=0.22, rows=4, sun_xy=sun, palette=PAL_DAY, haze_top=0.2, wisp=0.0,
                           warp=3.2, billow_r=58)
    save("sea_near", col, a, size=(1024, 384))


def star_sprites():
    """White sprites (tinted in-engine): a 4-point glint with thin diagonal rays, and a soft star dot."""
    N = 512
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    x, y = (xx - N / 2) / (N / 2), (yy - N / 2) / (N / 2)
    r = np.sqrt(x * x + y * y)
    core = np.exp(-(r / 0.05) ** 2)
    halo = np.exp(-(r / 0.22) ** 2) * 0.45
    ray = lambda a, b, w: np.exp(-(np.abs(a) / w) ** 2) * np.exp(-np.abs(b) / 0.42)
    cross = ray(x, y, 0.018) + ray(y, x, 0.018)
    u, v = (x + y) / np.sqrt(2), (x - y) / np.sqrt(2)
    diag = (ray(u, v, 0.012) + ray(v, u, 0.012)) * 0.35 * np.exp(-r / 0.25)
    a = np.clip(core + halo + cross + diag, 0, 1) * smoothstep(1.0, 0.85, r)
    save("star_glint", np.ones((N, N, 3), np.float32), a, size=(256, 256))
    dot = np.clip(np.exp(-(r / 0.09) ** 2) + np.exp(-(r / 0.3) ** 2) * 0.35 + cross * 0.25, 0, 1) * smoothstep(1.0, 0.8, r)
    save("star_dot", np.ones((N, N, 3), np.float32), dot, size=(128, 128))


PAINTINGS = {
    "stars": star_sprites,
    "sky_low": sky_low,
    "sea_far": sea_far,
    "sea_mid": sea_mid,
    "sea_near": sea_near,
}

if __name__ == "__main__":
    names = sys.argv[1:] or list(PAINTINGS)
    for n in names:
        PAINTINGS[n]()
