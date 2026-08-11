#!/usr/bin/env python3
"""Generate the Chord Assist launcher icon (all mipmap densities).

Design rationale (accessibility-first):
- bold, high-contrast shapes that stay legible at 48 px and for
  low-vision users: dark stage background, warm amber marks;
- three guitar strings with three fingering dots (a chord diagram);
- the two upper dots deliberately form the braille letter C ("Chord");
- a resonance arc suggests sound rather than sight.

Requires matplotlib. Usage:
  python3 tool/generate_app_icon.py
Writes android/app/src/main/res/mipmap-*/ic_launcher.png and a 512 px
preview at docs/app_icon_512.png.
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Arc, Circle, FancyBboxPatch

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android" / "app" / "src" / "main" / "res"

BACKGROUND = "#120E18"   # app scaffold background (dark stage)
EDGE = "#2A2333"         # subtle rim so the tile reads on dark launchers
STRING = "#F2EDF7"       # app onSurface tone
AMBER = "#FFA726"        # app seed accent

SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def draw_icon(pixels: int, path: Path) -> None:
    fig = plt.figure(figsize=(pixels / 100, pixels / 100), dpi=100)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_alpha(0)

    # rounded tile with a small transparent margin
    margin = 0.035
    radius = 0.21
    ax.add_patch(FancyBboxPatch(
        (margin, margin), 1 - 2 * margin, 1 - 2 * margin,
        boxstyle=f"round,pad=0,rounding_size={radius}",
        facecolor=BACKGROUND, edgecolor=EDGE,
        linewidth=max(pixels * 0.012, 1.0), zorder=1))

    # three strings under a chord-diagram nut bar
    string_lw = max(pixels * 0.028, 1.2)
    for x in (0.30, 0.50, 0.70):
        ax.plot([x, x], [0.30, 0.80], color=STRING, alpha=0.82,
                linewidth=string_lw, solid_capstyle="round", zorder=2)
    ax.plot([0.25, 0.75], [0.80, 0.80], color=STRING, alpha=0.95,
            linewidth=string_lw * 1.6, solid_capstyle="round", zorder=2)

    # fingering dots; the upper pair is braille "C" (dots 1 and 4)
    dot_r = 0.085
    for cx, cy in ((0.30, 0.66), (0.70, 0.66), (0.50, 0.47)):
        ax.add_patch(Circle((cx, cy), dot_r + 0.018, color=BACKGROUND,
                            zorder=3))
        ax.add_patch(Circle((cx, cy), dot_r, color=AMBER, zorder=4))

    # resonance arc (sound, not sight)
    arc_lw = max(pixels * 0.030, 1.4)
    ax.add_patch(Arc((0.5, 0.315), 0.46, 0.24, theta1=195, theta2=345,
                     color=AMBER, linewidth=arc_lw, capstyle="round",
                     zorder=2))

    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, transparent=True)
    plt.close(fig)
    print(f"wrote {path} ({pixels}px)")


def main() -> None:
    for directory, pixels in SIZES.items():
        draw_icon(pixels, RES / directory / "ic_launcher.png")

    draw_icon(512, ROOT / "docs" / "app_icon_512.png")


if __name__ == "__main__":
    main()
