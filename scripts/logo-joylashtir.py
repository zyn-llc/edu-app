#!/usr/bin/env python3
"""
Logotipni butun loyihaga joylashtirish.

    python scripts/logo-joylashtir.py D:\\yuklamalar\\logo.png

BITTA kvadrat PNG (kamida 512x512, shaffof fonli) beriladi — skript qolgan
hamma o'lchamni o'zi chiqaradi va to'g'ri papkalarga qo'yadi.

## Nega skript

Logotip 12 ta joyda kerak: PWA (4 ta), favicon, Android mipmap (5 ta zichlik),
landing va Play Store. Qo'lda qilinsa bittasi doim unutiladi va ilova
yarim brendlangan holda chiqadi.

## Maskable haqida

Android ikonkani doira, kvadrat yoki tomchi shaklida KESADI. Shuning uchun
`Icon-maskable-*` da fon butun kvadratni to'ldiradi va belgi markazdagi
80% ichida turadi — aks holda chetlari kesiladi. Oddiy `Icon-*` da esa
shaffoflik saqlanadi.

## Nima QILINMAYDI

Play Store ikonkasi (512x512, shaffofliksiz) va feature grafik (1024x500)
avtomatik chiqarilmaydi: ular do'kon sahifasining dizayn elementi, oddiy
masshtablash yetarli emas.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow kerak:  pip install pillow")

ROOT = Path(__file__).resolve().parent.parent
MOBILE = ROOT / "mobile"
LANDING = ROOT / "landing"

# Brend foni — maskable variantlar uchun. `mobile/lib/theme/app_colors.dart`
# dagi `primary` bilan bir xil bo'lishi shart.
BRAND = (248, 114, 28, 255)

PWA = [
    ("web/icons/Icon-192.png", 192, False),
    ("web/icons/Icon-512.png", 512, False),
    ("web/icons/Icon-maskable-192.png", 192, True),
    ("web/icons/Icon-maskable-512.png", 512, True),
    ("web/favicon.png", 64, False),
]

# Android launcher. Zichlik nomi -> piksel.
MIPMAP = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def load(src: Path) -> Image.Image:
    im = Image.open(src).convert("RGBA")
    if im.width != im.height:
        # Kvadratga to'ldiramiz (kesmaymiz — logotipning bir qismi
        # yo'qolib qolmasin).
        side = max(im.size)
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
        im = canvas
        print(f"  ! kvadrat emas edi ({im.width}x{im.height}) — to'ldirildi")
    if im.width < 512:
        print(f"  ! ogohlantirish: manba {im.width}px — 512 dan kichik, "
              f"katta o'lchamlar xira chiqadi")
    return im


def render(src: Image.Image, size: int, maskable: bool) -> Image.Image:
    if maskable:
        # Xavfsiz zona: belgi markazdagi 80% ichida.
        inner = int(size * 0.8)
        mark = src.resize((inner, inner), Image.LANCZOS)
        out = Image.new("RGBA", (size, size), BRAND)
        off = (size - inner) // 2
        out.paste(mark, (off, off), mark)
        return out
    return src.resize((size, size), Image.LANCZOS)


def main() -> int:
    if len(sys.argv) < 2:
        return print(__doc__) or 1

    src_path = Path(sys.argv[1])
    if not src_path.exists():
        sys.exit(f"Fayl topilmadi: {src_path}")

    print(f"Manba: {src_path}")
    src = load(src_path)

    print("\nPWA va favicon:")
    for rel, size, maskable in PWA:
        dst = MOBILE / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        render(src, size, maskable).save(dst)
        print(f"  {rel}  ({size}x{size}{', maskable' if maskable else ''})")

    print("\nAndroid launcher:")
    res = MOBILE / "android/app/src/main/res"
    for folder, size in MIPMAP.items():
        d = res / folder
        d.mkdir(parents=True, exist_ok=True)
        # Launcher ikonkasi shaffof bo'lmasligi kerak — eski Android
        # versiyalarida shaffof fon qora bo'lib chiqadi.
        render(src, size, True).save(d / "ic_launcher.png")
        print(f"  {folder}/ic_launcher.png  ({size}x{size})")

    print("\nLanding:")
    (LANDING / "assets").mkdir(parents=True, exist_ok=True)
    render(src, 512, False).save(LANDING / "assets" / "logo.png")
    render(src, 64, False).save(LANDING / "assets" / "favicon.png")
    print("  assets/logo.png (512), assets/favicon.png (64)")

    print("\nPlay Store uchun (qo'lda tayyorlang):")
    play = ROOT / "docs" / "play-assets"
    play.mkdir(parents=True, exist_ok=True)
    # Shaffofliksiz — Play Console shaffof PNG'ni rad etadi.
    icon = Image.new("RGB", (512, 512), BRAND[:3])
    mark = src.resize((410, 410), Image.LANCZOS)
    icon.paste(mark, (51, 51), mark)
    icon.save(play / "play-icon-512.png")
    print(f"  docs/play-assets/play-icon-512.png (shaffofliksiz)")
    print("  feature grafik 1024x500 — Figma'da qo'lda")

    print("\nKeyingi qadamlar:")
    print("  1. cd mobile && flutter clean")
    print("  2. bash deploy.sh app     (web ikonkalari)")
    print("  3. bash deploy.sh landing (agar landing chiqarilgan bo'lsa)")
    print("  4. Brauzerda: F12 -> Application -> Clear site data")
    print("     (favicon eng qattiq keshlanadigan fayllardan biri)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
