"""Play Store listing art for Zeta Co-Pilot, built from the official Zeta mark."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
REPO = Path(__file__).resolve().parents[3]
STORE = ROOT / "store"
LOGO = REPO / "force-app/main/default/staticresources"
HELV = "/System/Library/Fonts/Helvetica.ttc"

NAVY = (6, 24, 48)
NAVY_2 = (12, 52, 102)
CYAN = (0, 174, 239)
BLUE = (0, 114, 188)
INK = (18, 32, 51)
MUTED = (96, 112, 130)
LINE = (226, 232, 240)
PAPER = (244, 247, 251)
WHITE = (255, 255, 255)
GREEN = (15, 138, 96)


def font(size, weight="regular"):
    index = {"regular": 0, "bold": 1, "light": 4}[weight]
    return ImageFont.truetype(HELV, size, index=index)


def crop_visible(path):
    image = Image.open(path).convert("RGBA")
    box = image.getbbox()
    return image.crop(box) if box else image


def knockout_dark(path):
    image = Image.open(path).convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            lum = (red + green + blue) / 3
            if lum < 36:
                pixels[x, y] = (255, 255, 255, 0)
            else:
                strength = min(255, int((lum - 36) * 255 / (255 - 36)))
                pixels[x, y] = (red, green, blue, min(alpha, strength))
    box = image.getbbox()
    return image.crop(box) if box else image


def fit(image, box_w, box_h):
    ratio = min(box_w / image.width, box_h / image.height)
    size = (max(1, int(image.width * ratio)), max(1, int(image.height * ratio)))
    return image.resize(size, Image.Resampling.LANCZOS)


def gradient(size, top, bottom):
    width, height = size
    canvas = Image.new("RGB", size)
    pixels = canvas.load()
    for y in range(height):
        blend = y / max(1, height - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * blend) for i in range(3))
        for x in range(width):
            pixels[x, y] = color
    return canvas


def shadow_card(base, box, radius=28, fill=WHITE, blur=18, alpha=70):
    x, y, w, h = box
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle((x, y + 10, x + w, y + h + 14), radius=radius, fill=(8, 24, 48, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(layer)
    ImageDraw.Draw(base).rounded_rectangle((x, y, x + w, y + h), radius=radius, fill=fill)


def text_width(draw, value, face):
    box = draw.textbbox((0, 0), value, font=face)
    return box[2] - box[0]


def wrap(draw, value, face, width):
    lines = []
    for paragraph in value.split("\n"):
        current = ""
        for word in paragraph.split():
            trial = word if not current else f"{current} {word}"
            if text_width(draw, trial, face) <= width:
                current = trial
            else:
                if current:
                    lines.append(current)
                current = word
        lines.append(current)
    return lines


def paste(base, image, xy):
    base.paste(image, xy, image)


def status_bar(draw, width, dark=False):
    color = WHITE if dark else INK
    face = font(28, "bold")
    draw.text((48, 36), "9:41", font=face, fill=color)
    draw.rounded_rectangle((width - 150, 40, width - 48, 68), radius=8, outline=color, width=3)
    draw.rectangle((width - 142, 48, width - 78, 60), fill=color)
    draw.ellipse((width - 196, 42, width - 168, 70), outline=color, width=3)


def bottom_nav(base, active):
    draw = ImageDraw.Draw(base)
    width, height = base.size
    y = height - 168
    draw.rectangle((0, y, width, height), fill=WHITE)
    draw.line((0, y, width, y), fill=LINE, width=2)
    items = ["Home", "Planner", "Accounts", "Learn"]
    slot = width // len(items)
    for index, label in enumerate(items):
        color = BLUE if label == active else MUTED
        cx = slot * index + slot // 2
        draw.rounded_rectangle((cx - 28, y + 28, cx + 28, y + 52), radius=8, fill=color)
        face = font(24, "bold" if label == active else "regular")
        label_w = text_width(draw, label, face)
        draw.text((cx - label_w / 2, y + 78), label, font=face, fill=color)


def feature_graphic(mark):
    canvas = gradient((1024, 500), (4, 18, 40), (8, 58, 112)).convert("RGBA")
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((40, 40, 460, 470), fill=(0, 174, 239, 70))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(40)))
    sized = fit(mark, 340, 300)
    paste(canvas, sized, (78, (500 - sized.height) // 2))
    draw = ImageDraw.Draw(canvas)
    draw.text((470, 128), "ZETA PHARMA", font=font(22, "bold"), fill=CYAN)
    draw.text((470, 168), "Zeta Co-Pilot", font=font(64, "bold"), fill=WHITE)
    draw.rectangle((472, 258, 560, 264), fill=CYAN)
    draw.text((470, 288), "Plan the day. Work anywhere.", font=font(28), fill=(214, 230, 242))
    draw.text(
        (470, 348),
        "Powered by Cloudastick Systems, a Salesforce Partner",
        font=font(20),
        fill=(168, 196, 220),
    )
    return canvas.convert("RGB")


def screen_welcome(logo):
    canvas = Image.new("RGBA", (1080, 1920), PAPER)
    draw = ImageDraw.Draw(canvas)
    status_bar(draw, 1080)
    sized = fit(logo, 520, 220)
    paste(canvas, sized, ((1080 - sized.width) // 2, 280))
    draw = ImageDraw.Draw(canvas)
    title = "Welcome"
    face = font(72, "bold")
    draw.text(((1080 - text_width(draw, title, face)) / 2, 560), title, font=face, fill=INK)
    lead = "Sign in with your company account. After the first sync, you can keep working even without internet."
    body = font(32)
    lines = wrap(draw, lead, body, 760)
    y = 680
    for line in lines:
        draw.text(((1080 - text_width(draw, line, body)) / 2, y), line, font=body, fill=MUTED)
        y += 48
    shadow_card(canvas, (120, y + 48, 840, 112), radius=24)
    draw = ImageDraw.Draw(canvas)
    draw.text((156, y + 84), "How do you sign in?", font=font(22), fill=MUTED)
    draw.text((156, y + 116), "Live account", font=font(34, "bold"), fill=INK)
    button_y = y + 200
    draw.rounded_rectangle((120, button_y, 960, button_y + 112), radius=28, fill=BLUE)
    label = "Sign in"
    label_face = font(36, "bold")
    draw.text(((1080 - text_width(draw, label, label_face)) / 2, button_y + 32), label, font=label_face, fill=WHITE)
    footer = "Powered by Cloudastick Systems, a Salesforce Partner"
    footer_face = font(24)
    draw.text(((1080 - text_width(draw, footer, footer_face)) / 2, 1680), footer, font=footer_face, fill=MUTED)
    return canvas.convert("RGB")


def visits():
    return [
        ("09:00", "City Clinic", "Nasr City", "Confirmed"),
        ("10:30", "Nile Heart Centre", "Heliopolis", "Next"),
        ("12:15", "Garden Pharmacy", "Maadi", "Planned"),
        ("14:00", "Delta Medical", "New Cairo", "Planned"),
        ("16:10", "Palm Care", "6th of October", "Planned"),
    ]


def screen_today():
    canvas = gradient((1080, 1920), NAVY, NAVY_2).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    status_bar(draw, 1080, dark=True)
    draw.text((56, 140), "Good morning", font=font(32), fill=(168, 206, 230))
    draw.text((56, 188), "Today’s route", font=font(64, "bold"), fill=WHITE)
    draw.text((56, 276), "Thursday 15 October", font=font(28), fill=(150, 186, 214))
    stats = [("5", "Visits"), ("42 km", "On the road"), ("Ready", "Offline")]
    for index, (value, label) in enumerate(stats):
        x = 56 + index * 330
        shadow_card(canvas, (x, 360, 300, 150), radius=28, fill=WHITE)
        draw = ImageDraw.Draw(canvas)
        draw.text((x + 24, 384), value, font=font(40, "bold"), fill=NAVY)
        draw.text((x + 24, 444), label, font=font(24), fill=MUTED)
    sheet = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(sheet).rounded_rectangle((0, 560, 1080, 1920), radius=48, fill=PAPER)
    canvas.alpha_composite(sheet)
    draw = ImageDraw.Draw(canvas)
    y = 610
    for time, name, place, state in visits():
        shadow_card(canvas, (48, y, 984, 168), radius=28)
        draw = ImageDraw.Draw(canvas)
        draw.text((80, y + 36), time, font=font(28, "bold"), fill=BLUE)
        draw.text((230, y + 32), name, font=font(36, "bold"), fill=INK)
        draw.text((230, y + 88), place, font=font(28), fill=MUTED)
        chip = GREEN if state == "Next" else BLUE
        chip_w = text_width(draw, state, font(22, "bold")) + 36
        draw.rounded_rectangle((984 - chip_w, y + 36, 984, y + 84), radius=18, fill=chip)
        draw.text((984 - chip_w + 18, y + 46), state, font=font(22, "bold"), fill=WHITE)
        y += 196
    bottom_nav(canvas, "Home")
    return canvas.convert("RGB")


def screen_map():
    canvas = Image.new("RGBA", (1080, 1920), (214, 230, 242))
    draw = ImageDraw.Draw(canvas)
    for offset in range(-400, 1400, 180):
        draw.line((offset, 0, offset + 700, 1920), fill=(232, 242, 248), width=26)
        draw.line((0, offset + 200, 1080, offset + 520), fill=(232, 242, 248), width=18)
    route = [(180, 1500), (280, 1180), (460, 980), (620, 760), (780, 520), (860, 340)]
    draw.line(route, fill=CYAN, width=16, joint="curve")
    for point in route:
        draw.ellipse((point[0] - 16, point[1] - 16, point[0] + 16, point[1] + 16), fill=WHITE, outline=BLUE, width=6)
    draw.ellipse((164, 1484, 212, 1532), fill=BLUE)
    status_bar(draw, 1080)
    shadow_card(canvas, (48, 120, 984, 150), radius=28)
    draw = ImageDraw.Draw(canvas)
    draw.text((80, 152), "Your route", font=font(36, "bold"), fill=INK)
    draw.text((80, 206), "5 stops  ·  starting from your location", font=font(26), fill=MUTED)
    shadow_card(canvas, (48, 1500, 984, 220), radius=32)
    draw = ImageDraw.Draw(canvas)
    draw.text((80, 1536), "NEXT", font=font(22, "bold"), fill=CYAN)
    draw.text((80, 1572), "Nile Heart Centre", font=font(40, "bold"), fill=INK)
    draw.text((80, 1632), "Heliopolis  ·  12 min  ·  6.4 km", font=font(28), fill=MUTED)
    return canvas.convert("RGB")


def screen_accounts():
    canvas = Image.new("RGBA", (1080, 1920), PAPER)
    draw = ImageDraw.Draw(canvas)
    status_bar(draw, 1080)
    draw.text((56, 130), "Accounts", font=font(64, "bold"), fill=INK)
    shadow_card(canvas, (48, 240, 984, 104), radius=28)
    draw = ImageDraw.Draw(canvas)
    draw.text((84, 270), "Search clinics, pharmacies, people", font=font(30), fill=MUTED)
    rows = [
        ("CC", "City Clinic", "Nasr City  ·  Cardiology"),
        ("NH", "Nile Heart Centre", "Heliopolis  ·  Hospital"),
        ("GP", "Garden Pharmacy", "Maadi  ·  Pharmacy"),
        ("DM", "Delta Medical", "New Cairo  ·  Clinic"),
        ("PC", "Palm Care", "6th of October  ·  Clinic"),
    ]
    y = 390
    for initials, name, detail in rows:
        shadow_card(canvas, (48, y, 984, 176), radius=28)
        draw = ImageDraw.Draw(canvas)
        draw.ellipse((80, y + 40, 168, y + 128), fill=BLUE)
        initials_face = font(32, "bold")
        initials_w = text_width(draw, initials, initials_face)
        draw.text((124 - initials_w / 2, y + 66), initials, font=initials_face, fill=WHITE)
        draw.text((200, y + 42), name, font=font(36, "bold"), fill=INK)
        draw.text((200, y + 98), detail, font=font(28), fill=MUTED)
        y += 204
    bottom_nav(canvas, "Accounts")
    return canvas.convert("RGB")


def screen_offline():
    canvas = Image.new("RGBA", (1080, 1920), PAPER)
    draw = ImageDraw.Draw(canvas)
    status_bar(draw, 1080)
    draw.rounded_rectangle((48, 130, 1032, 360), radius=36, fill=NAVY)
    draw.text((84, 168), "You’re offline", font=font(48, "bold"), fill=WHITE)
    draw.text((84, 240), "Today’s visits are saved on this phone.", font=font(30), fill=(186, 214, 232))
    draw.text((84, 288), "They will sync when you are back online.", font=font(30), fill=(186, 214, 232))
    y = 410
    for time, name, place, _state in visits()[:4]:
        shadow_card(canvas, (48, y, 984, 160), radius=28)
        draw = ImageDraw.Draw(canvas)
        draw.text((80, y + 36), time, font=font(28, "bold"), fill=BLUE)
        draw.text((230, y + 32), name, font=font(36, "bold"), fill=INK)
        draw.text((230, y + 88), f"{place}  ·  Saved on this phone", font=font(26), fill=MUTED)
        y += 188
    bottom_nav(canvas, "Planner")
    return canvas.convert("RGB")


def tablet_today():
    canvas = gradient((1920, 1080), NAVY, NAVY_2).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    draw.text((72, 56), "Today’s route", font=font(54, "bold"), fill=WHITE)
    draw.text((72, 128), "Thursday 15 October  ·  5 visits  ·  ready offline", font=font(28), fill=(176, 208, 230))
    y = 210
    for time, name, place, state in visits():
        shadow_card(canvas, (72, y, 860, 140), radius=24, fill=WHITE)
        draw = ImageDraw.Draw(canvas)
        draw.text((100, y + 28), time, font=font(26, "bold"), fill=BLUE)
        draw.text((230, y + 24), name, font=font(32, "bold"), fill=INK)
        draw.text((230, y + 74), place, font=font(24), fill=MUTED)
        y += 160
    map_box = (980, 210, 1860, 980)
    ImageDraw.Draw(canvas).rounded_rectangle(map_box, radius=32, fill=(214, 230, 242))
    draw = ImageDraw.Draw(canvas)
    route = [(1080, 860), (1220, 700), (1400, 620), (1560, 460), (1700, 320)]
    draw.line(route, fill=CYAN, width=12, joint="curve")
    for point in route:
        draw.ellipse((point[0] - 12, point[1] - 12, point[0] + 12, point[1] + 12), fill=WHITE, outline=BLUE, width=5)
    draw.text((1020, 240), "Next  ·  Nile Heart Centre", font=font(28, "bold"), fill=INK)
    draw.text((1020, 286), "Heliopolis  ·  12 min", font=font(24), fill=MUTED)
    return canvas.convert("RGB")


def tablet_accounts():
    canvas = Image.new("RGBA", (1920, 1080), PAPER)
    draw = ImageDraw.Draw(canvas)
    draw.text((72, 48), "Accounts", font=font(54, "bold"), fill=INK)
    draw.text((72, 120), "Clinics and pharmacies on today’s route", font=font(28), fill=MUTED)
    cards = [
        ("City Clinic", "Nasr City", "Cardiology"),
        ("Nile Heart Centre", "Heliopolis", "Hospital"),
        ("Garden Pharmacy", "Maadi", "Pharmacy"),
        ("Delta Medical", "New Cairo", "Clinic"),
        ("Palm Care", "6th of October", "Clinic"),
        ("October Labs", "Sheikh Zayed", "Laboratory"),
    ]
    for index, (name, place, kind) in enumerate(cards):
        column = index % 3
        row = index // 3
        x = 72 + column * 610
        y = 210 + row * 380
        shadow_card(canvas, (x, y, 560, 320), radius=28)
        draw = ImageDraw.Draw(canvas)
        draw.ellipse((x + 32, y + 36, x + 112, y + 116), fill=BLUE)
        initials = "".join(part[0] for part in name.split()[:2])
        initials_face = font(28, "bold")
        initials_w = text_width(draw, initials, initials_face)
        draw.text((x + 72 - initials_w / 2, y + 58), initials, font=initials_face, fill=WHITE)
        draw.text((x + 32, y + 160), name, font=font(32, "bold"), fill=INK)
        draw.text((x + 32, y + 214), place, font=font(26), fill=MUTED)
        draw.text((x + 32, y + 256), kind, font=font(24, "bold"), fill=BLUE)
    return canvas.convert("RGB")


def tablet_welcome(logo):
    canvas = Image.new("RGBA", (1920, 1080), PAPER)
    band = gradient((760, 1080), NAVY, NAVY_2).convert("RGBA")
    canvas.paste(band, (0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.text((72, 360), "Zeta Co-Pilot", font=font(64, "bold"), fill=WHITE)
    draw.text((72, 450), "Plan the day.", font=font(40), fill=(190, 220, 238))
    draw.text((72, 510), "Work anywhere.", font=font(40), fill=(190, 220, 238))
    sized = fit(logo, 560, 220)
    paste(canvas, sized, (1040, 180))
    draw = ImageDraw.Draw(canvas)
    draw.text((1040, 440), "Welcome", font=font(56, "bold"), fill=INK)
    lead = wrap(draw, "Sign in with your company account. The day stays on the device after the first sync.", font(28), 700)
    y = 530
    for line in lead:
        draw.text((1040, y), line, font=font(28), fill=MUTED)
        y += 42
    draw.rounded_rectangle((1040, 700, 1680, 800), radius=24, fill=BLUE)
    draw.text((1260, 730), "Sign in", font=font(32, "bold"), fill=WHITE)
    return canvas.convert("RGB")


def tablet_offline():
    canvas = Image.new("RGBA", (1920, 1080), PAPER)
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((72, 56, 1848, 250), radius=32, fill=NAVY)
    draw.text((112, 96), "You’re offline", font=font(52, "bold"), fill=WHITE)
    draw.text((112, 170), "Visits, accounts, and the route stay on this device until you sync.", font=font(28), fill=(186, 214, 232))
    y = 300
    for time, name, place, _state in visits():
        shadow_card(canvas, (72, y, 1776, 120), radius=22)
        draw = ImageDraw.Draw(canvas)
        draw.text((104, y + 38), time, font=font(28, "bold"), fill=BLUE)
        draw.text((280, y + 36), name, font=font(32, "bold"), fill=INK)
        draw.text((900, y + 40), place, font=font(26), fill=MUTED)
        draw.text((1400, y + 40), "Saved on this phone", font=font(24, "bold"), fill=GREEN)
        y += 144
    return canvas.convert("RGB")


def main():
    blue = crop_visible(LOGO / "ZetaBlueZ.png")
    login = crop_visible(LOGO / "ZetaLoginLogo.png")
    white = knockout_dark(LOGO / "ZetaWhiteZ.png")
    STORE.mkdir(parents=True, exist_ok=True)
    phone = STORE / "phone"
    tablet = STORE / "tablet"
    phone.mkdir(exist_ok=True)
    tablet.mkdir(exist_ok=True)
    feature_graphic(white).save(STORE / "play-feature-graphic.png", "PNG")
    screen_welcome(login).save(phone / "01-welcome.png", "PNG")
    screen_today().save(phone / "02-today.png", "PNG")
    screen_map().save(phone / "03-route.png", "PNG")
    screen_accounts().save(phone / "04-accounts.png", "PNG")
    screen_offline().save(phone / "05-offline.png", "PNG")
    tablet_welcome(login).save(tablet / "01-welcome.png", "PNG")
    tablet_today().save(tablet / "02-today.png", "PNG")
    tablet_accounts().save(tablet / "03-accounts.png", "PNG")
    tablet_offline().save(tablet / "04-offline.png", "PNG")
    print("wrote", STORE)


if __name__ == "__main__":
    main()
