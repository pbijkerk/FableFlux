#!/usr/bin/env python3
"""Genereer de FableFlux-app-iconen (1024x1024) voor alle themavarianten.

Tekent op 4x (4096x4096) en schaalt terug met LANCZOS voor scherpe randen.
Draai vanuit de projectmap:  python3 generate_icon.py

De kleuren horen gelijk te blijven aan `AppTheme` in
FableFlux/DesignSystem/AppTheme.swift (logo in de instellingen).
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw

FINAL = 1024
SCALE = 4
S = FINAL * SCALE

ASSETS = Path(__file__).parent / "FableFlux" / "Assets.xcassets"

# asset-naam: (ring, segment, achtergrond)
VARIANTS = {
    "AppIcon": (0x1E7BF0, 0x0B5CC4, 0x061539),  # Origineel (blauw)
    "AppIcon-Oceaan": (0x14B8A6, 0x0F766E, 0x042F2E),
    "AppIcon-Nacht": (0x8B5CF6, 0x6D28D9, 0x1E1B4B),
    "AppIcon-Kampvuur": (0xF97316, 0xC2410C, 0x1C1917),
    "AppIcon-Inkt": (0xEC4899, 0xBE185D, 0x2A0A1F),
    "AppIcon-Woud": (0x10B981, 0x047857, 0x022C22),
    "AppIcon-Perkament": (0xF59E0B, 0xB45309, 0x0F172A),
}


def rgb(hex_value: int) -> tuple[int, int, int]:
    return ((hex_value >> 16) & 0xFF, (hex_value >> 8) & 0xFF, hex_value & 0xFF)


def render(ring: int, segment: int, background: int) -> Image.Image:
    # Vierkant en ondoorzichtig: iOS rondt de hoeken zelf af.
    img = Image.new("RGB", (S, S), rgb(background))
    draw = ImageDraw.Draw(img)

    c = S / 2
    outer = S * 0.30  # buitenstraal ring
    inner = outer * 20 / 46  # gat in het midden
    gap = outer * 5 / 46  # breedte van de twee diagonale sneden

    box = [(c - outer, c - outer), (c + outer, c + outer)]
    draw.ellipse(box, fill=rgb(ring))
    # Donkerder segment van linksboven (225°) tot rechts (360°), met de klok mee.
    draw.pieslice(box, start=225, end=360, fill=rgb(segment))
    draw.ellipse([(c - inner, c - inner), (c + inner, c + inner)], fill=rgb(background))

    # Diagonale sneden linksboven en rechtsonder.
    d = outer * 0.75
    draw.line([(c - d - gap, c - d - gap), (c - inner * 0.6, c - inner * 0.6)], fill=rgb(background), width=int(gap))
    draw.line([(c + inner * 0.6, c + inner * 0.6), (c + d + gap, c + d + gap)], fill=rgb(background), width=int(gap))

    return img.resize((FINAL, FINAL), Image.LANCZOS)


def main() -> None:
    for name, colors in VARIANTS.items():
        folder = ASSETS / f"{name}.appiconset"
        folder.mkdir(exist_ok=True)
        for old in folder.glob("*.png"):
            old.unlink()
        render(*colors).save(folder / f"{name}.png")
        contents = {
            "images": [{"filename": f"{name}.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1},
        }
        (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
        print(f"✓ {folder.relative_to(Path(__file__).parent)}")


if __name__ == "__main__":
    main()
