#!/usr/bin/env python3
"""VIDEO 01 — Something big is coming. 15-second teaser."""

from __future__ import annotations

import math
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path("/Users/ashrafrezk/Salesforce Projects/Zeta Pharma")
BUILD = ROOT / "ph/Plan/teasers/build"
OUT = ROOT / "ph/Plan/teasers/VIDEO-01-Something-Big-Is-Coming.mp4"

TABLET_SRC = Path(
    "/Users/ashrafrezk/.cursor/projects/Users-ashrafrezk-Salesforce-Projects-Zeta-Pharma/assets/teaser-tablet-user.jpg"
)
TEAM_SRC = Path(
    "/Users/ashrafrezk/.cursor/projects/Users-ashrafrezk-Salesforce-Projects-Zeta-Pharma/assets/teaser-team.jpg"
)
ZETA_LOGO = ROOT / "ph/offline/public/zeta-logo-white.png"
CLOUD_LOGO = ROOT / "force-app/main/default/staticresources/CloudastickLogo.png"
SF_SVG = ROOT / "ph/offline/public/salesforce-logo.svg"
HOME_SHOT = ROOT / "docs/guidebook/assets/pwa-home.png"
FIELD_SHOT = ROOT / "docs/guidebook/assets/sf-field-home.png"

FONT = "/System/Library/Fonts/Avenir Next.ttc"
FONT_INDEX = 2  # Demi Bold

W, H = 1920, 1080
FPS = 30
DURATION = 15.0
NFRAMES = int(FPS * DURATION)

# Screen corners on the original 1280x720 tablet still: TL, TR, BR, BL.
SCREEN_QUAD = [(596, 312), (992, 302), (976, 596), (608, 608)]


def smooth(t):
    t = float(np.clip(t, 0.0, 1.0))
    return t * t * (3.0 - 2.0 * t)


def fade_in(t, start, dur):
    return smooth((t - start) / dur) if dur else (1.0 if t >= start else 0.0)


def fade_out(t, end, dur):
    return smooth((end - t) / dur) if dur else (1.0 if t <= end else 0.0)


def text_width(text, font, tracking):
    widths = [font.getlength(ch) for ch in text]
    if not widths:
        return 0.0
    return float(sum(widths) + tracking * (len(text) - 1))


def draw_tracked(draw, text, font, xy, fill, tracking):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += font.getlength(ch) + tracking


def render_text(text, size, tracking):
    font = ImageFont.truetype(FONT, size, index=FONT_INDEX)
    width = text_width(text, font, tracking)
    ascent, descent = font.getmetrics()
    pad = 28
    img = Image.new("RGBA", (int(width) + pad * 2, ascent + descent + pad * 2), (0, 0, 0, 0))
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw_tracked(ImageDraw.Draw(shadow), text, font, (pad, pad + 4), (0, 0, 0, 170), tracking)
    shadow = shadow.filter(ImageFilter.GaussianBlur(7))
    img.alpha_composite(shadow)
    draw_tracked(ImageDraw.Draw(img), text, font, (pad, pad), (246, 248, 252, 255), tracking)
    return img


def paste(bg, fg, x, y, opacity=1.0):
    if opacity <= 0.001:
        return
    fg = np.asarray(fg) if not isinstance(fg, np.ndarray) else fg
    fh, fw = fg.shape[:2]
    x, y = int(round(x)), int(round(y))
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(bg.shape[1], x + fw), min(bg.shape[0], y + fh)
    if x1 <= x0 or y1 <= y0:
        return
    crop = fg[y0 - y : y0 - y + (y1 - y0), x0 - x : x0 - x + (x1 - x0)]
    if crop.shape[2] == 4:
        alpha = crop[:, :, 3:4].astype(np.float32) * (opacity / 255.0)
        src = crop[:, :, :3].astype(np.float32)
    else:
        alpha = np.full(crop.shape[:2] + (1,), opacity, np.float32)
        src = crop[:, :, :3].astype(np.float32)
    dst = bg[y0:y1, x0:x1].astype(np.float32)
    bg[y0:y1, x0:x1] = np.clip(src * alpha + dst * (1.0 - alpha), 0, 255).astype(np.uint8)


def cover_top(im, size):
    tw, th = size
    sw, sh = im.size
    scale = max(tw / sw, th / sh)
    nw, nh = max(1, int(sw * scale)), max(1, int(sh * scale))
    resized = im.resize((nw, nh), Image.LANCZOS)
    x = max(0, (nw - tw) // 2)
    y = 0
    if y + th > nh:
        y = max(0, nh - th)
    return resized.crop((x, y, x + tw, y + th))


def key_black(path, threshold=12, softness=26):
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    luma = rgb.max(axis=2)
    alpha = np.clip((luma - threshold) / softness, 0, 1)
    # Keep the gold check, which sits darker than the white cloud.
    alpha = np.maximum(alpha, np.clip((luma - 8) / 18.0, 0, 1) * (rgb[:, :, 0] > 40))
    ys, xs = np.where(alpha > 0.08)
    pad = 4
    x0, y0 = max(0, xs.min() - pad), max(0, ys.min() - pad)
    x1, y1 = min(rgb.shape[1], xs.max() + pad), min(rgb.shape[0], ys.max() + pad)
    rgba = np.dstack([rgb, alpha * 255]).astype(np.uint8)
    return Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")


def find_coeffs(output_quad, source_corners):
    matrix = []
    for p1, p2 in zip(output_quad, source_corners):
        matrix.append([p1[0], p1[1], 1, 0, 0, 0, -p2[0] * p1[0], -p2[0] * p1[1]])
        matrix.append([0, 0, 0, p1[0], p1[1], 1, -p2[1] * p1[0], -p2[1] * p1[1]])
    a = np.asarray(matrix, dtype=np.float64)
    b = np.asarray(source_corners, dtype=np.float64).reshape(8)
    return np.linalg.lstsq(a, b, rcond=None)[0]


def grade(im):
    arr = np.asarray(im.convert("RGB")).astype(np.float32)
    arr *= np.array([0.88, 0.94, 1.06], dtype=np.float32)
    arr = (arr - 124.0) * 1.05 + 120.0
    h, w = arr.shape[:2]
    yy = np.linspace(-1, 1, h)[:, None]
    xx = np.linspace(-1, 1, w)[None, :]
    vig = np.clip(1.0 - 0.55 * (xx * xx * 0.85 + yy * yy) ** 1.15, 0.35, 1.0)
    arr *= vig[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def make_card(shot, card_w, card_h, radius=26):
    bezel = 7
    inner = cover_top(shot.convert("RGB"), (card_w - bezel * 2, card_h - bezel * 2))
    plate = Image.new("RGBA", (card_w, card_h), (0, 0, 0, 0))
    mask = Image.new("L", (card_w, card_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, card_w - 1, card_h - 1), radius, fill=255)
    body = Image.new("RGBA", (card_w, card_h), (8, 12, 20, 255))
    body.putalpha(mask)
    plate.alpha_composite(body)
    inner_rgba = inner.convert("RGBA")
    inner_mask = Image.new("L", inner.size, 0)
    ImageDraw.Draw(inner_mask).rounded_rectangle(
        (0, 0, inner.size[0] - 1, inner.size[1] - 1), max(8, radius - 8), fill=255
    )
    inner_rgba.putalpha(inner_mask)
    plate.alpha_composite(inner_rgba, (bezel, bezel))
    ImageDraw.Draw(plate).rounded_rectangle(
        (1, 1, card_w - 2, card_h - 2), radius, outline=(186, 214, 232, 170), width=2
    )
    pad = 46
    shadow = Image.new("RGBA", (card_w + pad * 2, card_h + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (pad, pad + 10, pad + card_w, pad + card_h + 10), radius, fill=(0, 0, 0, 150)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(16))
    out = Image.new("RGBA", shadow.size, (0, 0, 0, 0))
    out.alpha_composite(shadow)
    out.alpha_composite(plate, (pad, pad))
    return out, pad


def field_screen():
    field = Image.open(FIELD_SHOT).convert("RGB")
    header = field.crop((0, 0, 1280, 96)).resize((1280, 108), Image.LANCZOS)
    # The Cairo route map sits on the right of the lower panel.
    band = field.crop((420, 520, 1280, 850))
    canvas = Image.new("RGB", (1280, 820), (255, 255, 255))
    canvas.paste(header, (0, 0))
    canvas.paste(cover_top(band, (1280, 712)), (0, 108))
    return canvas


def load_assets():
    BUILD.mkdir(parents=True, exist_ok=True)
    sf_png = BUILD / "salesforce.png"
    subprocess.check_call(
        [
            "magick",
            "-background",
            "none",
            "-density",
            "400",
            str(SF_SVG),
            "-resize",
            "1800x",
            str(sf_png),
        ]
    )
    sf = Image.open(sf_png).convert("RGBA")
    arr = np.asarray(sf)
    ys, xs = np.where(arr[:, :, 3] > 20)
    sf = sf.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))

    zeta = Image.open(ZETA_LOGO).convert("RGBA")
    cloud = key_black(CLOUD_LOGO)

    # Greeting and welcome message only, so account names stay out of frame.
    home = Image.open(HOME_SHOT).convert("RGB").crop((0, 0, 800, 372))
    screen = field_screen()

    base_w, base_h = 2304, 1296
    scale = base_w / 1280.0
    quad = [(x * scale, y * scale) for x, y in SCREEN_QUAD]

    tablet = grade(Image.open(TABLET_SRC)).resize((base_w, base_h), Image.LANCZOS)
    tablet = tablet.filter(ImageFilter.UnsharpMask(radius=1.5, percent=60, threshold=2))
    screen_fit = screen.resize((1400, 920), Image.LANCZOS)
    src = [(0, 0), (screen_fit.size[0], 0), screen_fit.size, (0, screen_fit.size[1])]
    coeffs = find_coeffs(quad, src)
    warped = screen_fit.convert("RGBA").transform(tablet.size, Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    mask = Image.new("L", tablet.size, 0)
    ImageDraw.Draw(mask).polygon(quad, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(0.8))
    warped.putalpha(mask)
    tablet_on = tablet.convert("RGBA")
    tablet_on.alpha_composite(warped)

    team = grade(Image.open(TEAM_SRC)).resize((base_w, base_h), Image.LANCZOS)
    team = team.filter(ImageFilter.UnsharpMask(radius=1.3, percent=50, threshold=2))

    home_size = (804, 374)
    map_size = (804, 516)
    home_card, pad = make_card(home, *home_size)
    map_card, _ = make_card(screen, *map_size)

    zeta_w = 860
    zeta_h = int(zeta.size[1] * (zeta_w / zeta.size[0]))
    zeta = zeta.resize((zeta_w, zeta_h), Image.LANCZOS)
    glow = Image.new("RGBA", (zeta_w + 180, zeta_h + 180), (0, 0, 0, 0))
    alpha = zeta.split()[-1].resize((zeta_w, zeta_h))
    tint = Image.new("RGBA", zeta.size, (40, 150, 230, 0))
    tint.putalpha(alpha.point(lambda p: int(p * 0.85)))
    glow.paste(tint, (90, 90), tint)
    glow = glow.filter(ImageFilter.GaussianBlur(28))

    sf.thumbnail((280, 180), Image.LANCZOS)
    cloud.thumbnail((250, 210), Image.LANCZOS)

    return {
        "tablet": tablet.convert("RGB"),
        "tablet_on": tablet_on.convert("RGB"),
        "team": team.convert("RGB"),
        "home_card": home_card,
        "map_card": map_card,
        "card_pad": pad,
        "home_size": home_size,
        "map_size": map_size,
        "zeta": zeta,
        "zeta_glow": glow,
        "sf": sf,
        "cloud": cloud,
        "t1": render_text("The way we work is evolving.", 58, 1.4),
        "t2": render_text("A new chapter. A shared ambition.", 46, 1.15),
        "t3": render_text("Something big is coming.", 52, 1.3),
    }


def background():
    ys = np.linspace(0, 1, H)[:, None]
    bg = np.zeros((H, W, 3), np.float32)
    bg[:, :, 0] = 5 + 7 * ys
    bg[:, :, 1] = 8 + 12 * ys
    bg[:, :, 2] = 16 + 20 * ys
    return np.clip(bg, 0, 255).astype(np.uint8)


def vignette_mask():
    yy, xx = np.mgrid[0:H, 0:W]
    nx = (xx - W / 2) / (W / 2)
    ny = (yy - H / 2) / (H / 2)
    return np.clip(1.0 - 0.34 * (nx * nx * 0.9 + ny * ny) ** 1.2, 0.0, 1.0).astype(np.float32)


def apply_vignette(frame, vig):
    out = frame.astype(np.float32) * vig[:, :, None]
    return np.clip(out, 0, 255).astype(np.uint8)


def add_light(frame, cx, strength, sigma=150, cy=H * 0.47, ysig=280):
    if strength <= 0.001:
        return frame
    xs = np.arange(W, dtype=np.float32)
    ys = np.arange(H, dtype=np.float32)
    band = np.exp(-((xs - cx) ** 2) / (2 * sigma * sigma)) * strength
    vert = np.exp(-((ys - cy) ** 2) / (2 * ysig * ysig))
    glow = vert[:, None] * band[None, :]
    f = frame.astype(np.float32)
    f[:, :, 0] += glow * 10
    f[:, :, 1] += glow * 42
    f[:, :, 2] += glow * 78
    return np.clip(f, 0, 255).astype(np.uint8)


def build_nodes():
    rng = np.random.default_rng(11)
    n = 40
    pts = np.column_stack([rng.uniform(90, W - 90, n), rng.uniform(80, H - 160, n)])
    # Pull a band of nodes across the middle, where the light travels.
    pts[:18, 1] = rng.uniform(H * 0.30, H * 0.68, 18)
    phase = rng.uniform(0, math.tau, n)
    speed = rng.uniform(0.35, 0.85, n)
    amp = rng.uniform(10, 26, (n, 1))
    return pts, phase, speed, amp


NODES, PHASE, SPEED, AMP = build_nodes()


def node_positions(t):
    drift = np.column_stack(
        [
            np.sin(t * SPEED + PHASE) * AMP[:, 0],
            np.cos(t * SPEED * 0.75 + PHASE) * AMP[:, 0] * 0.65,
        ]
    )
    return NODES + drift


def draw_network(t, light_cx, strength):
    if strength <= 0.02:
        return None
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    pts = node_positions(t)
    for i in range(len(pts)):
        for j in range(i + 1, len(pts)):
            dx = pts[i, 0] - pts[j, 0]
            dy = pts[i, 1] - pts[j, 1]
            dist = math.hypot(dx, dy)
            if dist > 270:
                continue
            mid = (pts[i, 0] + pts[j, 0]) * 0.5
            glow = math.exp(-((mid - light_cx) ** 2) / (2 * 240 * 240))
            alpha = int((1.0 - dist / 270.0) * (28 + 130 * glow) * strength)
            if alpha < 8:
                continue
            draw.line(
                [(pts[i, 0], pts[i, 1]), (pts[j, 0], pts[j, 1])],
                fill=(132, 196, 230, alpha),
                width=2,
            )
    for i, (x, y) in enumerate(pts):
        glow = math.exp(-((x - light_cx) ** 2) / (2 * 210 * 210))
        r = 2.4 + 2.2 * glow
        alpha = int((70 + 160 * glow) * strength)
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(214, 236, 255, alpha))
    return img


def ken(im, zoom, panx, pany):
    bw, bh = im.size
    cw = int(bw / zoom)
    ch = int(bh / zoom)
    maxx = max(0, bw - cw)
    maxy = max(0, bh - ch)
    x = int(maxx * (0.5 + panx * 0.5))
    y = int(maxy * (0.5 + pany * 0.5))
    crop = im.crop((x, y, x + cw, y + ch))
    if crop.size != (W, H):
        crop = crop.resize((W, H), Image.LANCZOS)
    return np.array(crop)


def scrim(frame, strength=0.72):
    grad = np.linspace(0, 1, 280) ** 1.35
    f = frame.astype(np.float32)
    f[-280:] *= (1.0 - strength * grad)[:, None, None]
    return np.clip(f, 0, 255).astype(np.uint8)


def place_text(frame, img, y, opacity):
    if opacity <= 0.01:
        return
    x = (W - img.size[0]) // 2
    paste(frame, img, x, y, opacity)


def scene_network(t, assets, vig):
    frame = BG.copy()
    cx = -200 + (W + 400) * smooth(np.clip((t - 0.12) / 2.55, 0, 1))
    frame = add_light(frame, cx, 1.0, sigma=120, ysig=250)
    net = draw_network(t, cx, 1.0)
    if net is not None:
        paste(frame, net, 0, 0, 1.0)
    op = fade_in(t, 0.40, 0.70) * fade_out(t, 2.72, 0.42)
    place_text(frame, assets["t1"], H // 2 - assets["t1"].size[1] // 2 + 8, op)
    return apply_vignette(frame, vig)


def scene_tablet(t, assets):
    local = np.clip((t - 2.8) / 1.9, 0, 1)
    zoom = 1.03 + 0.07 * local
    panx = -0.05 + 0.22 * local
    base = assets["tablet"]
    on = assets["tablet_on"]
    turn = smooth(np.clip((t - 3.05) / 0.45, 0, 1))
    a = ken(base, zoom, panx, 0.02)
    b = ken(on, zoom, panx, 0.02)
    frame = (a.astype(np.float32) * (1 - turn) + b.astype(np.float32) * turn).astype(np.uint8)
    frame = scrim(frame, 0.78)
    return frame


def scene_team(t, assets):
    local = np.clip((t - 4.3) / 1.25, 0, 1)
    zoom = 1.045 + 0.04 * local
    panx = 0.12 - 0.22 * local
    frame = ken(assets["team"], zoom, panx, -0.02)
    # Connected lines over the group. Coordinates are in the 1920 frame.
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    progress = smooth(np.clip((t - 4.52) / 0.55, 0, 1))
    # Points sit in the glass behind the group and on the tablet, not on faces.
    anchors = [(410, 150), (960, 118), (1510, 145), (990, 648)]
    pairs = [(0, 1), (1, 2), (0, 3), (2, 3)]
    for a, b in pairs:
        x0, y0 = anchors[a]
        x1, y1 = anchors[b]
        x = x0 + (x1 - x0) * progress
        y = y0 + (y1 - y0) * progress
        draw.line([(x0, y0), (x, y)], fill=(150, 210, 240, 150), width=2)
    if progress > 0.15:
        for x, y in anchors:
            r = 5
            draw.ellipse((x - r, y - r, x + r, y + r), fill=(230, 244, 255, 210))
    paste(frame, overlay, 0, 0, 0.9)
    frame = scrim(frame)
    return frame


def scene_panels(t, assets):
    frame = BG.copy()
    frame = add_light(frame, W * 0.5, 0.45, sigma=420, cy=H * 0.42, ysig=320)
    net = draw_network(t * 0.6, W * 0.55, 0.55)
    if net is not None:
        paste(frame, net, 0, 0, 1.0)
    home_w, home_h = assets["home_size"]
    map_w, map_h = assets["map_size"]
    pad = assets["card_pad"]
    gap = 78
    total = home_w + gap + map_w
    left = (W - total) // 2
    block_top = 188
    home_top = block_top + (map_h - home_h) // 2
    map_top = block_top
    local = t - 5.35
    line_p = smooth(np.clip((local - 0.22) / 0.5, 0, 1))
    if line_p > 0:
        overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        y = (home_top + home_h // 2 + map_top + map_h // 2) // 2
        x0 = left + home_w + 8
        x1 = left + home_w + gap - 8
        x_end = x0 + (x1 - x0) * line_p
        draw.line([(x0, y), (x_end, y)], fill=(150, 206, 236, 200), width=2)
        if line_p > 0.85:
            for nx in (x0, x1):
                draw.ellipse((nx - 5, y - 5, nx + 5, y + 5), fill=(236, 246, 255, 230))
        paste(frame, overlay, 0, 0, 1.0)
    o1 = smooth(np.clip((local - 0.02) / 0.38, 0, 1))
    o2 = smooth(np.clip((local - 0.16) / 0.38, 0, 1))
    paste(frame, assets["home_card"], left - pad, home_top - pad + int(12 * (1 - o1)), o1)
    paste(frame, assets["map_card"], left + home_w + gap - pad, map_top - pad + int(12 * (1 - o2)), o2)
    return apply_vignette(frame, VIGNETTE)


def scene_reveal(t, assets, vig):
    frame = BG.copy()
    settle = smooth(np.clip((t - 7.0) / 1.4, 0, 1))
    frame = add_light(frame, W * 0.5, 0.55 * (1 - 0.35 * settle), sigma=360, cy=H * 0.46, ysig=240)
    net_strength = 0.28 * (1 - smooth(np.clip((t - 7.1) / 1.3, 0, 1)))
    net = draw_network(t * 0.4, W * (0.15 + 0.7 * smooth(np.clip((t - 7.05) / 1.2, 0, 1))), net_strength)
    if net is not None:
        paste(frame, net, 0, 0, 1.0)

    rise = smooth(np.clip((t - 11.45) / 0.85, 0, 1))
    zeta = assets["zeta"]
    glow = assets["zeta_glow"]
    logo_x = (W - zeta.size[0]) // 2
    logo_y = int(392 - 118 * rise)
    reveal = smooth(np.clip((t - 7.28) / 1.15, 0, 1))
    # Soft left-to-right light reveal.
    xs = np.linspace(0, 1, zeta.size[0], dtype=np.float32)
    edge = -0.15 + 1.35 * reveal
    mask = np.clip((edge - xs) / 0.10, 0, 1)
    zeta_arr = np.asarray(zeta).astype(np.float32)
    zeta_arr[:, :, 3] *= mask
    glow_arr = np.asarray(glow).astype(np.float32)
    gmask = np.clip((edge + 0.06 - np.linspace(0, 1, glow.size[0])) / 0.14, 0, 1)
    glow_arr[:, :, 3] *= gmask
    paste(frame, glow_arr.astype(np.uint8), logo_x - 90, logo_y - 90, 1.0)
    paste(frame, zeta_arr.astype(np.uint8), logo_x, logo_y, 1.0)

    if reveal < 0.995:
        streak_x = logo_x + edge * zeta.size[0]
        frame = add_light(frame, streak_x, 0.85 * (1 - reveal * 0.3), sigma=28, cy=logo_y + zeta.size[1] / 2, ysig=70)

    text_op = fade_in(t, 8.05, 0.55)
    text = assets["t3"]
    text_y = logo_y + zeta.size[1] + 28
    place_text(frame, text, text_y, text_op)

    partner = smooth(np.clip((t - 11.75) / 0.7, 0, 1))
    if partner > 0.01:
        sf, cloud = assets["sf"], assets["cloud"]
        gap = 150
        row_w = sf.size[0] + gap + cloud.size[0]
        row_x = (W - row_w) // 2
        row_y = text_y + text.size[1] + 18 + int(16 * (1 - partner))
        # Align both marks on a shared center line.
        mid = row_y + 80
        paste(frame, sf, row_x, mid - sf.size[1] // 2, partner)
        paste(frame, cloud, row_x + sf.size[0] + gap, mid - cloud.size[1] // 2, partner)
    return apply_vignette(frame, vig)


def opacity_windows(t):
    # Abstract opening dissolves into the first shot. The photo cuts stay hard.
    if t < 2.82:
        return 1.0, 0.0, 0.0, 0.0, 0.0
    if t < 3.12:
        k = smooth((t - 2.82) / 0.30)
        return 1.0 - k, k, 0.0, 0.0, 0.0
    if t < 4.45:
        return 0.0, 1.0, 0.0, 0.0, 0.0
    if t < 5.35:
        return 0.0, 0.0, 1.0, 0.0, 0.0
    if t < 6.92:
        return 0.0, 0.0, 0.0, 1.0, 0.0
    if t < 7.20:
        k = smooth((t - 6.92) / 0.28)
        return 0.0, 0.0, 0.0, 1.0 - k, k
    return 0.0, 0.0, 0.0, 0.0, 1.0


def compose(t, assets, vig):
    weights = {
        "network": opacity_windows(t)[0],
        "tablet": opacity_windows(t)[1],
        "team": opacity_windows(t)[2],
        "panels": opacity_windows(t)[3],
        "reveal": opacity_windows(t)[4],
    }
    frames = {}
    if weights["network"] > 0.01:
        frames["network"] = scene_network(t, assets, vig)
    if weights["tablet"] > 0.01:
        frames["tablet"] = scene_tablet(t, assets)
    if weights["team"] > 0.01:
        frames["team"] = scene_team(t, assets)
    if weights["panels"] > 0.01:
        frames["panels"] = scene_panels(t, assets)
    if weights["reveal"] > 0.01:
        frames["reveal"] = scene_reveal(t, assets, vig)
    active = [(weights[k], frames[k]) for k in frames]
    if not active:
        out = BG.copy()
    elif len(active) == 1:
        out = active[0][1]
    else:
        total = sum(w for w, _ in active)
        acc = np.zeros((H, W, 3), np.float32)
        for w, fr in active:
            acc += fr.astype(np.float32) * (w / total)
        out = np.clip(acc, 0, 255).astype(np.uint8)
    # Open from black.
    opener = smooth(np.clip(t / 0.45, 0, 1))
    if opener < 0.999:
        out = (out.astype(np.float32) * opener).astype(np.uint8)
    caption = fade_in(t, 3.18, 0.32) * fade_out(t, 6.88, 0.22)
    place_text(out, assets["t2"], H - 156, caption)
    # Break up banding in the dark fields without graining the logos or screens.
    luma = out.mean(axis=2)
    dark = luma < 32
    if dark.any():
        noise = np.random.default_rng(int(t * FPS) + 3).integers(-2, 3, luma.shape, dtype=np.int16)
        lifted = out.astype(np.int16)
        lifted[dark] = np.clip(lifted[dark] + noise[dark, None], 0, 255)
        out = lifted.astype(np.uint8)
    return out


def write_bed(path):
    sr = 48000
    n = int(sr * DURATION)
    t = np.arange(n, dtype=np.float64) / sr
    partials = [(73.42, 0.24), (110.0, 0.18), (146.83, 0.11), (174.61, 0.055), (220.0, 0.04)]
    left = np.zeros(n)
    right = np.zeros(n)
    for freq, amp in partials:
        left += amp * np.sin(2 * np.pi * freq * (1 - 0.0022) * t)
        right += amp * np.sin(2 * np.pi * freq * (1 + 0.0022) * t)
    fade = np.clip(t / 1.5, 0, 1) * np.clip((DURATION - t) / 1.15, 0, 1)
    swell = 0.72 + 0.5 * np.clip((t - 7.05) / 1.3, 0, 1)
    lfo = 0.86 + 0.14 * np.sin(2 * np.pi * 0.06 * t)
    env = fade * swell * lfo * 0.16
    rng = np.random.default_rng(4)
    noise = rng.standard_normal(n)
    air = np.empty(n)
    state = 0.0
    for i, sample in enumerate(noise):
        state += 0.0035 * (sample - state)
        air[i] = state
    who = (
        np.exp(-((t - 0.25) ** 2) / 0.03) * 0.035
        + np.exp(-((t - 3.0) ** 2) / 0.04) * 0.03
        + np.exp(-((t - 7.1) ** 2) / 0.035) * 0.04
    )
    hp = noise - np.concatenate([[0.0], noise[:-1]])
    left = left * env + air * 0.02 * fade + hp * who
    right = right * env + air * 0.016 * fade + hp * who
    imp_t = t - 7.2
    imp = np.sin(2 * np.pi * (70 + 50 * np.exp(-np.clip(imp_t, 0, None))) * np.clip(imp_t, 0, None))
    imp *= np.exp(-np.clip(imp_t, 0, None) * 2.8)
    imp[imp_t < 0] = 0
    left += imp * 0.22
    right += imp * 0.22
    stereo = np.column_stack([left, right])
    peak = np.max(np.abs(stereo)) or 1.0
    stereo = stereo / peak * 0.55
    pcm = np.clip(stereo, -1, 1)
    pcm = (pcm * 32767).astype(np.int16)
    with wave.open(str(path), "w") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(sr)
        handle.writeframes(pcm.tobytes())


def mix_audio(path):
    bed = BUILD / "bed.wav"
    write_bed(bed)
    voice = (
        "atempo=0.90,"
        "highpass=f=85,"
        "equalizer=f=2600:t=q:w=1.1:g=2.2,"
        "acompressor=threshold=-18dB:ratio=2.2:attack=10:release=140:makeup=3,"
        "loudnorm=I=-16:TP=-1.5:LRA=7"
    )
    for name in ("vo1", "vo2", "vo3"):
        subprocess.check_call(
            [
                "ffmpeg",
                "-y",
                "-i",
                str(BUILD / f"{name}.aiff"),
                "-af",
                voice,
                str(BUILD / f"{name}.wav"),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    filt = (
        "[0:a]volume=0.85[bed];"
        "[1:a]adelay=520|520,volume=1[v1];"
        "[2:a]adelay=3280|3280,volume=1[v2];"
        "[3:a]adelay=7350|7350,volume=1[v3];"
        "[bed][v1][v2][v3]amix=inputs=4:duration=first:dropout_transition=0:normalize=0,"
        "alimiter=limit=0.96,"
        "afade=t=out:st=14.15:d=0.85"
    )
    subprocess.check_call(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(bed),
            "-i",
            str(BUILD / "vo1.wav"),
            "-i",
            str(BUILD / "vo2.wav"),
            "-i",
            str(BUILD / "vo3.wav"),
            "-filter_complex",
            filt,
            "-t",
            "15",
            str(path),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def render(assets, times=None):
    global BG, VIGNETTE
    BG = background()
    VIGNETTE = vignette_mask()
    if times is not None:
        folder = BUILD / "frames"
        folder.mkdir(parents=True, exist_ok=True)
        for t in times:
            frame = compose(t, assets, VIGNETTE)
            Image.fromarray(frame).save(folder / f"t{t:04.1f}.jpg", quality=90)
            print(f"preview {t:0.1f}s")
        return
    mix = BUILD / "mix.wav"
    mix_audio(mix)
    cmd = [
        "ffmpeg",
        "-y",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "-s",
        f"{W}x{H}",
        "-r",
        str(FPS),
        "-i",
        "-",
        "-i",
        str(mix),
        "-c:v",
        "libx264",
        "-profile:v",
        "high",
        "-pix_fmt",
        "yuv420p",
        "-crf",
        "17",
        "-preset",
        "medium",
        "-movflags",
        "+faststart",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        "-shortest",
        "-metadata",
        "title=Something big is coming",
        str(OUT),
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for i in range(NFRAMES):
            t = i / FPS
            frame = compose(t, assets, VIGNETTE)
            proc.stdin.write(frame.tobytes())
            if i % 30 == 0:
                print(f"frame {i}/{NFRAMES}")
        proc.stdin.close()
        err = proc.stderr.read().decode("utf-8", "replace")
        code = proc.wait()
        if code != 0:
            raise RuntimeError(err[-2000:])
    finally:
        if proc.poll() is None:
            proc.kill()
    poster = compose(13.6, assets, VIGNETTE)
    Image.fromarray(poster).save(BUILD / "poster.jpg", quality=92)
    print(OUT)


def main():
    print("preparing assets")
    assets = load_assets()
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        render(
            assets,
            times=[0.6, 1.6, 2.4, 3.5, 4.5, 5.0, 6.1, 6.6, 8.2, 9.4, 11.1, 13.2, 14.5],
        )
        return
    render(assets)


if __name__ == "__main__":
    main()
