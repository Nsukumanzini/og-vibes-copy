from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
IMAGES = ROOT / "assets" / "images"


def make_logo() -> None:
    # Keep the complete supplied mark, including its white background, so no
    # white lettering or negative space is removed when assets are regenerated.
    source = Image.open(IMAGES / "logo.jpeg").convert("RGBA")
    source.save(IMAGES / "logo_transparent.png", optimize=True)


def make_document_background() -> None:
    background = Image.open(IMAGES / "background.jpeg").convert("RGB")
    background.save(IMAGES / "document_background.png", optimize=True)


if __name__ == "__main__":
    make_logo()
    make_document_background()
