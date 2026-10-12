from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
IMAGES = ROOT / "assets" / "images"


def make_logo() -> None:
    source = Image.open(IMAGES / "logo.jpeg").convert("RGBA")
    pixels = []
    for red, green, blue, alpha in source.getdata():
        lightest = min(red, green, blue)
        if lightest >= 248:
            alpha = 0
        elif lightest >= 232:
            alpha = int(alpha * (248 - lightest) / 16)
        pixels.append((red, green, blue, alpha))
    source.putdata(pixels)
    source.save(IMAGES / "logo_transparent.png", optimize=True)


def make_document_background() -> None:
    background = Image.open(IMAGES / "background.jpeg").convert("RGB")
    background.save(IMAGES / "document_background.png", optimize=True)


if __name__ == "__main__":
    make_logo()
    make_document_background()
