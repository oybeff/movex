#!/usr/bin/env python3
"""
Ilova ikonkalarini logotipdan yasaydi.

Nega skript. Ikonka o'nlab o'lchamda kerak: Android beshta mipmap,
iOS yigirmadan ortiq fayl. Ularni qo'lda qirqish — bir marta qilinadi va
keyin logotip o'zgarganda yarmi eski bo'lib qoladi. Bu yerda esa bitta
manbadan hammasi qayta yasaladi.

Manba — logotipning to'liq varianti (belgi + yozuv). Ikonka uchun faqat
BELGI kesib olinadi: telefon ekranida 48 nuqtali kvadratda "MovexGo"
yozuvi baribir o'qilmaydi, faqat rasmni loyqalatadi. Yozuv qayerda
tugashini skript o'zi topadi — oq satrlar bo'yicha.

iOS ikonkasida SHAFFOFLIK BO'LMAYDI: App Store alfa kanalli ikonkani
qabul qilmaydi, shuning uchun fon oq qilib to'ldiriladi.

Ishga tushirish (mobile/ ichidan):
    python3 tool/generate_app_icons.py [manba.png]
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MOBILE = os.path.dirname(HERE)

DEFAULT_SOURCE = os.path.join(MOBILE, "assets", "logo_full.png")

#: Belgi atrofidagi bo'sh joy, kvadrat tomonining ulushi
PADDING = 0.10

ANDROID_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

#: iOS ikonkalari: fayl nomi → tomoni (nuqtada). Ro'yxat
#: Assets.xcassets/AppIcon.appiconset/Contents.json bilan mos.
IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def ink_bands(image, threshold=235, step=3):
    """Rasm bor satrlar oralig'i: [(y1, y2), ...]. Oq fon — bo'sh."""
    width, height = image.size
    pixels = image.load()

    def has_ink(y):
        for x in range(0, width, step):
            r, g, b = pixels[x, y]
            if r < threshold or g < threshold or b < threshold:
                return True
        return False

    bands, start = [], None
    for y in range(height):
        if has_ink(y) and start is None:
            start = y
        elif not has_ink(y) and start is not None:
            bands.append((start, y - 1))
            start = None
    if start is not None:
        bands.append((start, height - 1))
    return bands


def horizontal_bounds(image, top, bottom, threshold=235, step=2):
    """Belgining chap va o'ng chegarasi."""
    width = image.size[0]
    pixels = image.load()
    left, right = width, 0
    for y in range(top, bottom + 1, step):
        for x in range(width):
            r, g, b = pixels[x, y]
            if r < threshold or g < threshold or b < threshold:
                left = min(left, x)
                right = max(right, x)
                break
        for x in range(width - 1, -1, -1):
            r, g, b = pixels[x, y]
            if r < threshold or g < threshold or b < threshold:
                right = max(right, x)
                break
    return left, right


def extract_mark(source_path):
    """Logotipdan faqat belgini kvadrat qilib kesib oladi."""
    image = Image.open(source_path).convert("RGB")

    bands = ink_bands(image)
    if not bands:
        raise SystemExit("Rasmda hech narsa topilmadi — manba oq varaqmi?")

    # Birinchi polosa — belgi, qolganlari yozuv. Ikkinchi va uchinchi
    # polosa ("MovexGo" va "POWER IN MOTION") ikonkaga kirmaydi.
    top, bottom = bands[0]
    left, right = horizontal_bounds(image, top, bottom)

    mark = image.crop((left, top, right + 1, bottom + 1))

    side = int(max(mark.size) * (1 + PADDING * 2))
    canvas = Image.new("RGB", (side, side), "white")
    canvas.paste(mark, ((side - mark.size[0]) // 2, (side - mark.size[1]) // 2))
    return canvas


def save_square(image, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.resize((size, size), Image.LANCZOS).save(path, "PNG")


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not os.path.exists(source):
        raise SystemExit(f"Manba topilmadi: {source}")

    mark = extract_mark(source)
    print(f"belgi kesib olindi: {mark.size[0]}×{mark.size[1]}")

    # Ilova ichida ishlatiladigan variantlar
    assets = os.path.join(MOBILE, "assets")
    save_square(mark, os.path.join(assets, "logo_mark.png"), 512)
    print("assets/logo_mark.png")

    for folder, size in ANDROID_SIZES.items():
        save_square(
            mark,
            os.path.join(MOBILE, "android", "app", "src", "main", "res",
                         folder, "ic_launcher.png"),
            size,
        )
    print(f"Android: {len(ANDROID_SIZES)} ta mipmap")

    icons_dir = os.path.join(MOBILE, "ios", "Runner", "Assets.xcassets",
                             "AppIcon.appiconset")
    if os.path.isdir(icons_dir):
        for name, size in IOS_SIZES.items():
            save_square(mark, os.path.join(icons_dir, name), size)
        print(f"iOS: {len(IOS_SIZES)} ta ikonka")
    else:
        print("iOS ikonkalar papkasi yo'q — o'tkazib yuborildi")


if __name__ == "__main__":
    main()
