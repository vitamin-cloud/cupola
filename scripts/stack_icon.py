"""The "Stack" fork's launcher icon, from the owner's neon pirate-ship artwork.

    python3 scripts/stack_icon.py SOURCE.jpg REPO [PREVIEW_DIR]

SOURCE is the full artwork (the neon tile on a grey ground). Writes into REPO:
  assets/brand/stack_icon_art.jpg               the tile's inside, kept as the source of record
  android/.../mipmap-*/stack_icon_foreground.png  the artwork, feathered at the edges
  android/.../mipmap-*/stack_icon_background.png  the same artwork, blurred: what shows past it
  android/.../mipmap-*/stack_icon_monochrome.png  its bright lines in white, for themed icons
An adaptive icon is 108dp; a launcher shows the middle 72dp, cut to its shape. The artwork is
sized so the flag and the bow stay inside the circle, the tightest of those shapes.
Needs Pillow.
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

DENSITIES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
ART_SHARE = 0.63   # the artwork's width as a share of the 108dp canvas (the visible circle is 0.667)


def inside_of_tile(src):
    """The square inside the neon border, found by its bright pixels across the middle."""
    im = Image.open(src).convert("RGB")
    w, h = im.size
    px = im.load()
    bright = [x for x in range(w) if px[x, h // 2][1] > 200 and px[x, h // 2][0] > 150]
    left, right = bright[0], bright[-1]
    inset = round((right - left) * 0.019)  # past the border line and its glow
    box = (left + inset, left + inset, right - inset, right - inset)
    return im.crop(box)


def rounded_mask(size, radius, feather):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((feather, feather, size - feather, size - feather), radius, fill=255)
    return m.filter(ImageFilter.GaussianBlur(feather / 2))


def build(art, canvas):
    a = round(canvas * ART_SHARE)
    off = (canvas - a) // 2
    scaled = art.resize((a, a), Image.LANCZOS)
    mask = rounded_mask(a, radius=round(a * 0.12), feather=max(2, round(a * 0.035)))

    fg = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    piece = scaled.convert("RGBA")
    piece.putalpha(mask)
    fg.paste(piece, (off, off), piece)

    bg = art.resize((canvas, canvas), Image.LANCZOS).filter(ImageFilter.GaussianBlur(canvas * 0.06))
    bg = Image.blend(Image.new("RGB", bg.size, (4, 12, 14)), bg, 0.55)

    lum = scaled.convert("L").point(lambda v: 0 if v < 120 else min(255, (v - 120) * 3))
    lum = ImageChops.multiply(lum, mask)
    mono = Image.new("RGBA", (canvas, canvas), (255, 255, 255, 0))
    white = Image.new("RGBA", (a, a), (255, 255, 255, 255))
    white.putalpha(lum)
    mono.paste(white, (off, off), white)
    return fg, bg, mono


def main():
    src, repo = sys.argv[1], sys.argv[2]
    preview = sys.argv[3] if len(sys.argv) > 3 else None
    art = inside_of_tile(src)
    art.resize((1024, 1024), Image.LANCZOS).save(os.path.join(repo, "assets/brand/stack_icon_art.jpg"), quality=90)
    res = os.path.join(repo, "android/app/src/main/res")
    for density, px in DENSITIES.items():
        fg, bg, mono = build(art, px)
        d = os.path.join(res, f"mipmap-{density}")
        fg.save(os.path.join(d, "stack_icon_foreground.png"), optimize=True)
        bg.save(os.path.join(d, "stack_icon_background.png"), optimize=True)
        mono.save(os.path.join(d, "stack_icon_monochrome.png"), optimize=True)
    if preview:
        os.makedirs(preview, exist_ok=True)
        fg, bg, mono = build(art, 432)
        full = bg.convert("RGBA")
        full.alpha_composite(fg)
        full.save(os.path.join(preview, "icon_full.png"))
        mono.save(os.path.join(preview, "icon_mono.png"))
    print("ok")


if __name__ == "__main__":
    main()
