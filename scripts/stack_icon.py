"""The "Stack" fork's launcher icon, from the owner's Musubi artwork (the tile on a dark ground).

    python3 scripts/stack_icon.py SOURCE.jpg REPO [PREVIEW_DIR]

SOURCE is the full artwork: a square, round-cornered illustrated tile on a dark ground. Writes
into REPO:
  assets/brand/stack_icon_art.jpg                 the tile's inside, kept as the source of record
  android/.../mipmap-*/stack_icon_foreground.png  the artwork, filling the adaptive icon
  android/.../mipmap-*/stack_icon_background.png  the same artwork, blurred: what shows past it
  android/.../mipmap-*/stack_icon{,_round}.png    flattened icons, for Android 7 (before adaptive icons)
  assets/brand/stack_mark.png                     the artwork in a circle, the in-app logo
  android/.../drawable-*/launch_mark.png          the same circle at 112dp, the launch screen before Android 12

An adaptive icon is 108dp; a launcher shows the middle 72dp, cut to its shape. The tile is drawn
at ART_SHARE of the canvas, so its own rounded corners fall outside even the square shape and
the paper runs to the launcher's edge. Needs Pillow.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

DENSITIES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
LAUNCH = {"mdpi": 112, "hdpi": 168, "xhdpi": 224, "xxhdpi": 336, "xxxhdpi": 448}
ART_SHARE = 0.74  # the tile's width as a share of the 108dp canvas (the visible square is 0.667)


def inside_of_tile(src):
    """The tile, found by where the picture stops being its dark ground, a little inside its edge.

    Measured across the middle row only: below the tile is its drop shadow, so the tile is taken
    as a square from its top edge."""
    im = Image.open(src).convert("RGB")
    w, h = im.size
    px = im.load()
    ground = px[4, 4]

    def off_ground(p):
        return sum(abs(a - b) for a, b in zip(p, ground)) > 60

    row = [x for x in range(w) if off_ground(px[x, h // 2])]
    col = [y for y in range(h) if off_ground(px[w // 2, y])]
    left, right, top = row[0], row[-1], col[0]
    side = right - left
    inset = round(side * 0.01)  # past the tile's shaded rim
    return im.crop((left + inset, top + inset, left + side - inset, top + side - inset))


def build(art, canvas):
    a = round(canvas * ART_SHARE)
    off = (canvas - a) // 2
    scaled = art.resize((a, a), Image.LANCZOS)

    bg = art.resize((canvas, canvas), Image.LANCZOS).filter(ImageFilter.GaussianBlur(canvas * 0.05))

    # The tile's own corners are rounded onto the dark ground: cut them off, and the blurred
    # paper behind shows there instead.
    corners = Image.new("L", (a * 4, a * 4), 0)
    ImageDraw.Draw(corners).rounded_rectangle((0, 0, a * 4 - 1, a * 4 - 1), round(a * 4 * 0.11), fill=255)
    fg = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    piece = scaled.convert("RGBA")
    piece.putalpha(corners.resize((a, a), Image.LANCZOS))
    fg.paste(piece, (off, off), piece)

    # Themed icons: the ink of the drawing (its dark outlines), in white.
    return fg, bg


def flattened(art, canvas):
    """The icon as a launcher shows it: both layers, cut to the middle 72 of 108."""
    fg, bg = build(art, canvas)
    full = bg.convert("RGBA")
    full.alpha_composite(fg)
    m = round(canvas / 6)
    return full.crop((m, m, canvas - m, canvas - m))


def circle_cut(im, feather=1):
    size = im.size[0]
    big = size * 4
    m = Image.new("L", (big, big), 0)
    ImageDraw.Draw(m).ellipse((feather * 4, feather * 4, big - feather * 4, big - feather * 4), fill=255)
    out = im.copy()
    out.putalpha(m.resize((size, size), Image.LANCZOS))
    return out


def main():
    src, repo = sys.argv[1], sys.argv[2]
    preview = sys.argv[3] if len(sys.argv) > 3 else None
    art = inside_of_tile(src)
    art.resize((1024, 1024), Image.LANCZOS).save(os.path.join(repo, "assets/brand/stack_icon_art.jpg"), quality=90)
    res = os.path.join(repo, "android/app/src/main/res")
    for density, px in DENSITIES.items():
        fg, bg = build(art, px)
        d = os.path.join(res, f"mipmap-{density}")
        fg.save(os.path.join(d, "stack_icon_foreground.png"), optimize=True)
        bg.save(os.path.join(d, "stack_icon_background.png"), optimize=True)
        face = flattened(art, round(LEGACY[density] * 1.5)).resize((LEGACY[density],) * 2, Image.LANCZOS)
        square = Image.new("L", face.size, 0)
        ImageDraw.Draw(square).rounded_rectangle((0, 0, face.size[0] - 1, face.size[1] - 1), round(face.size[0] * 0.18), fill=255)
        sq = face.copy()
        sq.putalpha(square)
        sq.save(os.path.join(d, "stack_icon.png"), optimize=True)
        circle_cut(face).save(os.path.join(d, "stack_icon_round.png"), optimize=True)
    mark = circle_cut(flattened(art, 1536).resize((1024, 1024), Image.LANCZOS), feather=6)
    mark.save(os.path.join(repo, "assets/brand/stack_mark.png"), optimize=True)
    for density, px in LAUNCH.items():
        mark.resize((px, px), Image.LANCZOS).save(
            os.path.join(res, f"drawable-{density}", "launch_mark.png"), optimize=True)
    if preview:
        os.makedirs(preview, exist_ok=True)
        fg, bg = build(art, 432)
        full = bg.convert("RGBA")
        full.alpha_composite(fg)
        full.save(os.path.join(preview, "icon_full.png"))
    print("ok")


if __name__ == "__main__":
    main()
