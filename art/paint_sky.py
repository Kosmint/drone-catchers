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
            # clusters of 2-6 bumps with uneven heights, separated by low gaps
            k = rng.integers(2, 7)
            lift = rng.uniform(0.0, 1.0) ** 2  # most clusters low, a few tall
            for j in range(k):
                r = billow_r * rng.uniform(0.55, 1.3) * (0.8 + 0.6 * lift)
                hump = np.sin((j + 0.5) / k * np.pi)  # tallest in the middle of a cluster
                yb = H * top_frac + r * (0.9 - 0.7 * hump * lift) + billow_r * (1 - lift) * 0.6
                blobs.append((x, yb, r, 1.0))
                if rng.uniform() < 0.5:
                    blobs.append((x + rng.uniform(-0.4, 0.4) * r, yb - r * 0.55, r * rng.uniform(0.35, 0.6), 1.0))
                x += r * rng.uniform(0.7, 1.2)
            x += billow_r * rng.uniform(0.5, 3.0)  # gap
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


def sea_bands(n=10):
    """The cloud sea as N thin parallax bands (far -> near). Each band: billowy top edge, opaque
    down past the bottom of the screen, rolls sized for its distance. Writes art/out/bands.json
    with the card layout (Roblox studs) so the build script places them exactly."""
    import json
    TAN = 0.6306           # 2*tan(FOV/2) for FOV 35
    PLANE_DIST = 98        # camera -> flight plane
    SCREEN_BOTTOM = 0.595  # screen bottom below the horizon (fraction of view height)
    layout = []
    for i in range(n):
        t = i / (n - 1)
        z = -880 + 460 * t                       # depth behind the flight plane
        dist = PLANE_DIST - z
        hv = dist * TAN                          # visible height (studs) at that depth
        s = 0.01 + 0.43 * t ** 2.1               # top edge below the horizon (screen fraction)
        top_frac = 0.1
        card_h = (SCREEN_BOTTOM + 0.1 - s) * hv / (1 - top_frac)
        card_w = min(2040, hv * 3.2)
        tile_w = card_w / 2
        center = -s * hv + top_frac * card_h - card_h / 2
        layout.append({
            "name": "Band%02d" % (i + 1), "z": round(z, 1), "w": round(card_w, 1), "h": round(card_h, 1),
            "tileW": round(tile_w, 1), "offY": round(center, 2),
            "kX": round(0.04 + 0.36 * t ** 1.3, 3), "kY": round(0.08 + 0.92 * t ** 1.3, 3),
        })
        # image: one tile, aspect tile_w : card_h
        W = 2048
        H = int(W * card_h / tile_w) // 2 * 2
        H = max(H, 256)
        sun = (W * 0.58, -H * (0.3 + 1.2 * t))
        col, a = rolling_sheet(500 + i * 7, W, H, top_frac=top_frac, rows=int(3 + 3 * (1 - t)),
                               sun_xy=sun, palette=PAL_DAY, haze_top=0.75 * (1 - t) ** 1.4 + 0.08,
                               wisp=0.45 * (1 - t), warp=2.2 + t,
                               billow_r=(W * (0.012 + 0.02 * t)) if t > 0.35 else 0.0)
        # far bands melt into the bright horizon haze (only near bands keep full contrast)
        haze = 0.7 * (1 - t) ** 1.6
        col = col * (1 - haze) + hexc("fbe9dd") * haze
        out_h = max(128, int(1024 * H / W))
        save("band%02d" % (i + 1), col, a, size=(1024, out_h))
    with open(os.path.join(OUT, "bands.json"), "w") as f:
        json.dump(layout, f, indent=1)
    print(json.dumps(layout))


def float_clouds(n=5):
    """Standalone floating cumulus clusters (same painterly billow shading as the sea bands),
    soft wispy undersides; placed in the play space as world-fixed cards."""
    for k in range(n):
        rng = np.random.default_rng(900 + k)
        W, H = 2048, 1152
        blobs = []
        # flat-ish base row
        cx0 = W * 0.5
        span = W * rng.uniform(0.55, 0.75)
        nb = rng.integers(5, 8)
        for j in range(nb):
            x = cx0 - span / 2 + span * (j + 0.5) / nb + rng.uniform(-40, 40)
            r = W * rng.uniform(0.07, 0.1)
            blobs.append((x, H * 0.64, r, 1.0))
        # dome of billows, tallest near the middle
        for j in range(rng.integers(9, 15)):
            u = rng.uniform(-1, 1)
            x = cx0 + u * span * 0.45
            hump = 1 - abs(u) ** 1.5
            r = W * rng.uniform(0.06, 0.11) * (0.7 + 0.5 * hump)
            y = H * 0.64 - hump * H * rng.uniform(0.18, 0.36)
            blobs.append((x, y, r, 1.0))
        B0 = blob_field(H, W, blobs, wrap=False)
        m0 = B0 > 0.45
        # cauliflower: small sub-billows sitting on the upper silhouette
        edge = m0 & ~np.roll(m0, 6, axis=0)  # pixels whose neighbour above is outside
        ey, ex = np.nonzero(edge)
        sub = []
        if len(ey):
            for idx in rng.choice(len(ey), size=min(70, len(ey)), replace=False):
                r = W * rng.uniform(0.018, 0.045)
                sub.append((ex[idx], ey[idx] + r * 0.45, r, 0.9))
        B = B0 + blob_field(H, W, sub, wrap=False)
        B = B + (fbm(H, W, 950 + k, beta=1.6) - 0.5) * 0.2
        mask = smoothstep(0.42, 0.52, B)
        yy = np.mgrid[0:H, 0:W][0].astype(np.float32) / H
        # wispy, fading underside
        wisp = fbm(H, W, 960 + k, beta=2.0, ax=5.0)
        mask = mask * np.clip(smoothstep(0.78, 0.62, yy) + (wisp - 0.5) * 0.6, 0, 1)
        r0 = W * 0.05
        # large-scale light from the smoothed mass; small billows only show in the rim
        Bs = gaussian_filter(B, r0 * 0.5)
        gy = np.gradient(Bs, axis=0)
        top_lit = np.clip(gy * r0 * 3.0, 0, 1)
        under = np.clip(-gy * r0 * 2.0, 0, 1)
        rim = np.clip((1 - gaussian_filter(mask, r0 * 0.08)) * mask * 2.5, 0, 1) * (0.45 + 0.55 * top_lit)
        lumpy = fbm(H, W, 970 + k, beta=2.4, ax=1.3)
        val = np.clip(0.52 + 0.3 * top_lit - 0.1 * under + 0.32 * rim + (lumpy - 0.5) * 0.18
                      - 0.22 * smoothstep(0.42, 0.75, yy), 0, 0.92)
        val = painterly_steps(val, 7, lumpy, jitter=0.14, soft=0.65)
        col = ramp(val, PAL_DAY)
        save("cloud%02d" % (k + 1), col, mask, size=(1024, 576))


# --------------------------------------------------------------------------- storm layer (sunset)

PAL_STORM_BODY = [
    (0.00, hexc("1b1f45")), (0.3, hexc("2a3063")), (0.55, hexc("3d3f7c")), (0.8, hexc("5a4f8e")), (1.0, hexc("7a5f98")),
]
PAL_STORM_RIM = [(0.0, hexc("c65a8a")), (0.45, hexc("ff8a5c")), (0.8, hexc("ffc07a")), (1.0, hexc("fff0c8"))]
STORM_SUN = (0.38, 0.62)  # sun position in the storm backdrop (fractions), low on the horizon


def sky_storm():
    W, H = 2048, 896
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = yy / H
    hz = 0.62
    col = ramp(v / hz, [
        (0.00, hexc("1c1d4d")), (0.3, hexc("3a2f74")), (0.55, hexc("8a4a8f")),
        (0.75, hexc("e26a7e")), (0.9, hexc("ff9e5e")), (1.0, hexc("ffcf7a")),
    ])
    below = ramp((v - hz) / (1 - hz), [(0, hexc("ffc276")), (0.3, hexc("c86a7a")), (1, hexc("3a2c5e"))])
    col = np.where((v < hz)[..., None], col, below)
    sx, sy = W * STORM_SUN[0], H * STORM_SUN[1]
    dx, dy = (xx - sx) / W, (yy - sy) / H
    r = np.sqrt(dx * dx + (dy * 0.6) ** 2)
    glow = np.exp(-(r / 0.04) ** 2) + np.exp(-(r / 0.14) ** 2) * 0.6 + np.exp(-(r / 0.4) ** 2) * 0.35
    col = col + np.clip(glow, 0, 1)[..., None] * (hexc("fff1cf") - col) * np.clip(glow, 0, 1)[..., None]
    # horizontal streaks of lit cloud in the glow (like sunset cirrus)
    st = fbm(H, W, 71, beta=2.4, ax=9.0)
    sm = smoothstep(0.6, 0.8, st) * smoothstep(hz - 0.32, hz - 0.12, v) * smoothstep(hz + 0.02, hz - 0.06, v)
    scol = ramp(np.clip(1 - r * 2.2, 0, 1), [(0, hexc("b85a86")), (0.5, hexc("ff9a6a")), (1, hexc("ffe0a0"))])
    col = col * (1 - sm[..., None] * 0.7) + scol * sm[..., None] * 0.7
    col = col + (fbm(H, W, 72, beta=1.2) - 0.5)[..., None] * 0.015
    save("sky_storm", col, size=(1024, 448))


def storm_towers(name, seed, W, H, towers, base_frac, height_rng, width_rng, haze, rim_gain, sun_x_frac):
    """Cumulonimbus towers with anvil tops, dark blue bodies, sunset rims (tileable in X)."""
    rng = np.random.default_rng(seed)
    blobs = []
    for i in range(towers):
        x = (i + rng.uniform(0.1, 0.9)) * W / towers
        tw = W * rng.uniform(*width_rng)
        th = H * rng.uniform(*height_rng)
        base_y = H * base_frac
        lean = rng.uniform(0.05, 0.2) * tw
        # cumulonimbus profile: width (fraction of tw) along the height t=0 (base) .. 1 (anvil top)
        def width_at(t):
            body = 1.0 + 0.25 * np.sin(t * np.pi * 0.9)        # bulging body
            neck = 1 - 0.25 * np.exp(-((t - 0.78) / 0.06) ** 2)  # slight neck under the anvil
            anvil = 1 + 0.9 * smoothstep(0.8, 0.95, t)          # wide flat anvil
            return body * neck * anvil
        step = tw * 0.1
        n_levels = max(4, int(th / step))
        for j in range(n_levels + 1):
            t = j / n_levels
            wdt = tw * width_at(t) * rng.uniform(0.75, 1.2)          # wobbly sides
            cx = x + lean * t + (0.35 * tw * smoothstep(0.8, 1.0, t)) + rng.uniform(-0.08, 0.08) * tw
            k = max(2, int(wdt / (tw * 0.22)))
            anvil = t > 0.85
            for q in range(k):
                bx = cx - wdt / 2 + wdt * (q + 0.5) / k + rng.uniform(-0.06, 0.06) * tw
                r = tw * rng.uniform(0.15, 0.25) * (0.55 if anvil else 1.0)
                by = base_y - t * th + (r * 0.5 if anvil else 0)       # thin, flat anvil
                blobs.append((bx, by, r, 1.0))
        # rounded cumulus dome where the body meets the anvil (not a flat mesa)
        for q in range(4):
            blobs.append((x + lean * 0.75 + rng.uniform(-0.3, 0.3) * tw, base_y - 0.8 * th + rng.uniform(-0.04, 0.02) * H,
                          tw * rng.uniform(0.18, 0.26), 1.0))
    for _ in range(towers * 6):  # low lumpy clouds between towers
        blobs.append((rng.uniform(0, W), H * base_frac + rng.uniform(0.0, 0.08) * H, W * rng.uniform(0.03, 0.06), 1.0))
    B0 = blob_field(H, W, blobs)
    m0 = B0 > 0.45
    # billows on every edge (top + both sides), pushed slightly inward
    sub = []
    for shift, axis, dx_, dy_ in ((6, 0, 0, 0.4), (6, 1, 0.4, 0), (-6, 1, -0.4, 0)):
        edge = m0 & ~np.roll(m0, shift, axis=axis)
        ey, ex = np.nonzero(edge)
        if len(ey) == 0:
            continue
        for idx in rng.choice(len(ey), size=min(130, len(ey)), replace=False):
            r = W * rng.uniform(0.008, 0.024)
            sub.append((ex[idx] + r * dx_, ey[idx] + r * dy_, r, 0.9))
    # inner bulges so the mass reads as heaped billows
    iy, ix = np.nonzero(m0[:: 8, :: 8])
    if len(iy):
        for idx in rng.choice(len(iy), size=min(120, len(iy)), replace=False):
            sub.append((ix[idx] * 8, iy[idx] * 8, W * rng.uniform(0.015, 0.035), 0.5))
    B = B0 + blob_field(H, W, sub) + (fbm(H, W, seed + 1, beta=1.6) - 0.5) * 0.2
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = yy / H
    mask = smoothstep(0.42, 0.52, B) * smoothstep(1.0, 0.97, v) + smoothstep(base_frac + 0.05, base_frac + 0.12, v)
    mask = np.clip(mask, 0, 1)
    # outward normal of the silhouette -> rim where it faces the low sun (behind, at sun_x)
    ms = gaussian_filter(mask, 4.0)
    gy, gx = np.gradient(ms)
    nl = np.sqrt(gx * gx + gy * gy) + 1e-6
    nxo, nyo = -gx / nl, -gy / nl
    sdx, sdy = (W * sun_x_frac - xx), (H * 0.95 - yy)
    sl = np.sqrt(sdx * sdx + sdy * sdy) + 1e-6
    facing = np.clip((nxo * sdx / sl + nyo * sdy / sl) * 0.6 + 0.55, 0, 1)
    edge_band = np.clip((1 - gaussian_filter(mask, 7.0)) * mask * 2.6, 0, 1)
    rim = np.clip(edge_band * (0.35 + 0.65 * facing) * rim_gain, 0, 1)
    # body: darker toward the bottom, billow light from the smoothed mass
    Bs = gaussian_filter(B, 10)
    top_lit = np.clip(np.gradient(Bs, axis=0) * 40, 0, 1)
    lump = fbm(H, W, seed + 2, beta=2.3, ax=1.3)
    body_v = np.clip(0.35 + 0.35 * top_lit + (lump - 0.5) * 0.3 - 0.35 * smoothstep(0.3, 1.0, v), 0, 1)
    body_v = painterly_steps(body_v, 6, lump, jitter=0.12, soft=0.6)
    col = ramp(body_v, PAL_STORM_BODY)
    rcol = ramp(painterly_steps(rim, 5, lump, jitter=0.1, soft=0.5), PAL_STORM_RIM)
    rw = np.clip(rim * 1.4, 0, 1)[..., None]
    col = col * (1 - rw) + rcol * rw
    # aerial haze toward the sunset
    col = col * (1 - haze) + hexc("b9658c") * haze
    col = col + (fbm(H, W, seed + 3, beta=1.7, ax=6.0) - 0.5)[..., None] * 0.025
    save(name, col, mask, size=(1024, int(1024 * H / W)))


def _dome_mask(H, W, rng, cx, base_y, width, height, wrap=True):
    """One rounded cumulus dome (hump-profile billows + edge sub-billows). Returns field B."""
    blobs = []
    for j in range(rng.integers(7, 12)):
        u = rng.uniform(-1, 1)
        hump = 1 - abs(u) ** 1.6
        r = width * rng.uniform(0.14, 0.24) * (0.7 + 0.5 * hump)
        blobs.append((cx + u * width * 0.42, base_y - hump * height * rng.uniform(0.55, 0.85) + r * 0.3, r, 1.0))
    for j in range(5):  # broad body under the dome
        blobs.append((cx + (j - 2) * width * 0.2, base_y + height * 0.15, width * 0.2, 1.0))
    B0 = blob_field(H, W, blobs, wrap=wrap)
    m0 = B0 > 0.45
    edge = m0 & ~np.roll(m0, 5, axis=0)
    ey, ex = np.nonzero(edge)
    sub = []
    if len(ey):
        for idx in rng.choice(len(ey), size=min(45, len(ey)), replace=False):
            r = width * rng.uniform(0.04, 0.09)
            sub.append((ex[idx], ey[idx] + r * 0.45, r, 0.9))
    return B0 + blob_field(H, W, sub, wrap=wrap)


def storm_towers2(name, seed, W, H, towers, base_frac, height_rng, width_rng, haze, sun_x_frac):
    """Towering storm clouds painted as cascades of domes (top first, lower/nearer domes over them)."""
    rng = np.random.default_rng(seed)
    col = np.zeros((H, W, 3), np.float32)
    alpha = np.zeros((H, W), np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lumpN = fbm(H, W, seed + 2, beta=2.3, ax=1.3)
    grain = fbm(H, W, seed + 3, beta=1.7, ax=6.0) - 0.5

    def over(c, a):
        nonlocal col, alpha
        out_a = a + alpha * (1 - a)
        col = (c * a[..., None] + col * (alpha * (1 - a))[..., None]) / np.maximum(out_a, 1e-5)[..., None]
        alpha = out_a

    def shade(B, depth_t):
        mask = smoothstep(0.42, 0.52, B + (lumpN - 0.5) * 0.15)
        ms = gaussian_filter(mask, 4.0)
        gy, gx = np.gradient(ms)
        nl = np.sqrt(gx * gx + gy * gy) + 1e-6
        sdx, sdy = (W * sun_x_frac - xx), (H * 0.98 - yy)
        sl = np.sqrt(sdx * sdx + sdy * sdy) + 1e-6
        facing = np.clip(((-gx / nl) * sdx / sl + (-gy / nl) * sdy / sl) * 0.6 + 0.5, 0, 1)
        edge_band = np.clip((1 - gaussian_filter(mask, 5.0)) * mask * 2.2, 0, 1)
        top = np.clip(-gaussian_filter(np.gradient(mask, axis=0), 3) * 30, 0, 1)
        # rim light only where the edge faces the sun / the sky above (no all-round outline)
        rim = np.clip(edge_band * np.clip((top - 0.25) * 2.0, 0, 1) * (0.55 + 0.45 * facing), 0, 1) * 0.85
        Bs = gaussian_filter(B, 14)
        lit = np.clip(np.gradient(Bs, axis=0) * 45, 0, 1)
        v = np.clip(0.28 + 0.4 * lit + (lumpN - 0.5) * 0.22 - 0.25 * depth_t, 0, 1)
        c = ramp(painterly_steps(v, 6, lumpN, jitter=0.12, soft=0.6), PAL_STORM_BODY)
        rc = ramp(painterly_steps(rim, 5, lumpN, jitter=0.1, soft=0.5), PAL_STORM_RIM)
        rw = np.clip(rim * 1.5, 0, 1)[..., None]
        c = c * (1 - rw) + rc * rw
        return c * (1 - haze) + hexc("b9658c") * haze, mask

    order = []
    for i in range(towers):
        x = (i + rng.uniform(0.15, 0.85)) * W / towers
        tw = W * rng.uniform(*width_rng)
        th = H * rng.uniform(*height_rng)
        order.append((x, tw, th))
    for (x, tw, th) in order:
        base_y = H * base_frac
        top_y = base_y - th
        # wispy anvil behind everything: long flat streak downwind of the top
        streak = fbm(H, W, seed + int(x), beta=2.2, ax=7.0)
        band = np.exp(-((yy - (top_y + th * 0.12)) / (H * 0.03)) ** 2)
        span = smoothstep(x - tw * 0.7, x - tw * 0.3, xx) * smoothstep(x + tw * 1.8, x + tw * 0.8, xx)
        a_anv = np.clip(smoothstep(0.35, 0.6, streak) * band * span * 1.2 + band * span * 0.35, 0, 1) * 0.95
        anv_rim = np.clip(-np.gradient(gaussian_filter(a_anv, 3), axis=0) * 40, 0, 1)
        c_anv = ramp(np.clip(0.55 + 0.4 * anv_rim, 0, 1), PAL_STORM_BODY)
        c_anv = c_anv * (1 - anv_rim[..., None]) + ramp(anv_rim, PAL_STORM_RIM) * anv_rim[..., None]
        over(c_anv * (1 - haze) + hexc("b9658c") * haze, a_anv)
        # domes from the top (smallest, furthest) down to the base (widest, nearest)
        n = rng.integers(3, 5)
        for d in range(n):
            t = d / max(n - 1, 1)
            w_d = tw * (0.85 + 0.4 * t) * rng.uniform(0.92, 1.08)
            y_d = top_y + th * (0.32 + 0.66 * t)
            cx = x + rng.uniform(-0.08, 0.08) * tw
            B = _dome_mask(H, W, rng, cx, y_d, w_d, th * 0.5)
            c, m = shade(B, t)
            over(c, m)
    # low lumpy clouds along the base
    B = blob_field(H, W, [(rng.uniform(0, W), H * base_frac + rng.uniform(0.02, 0.1) * H, W * rng.uniform(0.04, 0.07), 1.0)
                          for _ in range(towers * 8)])
    c, m = shade(B, 1.0)
    over(c, np.clip(m + smoothstep(base_frac + 0.08, base_frac + 0.14, yy / H), 0, 1))
    col = np.clip(col + grain[..., None] * 0.025, 0, 1)
    save(name, col, alpha, size=(1024, int(1024 * H / W)))


def storm_set():
    sky_storm()
    # taller canvases (1.5x) with the tower bases in the middle: the solid fill below the bases
    # reaches past the next layer, so no strips of sky show between layers
    storm_towers2("storm_far", 61, 2048, 1536, towers=3, base_frac=0.5, height_rng=(0.3, 0.41),
                  width_rng=(0.12, 0.16), haze=0.4, sun_x_frac=0.38)
    storm_towers2("storm_mid", 62, 2048, 1536, towers=2, base_frac=0.53, height_rng=(0.37, 0.47),
                  width_rng=(0.16, 0.2), haze=0.18, sun_x_frac=0.38)
    storm_towers2("storm_near", 63, 2048, 1152, towers=2, base_frac=0.5, height_rng=(0.23, 0.33),
                  width_rng=(0.2, 0.26), haze=0.04, sun_x_frac=0.38)


# --- storm v2: cold grey-teal thunderstorm (user reference: dark billowing clouds, bright gap, lightning)
PAL_STORM_GREY = [
    (0.00, hexc("141b1f")), (0.2, hexc("26323a")), (0.42, hexc("3e4e56")),
    (0.62, hexc("62757c")), (0.8, hexc("95a8ab")), (0.92, hexc("c4d4d3")), (1.0, hexc("e6f0ee")),
]


def sky_storm2():
    W, H = 2048, 896
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    gx, gy = W * 0.55, H * 0.3  # bright gap in the clouds (upper middle)
    d = np.sqrt(((xx - gx) / W) ** 2 + ((yy - gy) / H * 0.7) ** 2)
    n1 = fbm(H, W, 201, beta=2.4, ax=1.6)
    n2 = fbm(H, W, 202, beta=1.8, ax=1.2)
    light = np.exp(-(d / 0.28) ** 2) * 0.85 + (n1 - 0.5) * 0.5 + (n2 - 0.5) * 0.2 + 0.25
    val = painterly_steps(np.clip(light, 0, 1), 8, n2, jitter=0.1, soft=0.7)
    save("sky_storm2", ramp(val, PAL_STORM_GREY), size=(1024, 448))


def storm_heap(name, seed, W, H, base_frac, rows, dome_w, dome_h, blur, haze, gap_x=0.55, light=1.0):
    """Rows of heaped cauliflower storm domes (grey), lit from a bright gap above; solid below."""
    rng = np.random.default_rng(seed)
    col = np.zeros((H, W, 3), np.float32)
    alpha = np.zeros((H, W), np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lumpN = fbm(H, W, seed + 2, beta=2.3, ax=1.2)
    fluff = fbm(H, W, seed + 4, beta=1.5, ax=1.0)  # fine cotton texture

    def over(c, a):
        nonlocal col, alpha
        out_a = a + alpha * (1 - a)
        col = (c * a[..., None] + col * (alpha * (1 - a))[..., None]) / np.maximum(out_a, 1e-5)[..., None]
        alpha = out_a

    for r_i in range(rows):  # back rows first (higher on the canvas), nearer rows lower and over them
        t = r_i / max(rows - 1, 1)
        y_base = H * (base_frac - 0.12 * (1 - t))
        n = int(W / (dome_w * W * 0.75)) + 1
        for k in range(n):
            cx = (k + rng.uniform(0, 1)) * W / n
            w = dome_w * W * rng.uniform(0.8, 1.3)
            h = dome_h * H * rng.uniform(0.7, 1.3) * (1 + 0.4 * rng.uniform() ** 3)  # a few tall heaps
            B = _dome_mask(H, W, rng, cx, y_base + rng.uniform(-0.03, 0.03) * H, w, h)
            # soft, fluffy volume: wide blurred edge broken up by cotton-like noise
            Bb = gaussian_filter(B, w * 0.04)
            mask = smoothstep(0.25, 0.6, Bb + (fluff - 0.5) * 0.35)
            Bs = gaussian_filter(B, w * 0.12)
            lit = np.clip(np.gradient(Bs, axis=0) * w * 0.35, 0, 1)              # tops face the light
            inner = gaussian_filter(mask, w * 0.05)
            silver = np.clip((1 - inner) * mask * 2.0, 0, 1) * lit                 # bright fringe on lit tops
            gapd = np.exp(-((cx - W * gap_x) / (W * 0.35)) ** 2)                 # domes under the gap are brighter
            v = (0.2 + 0.45 * lit + 0.3 * silver * (0.5 + 0.5 * gapd)) * light \
                + (fluff - 0.5) * 0.18 + (lumpN - 0.5) * 0.12 + 0.1 * gapd - 0.15 * t
            c = ramp(np.clip(v, 0, 1), PAL_STORM_GREY)
            c = c * (1 - haze * (1 - t)) + hexc("5d6e73") * haze * (1 - t)
            over(c, mask)
    # dark solid storm base under the heaps
    base = smoothstep(base_frac + 0.04, base_frac + 0.12, yy / H)
    bc = ramp(np.clip(0.18 + (lumpN - 0.5) * 0.3, 0, 1), PAL_STORM_GREY)
    over(bc * (1 - 0.5 * haze) + hexc("4d5c61") * 0.5 * haze, base)
    if blur > 0:  # soft focus for distance (keep alpha edges soft too)
        col = gaussian_filter(col, (blur, blur, 0))
        alpha = gaussian_filter(alpha, blur)
    col = np.clip(col + (fbm(H, W, seed + 3, beta=1.6, ax=4.0) - 0.5)[..., None] * 0.03, 0, 1)
    save(name, col, alpha, size=(1024, int(1024 * H / W)))


def storm_volume(name, seed, W, H, top_frac, scale, gain, gap=(0.55, -0.3), steps=16, march=0.012,
                 dark=0.0, haze=0.0, out_h=None):
    """Soft volumetric storm clouds: fractal density + light marched toward a bright gap.
    Thin parts glow, thick parts self-shadow (like real backlit storm clouds)."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = yy / H
    # billowy density: big puffs (inverted ridged noise) + detail
    n1 = fbm(H, W, seed, beta=2.6 + 0.2 * scale, ax=1.4)
    n2 = fbm(H, W, seed + 1, beta=2.0, ax=1.2)
    n3 = fbm(H, W, seed + 2, beta=1.4, ax=1.0)
    puffy = 1 - np.abs(n1 * 2 - 1)
    dens = 0.55 * puffy + 0.3 * n2 + 0.15 * n3
    # layer: denser downward, top edge heaped into big billows (large-scale noise) + smaller lumps
    big = fbm(H, W, seed + 7, beta=3.2, ax=1.0)
    edge = top_frac + (0.5 - big) * 0.55 + (n2 - 0.5) * 0.12
    dens = dens + (v - edge) * 2.2
    D = np.clip((dens - 0.55) * gain, 0, 1)
    # light march toward the gap (direction varies per pixel)
    gx, gy = W * gap[0], H * gap[1]
    dx, dy = gx - xx, gy - yy
    dx = (dx + W / 2) % W - W / 2  # wrapped distance (for the gap glow only)
    # constant light direction (from above, leaning toward the gap) keeps the tile seamless
    ux = np.full_like(xx, 0.18) * np.sign(gap[0] - 0.5 + 1e-6)
    uy = np.full_like(yy, -0.98)
    optical = np.zeros_like(D)
    step_px = march * W
    from scipy.ndimage import map_coordinates
    for i in range(1, steps + 1):
        sx = (xx + ux * step_px * i) % W
        sy = np.clip(yy + uy * step_px * i, 0, H - 1)
        optical += map_coordinates(D, [sy.ravel(), sx.ravel()], order=1, mode="nearest").reshape(H, W)
    light = np.exp(-optical * 0.16)
    gapd = np.exp(-((dx / W) ** 2 + ((yy - max(gy, 0)) / H * 0.8) ** 2) / 0.12)
    # inner billows: light also varies with the local density structure
    val = np.clip(0.06 + 0.8 * light + 0.15 * gapd - dark * v + (puffy - 0.5) * 0.22 + (n3 - 0.5) * 0.1, 0, 1)
    col = ramp(val, PAL_STORM_GREY)
    col = col * (1 - haze) + hexc("5f7075") * haze
    alpha = smoothstep(0.0, 0.35, D)
    save(name, col, alpha, size=(1024, out_h or int(1024 * H / W)))


def storm2_layers():
    # light comes from the bright gap above the middle; nearer layers are bigger, darker, sharper
    storm_volume("storm2_far", 211, 2048, 1024, top_frac=0.3, scale=0.0, gain=2.2, gap=(0.55, -0.2), haze=0.25)
    storm_volume("storm2_mid", 212, 2048, 1024, top_frac=0.38, scale=0.5, gain=2.6, gap=(0.55, -0.6), dark=0.25, haze=0.1)
    storm_volume("storm2_near", 213, 2048, 768, top_frac=0.3, scale=1.0, gain=3.0, gap=(0.55, -1.2), dark=0.35)
    # overhead ceiling: render a layer lit from "above" and flip it, so it hangs with lit undersides toward the gap
    storm_volume("storm2_ceiling", 214, 2048, 768, top_frac=0.35, scale=0.6, gain=2.6, gap=(0.55, -0.8), dark=0.3)
    im = Image.open(os.path.join(OUT, "storm2_ceiling.png"))
    im.transpose(Image.FLIP_TOP_BOTTOM).save(os.path.join(OUT, "storm2_ceiling.png"))
    return


def _storm2_layers_old():
    storm_heap("storm2_far", 211, 2048, 1024, base_frac=0.55, rows=2, dome_w=0.1, dome_h=0.22, blur=2.5, haze=0.45)
    storm_heap("storm2_mid", 212, 2048, 1024, base_frac=0.6, rows=2, dome_w=0.15, dome_h=0.3, blur=1.2, haze=0.2)
    storm_heap("storm2_near", 213, 2048, 768, base_frac=0.55, rows=2, dome_w=0.22, dome_h=0.42, blur=0.0, haze=0.0,
               light=0.85)
    # ceiling: billows hanging down from above (paint a sheet and flip it)
    W, H = 2048, 768
    col, a = rolling_sheet(214, W, H, top_frac=0.3, rows=3, sun_xy=(W * 0.55, H * 2.0), palette=PAL_STORM_GREY,
                           haze_top=0.1, wisp=0.3, warp=3.0, billow_r=W * 0.05)
    col = col * 0.7
    save("storm2_ceiling", col[::-1], a[::-1], size=(1024, 384))


def lightning_bolt():
    """Branching bolt sprite (white with cyan glow) on transparent background."""
    W, H = 512, 1024
    rng = np.random.default_rng(301)
    core = np.zeros((H, W), np.float32)

    def branch(x, y, angle, length, width, depth):
        steps = int(length / 8)
        for _ in range(steps):
            angle += rng.uniform(-0.5, 0.5)
            angle = np.clip(angle, np.pi * 0.25, np.pi * 0.75)
            nx, ny = x + np.cos(angle) * 8, y + np.sin(angle) * 8
            for t in np.linspace(0, 1, 6):
                px, py = int(x + (nx - x) * t), int(y + (ny - y) * t)
                if 0 <= px < W and 0 <= py < H:
                    core[max(0, py - width):py + width + 1, max(0, px - width):px + width + 1] = 1
            x, y = nx, ny
            if depth < 3 and rng.uniform() < 0.09:
                branch(x, y, angle + rng.choice([-0.7, 0.7]), length * 0.35, max(0, width - 1), depth + 1)
            if y > H - 10:
                break
    branch(W * 0.5, 0, np.pi / 2, H * 1.1, 1, 0)
    glow = gaussian_filter(core, 2) * 1.5 + gaussian_filter(core, 8) * 2.5
    a = np.clip(core + glow, 0, 1)
    col = np.clip(np.dstack([np.ones_like(core)] * 3) * 1.0, 0, 1)
    col[..., 0] -= (1 - core) * 0.25  # cyan-tinted glow, white core
    save("bolt", col, a, size=(256, 512))


def sky_whale2():
    """Organic sky-whale silhouette from overlapping ellipses (head right, tail left)."""
    W, H = 2048, 768
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    a = np.zeros((H, W), np.float32)

    def ell(cx, cy, rx, ry, ang=0.0):
        c, s = np.cos(ang), np.sin(ang)
        u = ((xx - cx) * c + (yy - cy) * s) / rx
        v = (-(xx - cx) * s + (yy - cy) * c) / ry
        return np.clip(1.2 - np.sqrt(u * u + v * v) * 1.2, 0, 1) * 5

    # head + body: big rounded mass, deeper belly
    a = np.maximum(a, ell(W * 0.66, H * 0.47, W * 0.26, H * 0.2))
    a = np.maximum(a, ell(W * 0.62, H * 0.53, W * 0.22, H * 0.19))
    # tail stalk: chain of shrinking ellipses curving slightly up
    for i in range(12):
        t = i / 11
        a = np.maximum(a, ell(W * (0.45 - 0.33 * t), H * (0.5 - 0.06 * t * t), W * (0.11 - 0.07 * t), H * (0.15 - 0.12 * t)))
    # flukes (seen from the side: thin swept lobes)
    a = np.maximum(a, ell(W * 0.08, H * 0.38, W * 0.06, H * 0.035, -0.5))
    a = np.maximum(a, ell(W * 0.08, H * 0.5, W * 0.055, H * 0.03, 0.45))
    # long pectoral fin sweeping back and down
    a = np.maximum(a, ell(W * 0.55, H * 0.75, W * 0.14, H * 0.035, 0.32))
    a = gaussian_filter(np.clip(a, 0, 1), 3.0)
    col = np.dstack([np.full((H, W), c, np.float32) for c in (0.07, 0.09, 0.11)])
    save("whale", col, a, size=(1024, 384))


def sky_whale():
    """Original sky-whale silhouette (side view): long body, tail flukes, long pectoral fin."""
    W, H = 2048, 768
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    u = xx / W  # 0 = tail tip .. 1 = head
    # spine: slight S-curve, tail end lifted
    spine = H * (0.46 + 0.05 * np.sin(u * np.pi * 1.6) - 0.06 * smoothstep(0.35, 0.0, u))
    # thickness: blunt big head, belly bulge, long taper into a thin tail stalk
    prof = np.clip(np.where(u > 0.82, np.sqrt(np.clip((1.0 - u) / 0.18, 0, 1)), 1.0) *
                   smoothstep(0.08, 0.62, u) ** 0.9, 0, 1)
    top_h = H * 0.17 * prof
    bot_h = H * 0.25 * prof  # deeper belly
    dy = yy - spine
    body = np.where(dy < 0, smoothstep(top_h + 2, top_h - 2, -dy), smoothstep(bot_h + 2, bot_h - 2, dy)) * (u > 0.06)
    stalk = smoothstep(H * 0.022 + 2, H * 0.022 - 2, np.abs(dy)) * (u > 0.04) * (u < 0.2)
    # crescent fluke at the tail tip (thin, swept back)
    fx = W * 0.05
    fl = np.zeros_like(body)
    for sgn in (-1, 1):
        t = np.clip((fx - xx) / (W * 0.05) + 0.2, 0, 1)
        cy_f = H * 0.4 + sgn * t * H * 0.14
        width = H * 0.035 * (1 - t) + 2
        fl = np.maximum(fl, smoothstep(width + 2, width - 2, np.abs(yy - cy_f)) * (xx < fx + W * 0.02) * (xx > fx - W * 0.045))
    # long humpback pectoral fin sweeping back and down from behind the head
    ft = np.clip((W * 0.66 - xx) / (W * 0.26), 0, 1)
    fin_y = H * 0.6 + ft * H * 0.28
    fw = H * 0.045 * (1 - ft) ** 0.8 + 1
    fin = smoothstep(fw + 2, fw - 2, np.abs(yy - fin_y)) * (xx < W * 0.66) * (xx > W * 0.4)
    a = np.clip(np.maximum.reduce([body, stalk, fl, fin]), 0, 1)
    a = gaussian_filter(a, 2.0)
    col = np.dstack([np.full((H, W), c, np.float32) for c in (0.06, 0.08, 0.1)])
    save("whale", col, a, size=(1024, 384))


def mist():
    """See-through drifting mist band (tileable), white-lilac streaks."""
    W, H = 2048, 512
    yy = np.mgrid[0:H, 0:W][0].astype(np.float32) / H
    n = fbm(H, W, 81, beta=2.2, ax=7.0)
    n2 = fbm(H, W, 82, beta=1.8, ax=3.0)
    a = smoothstep(0.42, 0.75, n * 0.75 + n2 * 0.25) * np.exp(-((yy - 0.5) / 0.28) ** 2) * 0.85
    col = ramp(n2, [(0, hexc("b8a6d8")), (0.6, hexc("e8d8ee")), (1, hexc("fff0e8"))])
    save("mist", col, a, size=(1024, 256))


def storm2_set():
    sky_storm2()
    storm2_layers()
    lightning_bolt()
    sky_whale()


PAINTINGS = {
    "storm2": storm2_set,
    "storm": storm_set,
    "mist": mist,
    "clouds": float_clouds,
    "bands": sea_bands,
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
