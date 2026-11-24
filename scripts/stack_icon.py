"""Pirate-ship launcher icon for the "Stack" fork, in Android's 108x108 adaptive-icon grid.

Writes, into the repo given as argv[1]:
  res/drawable/stack_ship.xml        foreground (colour)
  res/drawable/stack_ship_mono.xml   monochrome (themed icons)
  res/drawable/stack_ship_bg.xml     background (night sky)
and into argv[2] the same art as SVG for the preview page.
The safe zone is the 66dp circle at the centre; everything that must survive a mask sits inside it.
"""
import os
import sys

# (path, fill, optional stroke width) -- drawn in order, back to front.
SKY_TOP, SKY_BOTTOM = "#22335A", "#070B16"
MOON = "#F4E7B8"
STAR = "#DCE6FF"
SEA_BACK, SEA_FRONT = "#1E5A78", "#2D86A8"
FOAM = "#CFEAF5"
HULL, HULL_DARK, RAIL = "#7A4524", "#4E2A14", "#C08A4A"
MAST = "#3B2210"
SAIL, SAIL_SHADE = "#F3E9D2", "#D9CBAE"
INK = "#1A120C"


def circle(cx, cy, r):
    return f"M{cx - r},{cy} a{r},{r} 0 1,0 {2 * r},0 a{r},{r} 0 1,0 {-2 * r},0 Z"


FOREGROUND = [
    # moon and stars
    (circle(35, 33, 5.2), MOON, None),
    (circle(38.2, 31.4, 4.6), "#1A2746", None),  # bite out of the moon, in the sky's colour there
    (circle(70, 30, 0.9), STAR, None),
    (circle(76, 40, 0.7), STAR, None),
    (circle(30, 44, 0.7), STAR, None),
    # back wave
    ("M-6,74 q5,-3.4 10,0" + " t10,0" * 11 + " V112 H-6 Z", SEA_BACK, None),
    # mast and flag
    ("M53.1,22 h2.2 v43 h-2.2 Z", MAST, None),
    ("M55.3,22.2 h10 l-2.6,3.1 l2.6,3.1 h-10 Z", INK, None),
    (circle(59.6, 25.3, 1.15), SAIL, None),
    # top sail
    ("M46,30 Q54.2,28.6 62.4,30 Q61.4,33.2 62.4,36.2 Q54.2,35 46,36.2 Q47,33.2 46,30 Z", SAIL, None),
    # main sail with a shaded belly
    ("M39.5,38 Q54.2,35.6 68.9,38 Q66.6,47.5 68.9,57 Q54.2,54.6 39.5,57 Q41.8,47.5 39.5,38 Z", SAIL, None),
    ("M54.2,36.8 Q62,37 68.9,38 Q66.6,47.5 68.9,57 Q62,55.8 54.2,55.8 Z", SAIL_SHADE, None),
    # skull and crossbones on the main sail
    ("M48.6,52.2 L59.8,44.6", INK, 1.7),
    ("M48.6,44.6 L59.8,52.2", INK, 1.7),
    (circle(54.2, 46.6, 3.9), INK, None),
    ("M51.9,49.4 h4.6 v2.6 h-4.6 Z", INK, None),
    (circle(52.7, 46.4, 1.0), SAIL, None),
    (circle(55.7, 46.4, 1.0), SAIL, None),
    # hull, raised stern, rail and portholes
    ("M66,59.5 h12.5 l-0.8,5.5 h-11.7 Z", HULL_DARK, None),
    ("M29,64 H79.5 L73.5,77 H35.5 Z", HULL, None),
    ("M29,64 H79.5 L78.6,66 H29.9 Z", RAIL, None),
    ("M35.5,77 L34.2,74.2 H74.8 L73.5,77 Z", HULL_DARK, None),
    (circle(42, 70, 1.5), INK, None),
    (circle(50, 70, 1.5), INK, None),
    (circle(58, 70, 1.5), INK, None),
    (circle(66, 70, 1.5), INK, None),
    # front wave and foam
    ("M-6,79 q5,-3.4 10,0" + " t10,0" * 11 + " V112 H-6 Z", SEA_FRONT, None),
    ("M22,78.4 q2.5,-1.6 5,0 M41,78.4 q2.5,-1.6 5,0 M62,78.4 q2.5,-1.6 5,0 M80,78.4 q2.5,-1.6 5,0", FOAM, 1.2),
]

# Monochrome: the ship alone (Android tints it), no sky, moon or sea fill.
MONO = [
    ("M53.1,22 h2.2 v43 h-2.2 Z", None),
    ("M55.3,22.2 h10 l-2.6,3.1 l2.6,3.1 h-10 Z", None),
    ("M46,30 Q54.2,28.6 62.4,30 Q61.4,33.2 62.4,36.2 Q54.2,35 46,36.2 Q47,33.2 46,30 Z", None),
    ("M39.5,38 Q54.2,35.6 68.9,38 Q66.6,47.5 68.9,57 Q54.2,54.6 39.5,57 Q41.8,47.5 39.5,38 Z", None),
    ("M66,59.5 h12.5 l-0.8,5.5 h-11.7 Z", None),
    ("M29,64 H79.5 L73.5,77 H35.5 Z", None),
    ("M24,81 q5,-3.4 10,0 t10,0 t10,0 t10,0 t10,0 t10,0", 2.2),
]


def android_vector(items):
    out = ['<?xml version="1.0" encoding="utf-8"?>',
           '<!-- The "Stack" fork\'s pirate-ship icon (scripts made it; see the commit). 108dp adaptive grid. -->',
           '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
           '    android:width="108dp" android:height="108dp"',
           '    android:viewportWidth="108" android:viewportHeight="108">']
    for d, fill, stroke in items:
        if stroke:
            out.append(f'    <path android:pathData="{d}" android:fillColor="#00000000"'
                       f' android:strokeColor="{fill}" android:strokeWidth="{stroke}" android:strokeLineCap="round"/>')
        else:
            out.append(f'    <path android:pathData="{d}" android:fillColor="{fill}"/>')
    out.append('</vector>')
    return "\n".join(out) + "\n"


def svg(items, bg=True):
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">']
    if bg:
        out.append(f'<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{SKY_TOP}"/>'
                   f'<stop offset="1" stop-color="{SKY_BOTTOM}"/></linearGradient></defs><rect width="108" height="108" fill="url(#sky)"/>')
    for d, fill, stroke in items:
        if stroke:
            out.append(f'<path d="{d}" fill="none" stroke="{fill}" stroke-width="{stroke}" stroke-linecap="round"/>')
        else:
            out.append(f'<path d="{d}" fill="{fill}"/>')
    out.append('</svg>')
    return "".join(out)


repo, preview = sys.argv[1], sys.argv[2]
res = os.path.join(repo, "android/app/src/main/res/drawable")
open(os.path.join(res, "stack_ship.xml"), "w").write(android_vector(FOREGROUND))
open(os.path.join(res, "stack_ship_mono.xml"), "w").write(
    android_vector([(d, "#FFFFFFFF", s) for d, s in MONO]))
open(os.path.join(res, "stack_ship_bg.xml"), "w").write(
    '<?xml version="1.0" encoding="utf-8"?>\n<!-- The "Stack" fork\'s icon background: the night sky. -->\n'
    '<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">\n'
    f'    <gradient android:angle="270" android:startColor="{SKY_TOP}" android:endColor="{SKY_BOTTOM}"/>\n</shape>\n')
os.makedirs(preview, exist_ok=True)
open(os.path.join(preview, "ship.svg"), "w").write(svg(FOREGROUND))
open(os.path.join(preview, "ship_mono.svg"), "w").write(svg([(d, "#FFFFFF", s) for d, s in MONO], bg=False))
print("ok")
