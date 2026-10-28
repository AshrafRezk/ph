"""Build launcher, PWA, and Play Store images from the official Zeta mark."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
REPO = Path(__file__).resolve().parents[3]
MARK_SRC = REPO / "force-app/main/default/staticresources/ZetaBlueZ.png"
LOCKUP_SRC = REPO / "force-app/main/default/staticresources/ZetaBlueLogo.png"
LOGIN_SRC = REPO / "force-app/main/default/staticresources/ZetaLoginLogo.png"
RES = ROOT / "android/app/src/main/res"
WHITE = (255, 255, 255, 255)
INK = (0, 114, 188, 255)
MUTED = (112, 110, 107, 255)


def crop_content(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    box = image.getbbox()
    if not box:
        raise SystemExit(f"No visible pixels in {path}")
    return image.crop(box)


def contain(mark: Image.Image, size: int, scale: float) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    target = max(1, int(round(size * scale)))
    ratio = min(target / mark.width, target / mark.height)
    resized = mark.resize(
        (max(1, int(round(mark.width * ratio))), max(1, int(round(mark.height * ratio)))),
        Image.Resampling.LANCZOS,
    )
    canvas.paste(
        resized,
        ((size - resized.width) // 2, (size - resized.height) // 2),
        resized,
    )
    return canvas


def on_white(image: Image.Image) -> Image.Image:
    background = Image.new("RGBA", image.size, WHITE)
    return Image.alpha_composite(background, image)


def save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG")


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial Bold.ttf" if bold else "/Library/Fonts/Arial.ttf",
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def feature_graphic(mark: Image.Image, lockup: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", (1024, 500), WHITE)
    mark_box = contain(mark, 300, 0.92)
    canvas.paste(mark_box, (72, 100), mark_box)
    wordmark = lockup.crop((200, 0, lockup.width, lockup.height))
    wordmark_w = 420
    wordmark_h = max(1, int(round(wordmark.height * (wordmark_w / wordmark.width))))
    wordmark = wordmark.resize((wordmark_w, wordmark_h), Image.Resampling.LANCZOS)
    text_x = 430
    title_font = font(36, bold=True)
    subtitle_font = font(22)
    title = "Zeta Co-Pilot"
    subtitle = "Powered by Cloudastick Systems, a Salesforce Partner"
    block_h = 44 + 16 + wordmark_h + 18 + 28
    top = (500 - block_h) // 2
    draw = ImageDraw.Draw(canvas)
    draw.text((text_x, top), title, font=title_font, fill=INK)
    canvas.paste(wordmark, (text_x, top + 56), wordmark)
    draw.text((text_x, top + 56 + wordmark_h + 18), subtitle, font=subtitle_font, fill=MUTED)
    return canvas


def main() -> None:
    mark = crop_content(MARK_SRC)
    lockup = crop_content(LOCKUP_SRC)
    launcher = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    foreground = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

    for density, size in launcher.items():
        icon = on_white(contain(mark, size, 0.68))
        folder = RES / f"mipmap-{density}"
        save(icon, folder / "ic_launcher.png")
        save(icon, folder / "ic_launcher_round.png")
    for density, size in foreground.items():
        save(contain(mark, size, 0.58), RES / f"mipmap-{density}" / "ic_launcher_foreground.png")

    splashes = {
        "drawable/splash.png": (480, 320),
        "drawable-land-mdpi/splash.png": (480, 320),
        "drawable-land-hdpi/splash.png": (800, 480),
        "drawable-land-xhdpi/splash.png": (1280, 720),
        "drawable-land-xxhdpi/splash.png": (1600, 960),
        "drawable-land-xxxhdpi/splash.png": (1920, 1280),
        "drawable-port-mdpi/splash.png": (320, 480),
        "drawable-port-hdpi/splash.png": (480, 800),
        "drawable-port-xhdpi/splash.png": (720, 1280),
        "drawable-port-xxhdpi/splash.png": (960, 1600),
        "drawable-port-xxxhdpi/splash.png": (1280, 1920),
    }
    for rel, (width, height) in splashes.items():
        plate = Image.new("RGBA", (width, height), WHITE)
        side = int(round(min(width, height) * 0.42))
        badge = contain(mark, side, 0.92)
        plate.paste(badge, ((width - side) // 2, (height - side) // 2), badge)
        save(plate, RES / rel)

    public = ROOT / "public"
    save(on_white(contain(mark, 192, 0.72)), public / "icon-192.png")
    play_icon = on_white(contain(mark, 512, 0.72))
    save(play_icon, public / "icon-512.png")
    store = ROOT / "store"
    save(play_icon, store / "play-icon-512.png")
    save(feature_graphic(mark, lockup), store / "play-feature-graphic.png")
    save(contain(mark, 256, 0.92), public / "zeta-mark.png")
    login = Image.open(LOGIN_SRC).convert("RGBA")
    save(login, public / "zeta-logo.png")
    print("Zeta icons written")


if __name__ == "__main__":
    main()
