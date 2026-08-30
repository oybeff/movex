#!/usr/bin/env python3
"""
Texnika turlari uchun ikonkalarni yasaydi.

Har bir mashina primitivlar ro'yxati sifatida tasvirlangan (to'rtburchak,
doira, ko'pburchak, chiziq) va shu bitta tavsifdan IKKI xil fayl chiqadi:

  assets/equipment_types/<code>.svg   — interfeys uchun, currentColor bilan
                                        bo'yaladi (katalog, kartochkalar,
                                        bildirishnomalar)
  assets/equipment_types/<code>.png   — Yandex xaritadagi marker uchun:
                                        yashil doira ichida oq belgi.
                                        BitmapDescriptor faqat rasm qabul qiladi.

Nega tayyor to'plam emas: bepul MIT to'plamlarda (Tabler va boshqalar) bizga
kerak 17 turdan atigi 6 tasi bor — greyder, katok, yamobur, betonnasos,
avtovishka uchun umuman ikonka yo'q. Qolganlari esa atribut talab qiladi.

Ishga tushirish:
    python3 tool/generate_equipment_icons.py

Ikonkani o'zgartirish: pastdagi MACHINES ichidagi primitivlarni tahrirlab,
skriptni qayta ishga tushiring. Koordinatalar 64x64 maydonda, yer chizig'i
y=56 da.
"""
import os
from math import cos, radians, sin

try:
    from PIL import Image, ImageDraw
except ImportError:
    raise SystemExit("Pillow kerak:  pip install Pillow")

SIZE = 64                     # SVG viewBox va chizma koordinatalari
# Xarita markeri. Yandex xaritada rasm `scale` ga ko'paytirilib chiziladi:
# 256 * 0.45 ≈ 115 px — eski excavator.png (1009 px * 0.15 ≈ 150 px) dan
# bir oz kichikroq, lekin yuqori zichlikdagi ekranda ham tiniq.
PNG_SIZE = 256
MARKER_SCALE_HINT = 0.45      # client_main_page.dart dagi PlacemarkIconStyle.scale
SUPERSAMPLE = 3               # PNG ni silliq qilish uchun

MARKER_FILL = (46, 204, 113)      # AppColors.primaryGreen
MARKER_STROKE = (255, 255, 255)
GLYPH_ON_MARKER = (255, 255, 255)

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "assets", "equipment_types")


# ---------------------------------------------------------------- primitivlar

def rect(x, y, w, h, r=0):
    return ("rect", (x, y, w, h, r))


def circle(cx, cy, r):
    return ("circle", (cx, cy, r))


def ring(cx, cy, r, w):
    """G'ildirak: to'ldirilgan doira ichida teshik o'rniga qalin halqa."""
    return ("ring", (cx, cy, r, w))


def poly(points):
    return ("poly", tuple(points))


def line(x1, y1, x2, y2, w):
    return ("line", (x1, y1, x2, y2, w))


def wheels(xs, cy, r, w=None):
    """Bir nechta g'ildirak bir qatorda."""
    out = []
    for x in xs:
        out.append(ring(x, cy, r, w or max(2, r * 0.55)))
    return out


def tracks(x, y, w, h):
    """Kraul izlar: cho'zilgan yumaloq to'rtburchak va ichidagi g'ildiraklar."""
    r = h / 2
    parts = [rect(x, y, w, h, r)]
    return parts


def boom(points, w=4):
    """Siniq strela — ketma-ket qalin chiziqlar."""
    out = []
    for i in range(len(points) - 1):
        (x1, y1), (x2, y2) = points[i], points[i + 1]
        out.append(line(x1, y1, x2, y2, w))
    return out


GROUND = 56


# ------------------------------------------------------------------ mashinalar

MACHINES = {
    # Ekskavator: izlar, aylanuvchi korpus, pastga egilgan strela va cho'mich
    "excavator": lambda: [
        *tracks(6, 46, 40, 10),
        *wheels([13, 22, 31, 40], 51, 3.2, 1.6),
        rect(14, 32, 26, 13, 2.5),
        rect(16, 22, 12, 11, 2),
        *boom([(36, 30), (50, 16), (56, 30)], 4),
        poly([(51, 30), (61, 28), (59, 38), (50, 38)]),
    ],

    # Mini ekskavator: o'sha sxema, lekin sezilarli darajada past va ixcham —
    # katalogda kattasidan farqlanib turishi kerak
    "mini_excavator": lambda: [
        *tracks(10, 46, 30, 9),
        *wheels([16, 24, 32], 50.5, 2.6, 1.4),
        rect(15, 34, 20, 12, 2.5),
        rect(17, 25, 10, 9, 2),
        *boom([(31, 32), (41, 24), (45, 33)], 3),
        poly([(42, 33), (50, 31), (49, 39), (42, 39)]),
    ],

    # Ekskavator-yuklagich: oldida yuklash cho'michi, orqasida ekskavator strelasi
    "backhoe_loader": lambda: [
        *wheels([15, 47], 48, 8, 3.2),
        rect(20, 34, 24, 11, 2.5),
        rect(26, 24, 12, 11, 2),
        # old cho'mich
        *boom([(22, 38), (10, 34)], 3.5),
        poly([(11, 30), (4, 32), (4, 42), (11, 40)]),
        # orqa strela
        *boom([(42, 32), (52, 22), (58, 34)], 3.5),
        poly([(54, 34), (62, 33), (61, 41), (53, 40)]),
    ],

    # Buldozer: asosiy belgisi — oldindagi BALAND tig'. Shuning uchun tig'
    # izlardan aniq ajratilgan va deyarli butun balandlikni egallaydi.
    "bulldozer": lambda: [
        *tracks(18, 42, 36, 13),
        *wheels([25, 34, 43, 50], 48.5, 3.6, 1.8),
        rect(24, 30, 26, 12, 2.5),
        rect(28, 20, 14, 11, 2),
        poly([(3, 26), (13, 30), (13, 56), (3, 60)]),
        line(13, 44, 20, 42, 3),
    ],

    # Frontal yuklagich: ekskavator-yuklagichdan farqi — orqada strela YO'Q,
    # oldida esa juda katta cho'mich
    "front_loader": lambda: [
        # cho'mich old g'ildirak bilan QO'SHILIB ketmasligi kerak — shuning uchun
        # g'ildiraklar o'ngga surilgan, cho'mich esa ular bilan kesishmaydi
        *wheels([28, 52], 47, 8, 3.2),
        rect(36, 30, 20, 14, 2.5),
        rect(38, 20, 13, 11, 2),
        *boom([(38, 36), (21, 29)], 4),
        poly([(21, 24), (3, 30), (3, 44), (21, 38)]),
    ],

    # Avtokran: yuk mashinasi shassisi va uzun teleskopik strela
    "truck_crane": lambda: [
        *wheels([13, 26, 40, 52], 49, 6.5, 2.6),
        rect(8, 34, 50, 10, 2),
        rect(9, 24, 13, 11, 2),
        # strela
        *boom([(28, 34), (58, 12)], 5),
        line(58, 12, 58, 24, 2),
        circle(58, 26, 3),
        # tayanchlar
        line(10, 44, 6, 52, 2.5),
        line(56, 44, 60, 52, 2.5),
    ],

    # Manipulyator: kabinadan keyin tik ustun va undan Z shaklida bukilgan
    # kran — aynan shu bukilish uni avtokrandan farqlaydi
    "manipulator": lambda: [
        *wheels([14, 32, 50], 49, 6.5, 2.6),
        rect(5, 24, 14, 12, 2),
        rect(21, 36, 39, 6, 1.5),
        rect(36, 27, 23, 9, 1.5),
        rect(23, 14, 5, 22, 1),
        *boom([(25, 16), (40, 10), (53, 19)], 3.5),
        line(53, 19, 53, 26, 2),
        circle(53, 28, 2.5),
    ],

    # Avtovishka: teleskopik strela va tepadagi savat
    "aerial_platform": lambda: [
        *wheels([14, 30, 48], 49, 6.5, 2.6),
        rect(8, 24, 14, 12, 2),
        rect(24, 34, 34, 9, 2),
        *boom([(30, 34), (52, 14)], 4),
        # savat
        rect(48, 6, 14, 9, 1.5),
        line(10, 43, 6, 52, 2.5),
        line(56, 43, 60, 52, 2.5),
    ],

    # Samosval: ko'tarilgan kuzov
    "dump_truck": lambda: [
        *wheels([16, 34, 48], 49, 7, 2.8),
        rect(6, 26, 15, 16, 2),
        # ko'tarilgan kuzov
        poly([(22, 34), (60, 34), (60, 42), (22, 42)]),
        poly([(24, 30), (62, 14), (64, 22), (26, 36)]),
        line(24, 34, 24, 42, 2),
    ],

    # Beton aralashtirgich: yotiq baraban
    "concrete_mixer": lambda: [
        *wheels([14, 32, 48], 49, 7, 2.8),
        rect(4, 26, 14, 16, 2),
        rect(20, 38, 40, 5, 1.5),
        # baraban
        poly([(24, 34), (34, 18), (54, 18), (58, 34)]),
        line(30, 22, 52, 22, 2),
        line(27, 28, 56, 28, 2),
    ],

    # Betonnasos: strela tik ko'tarilib, oldinga oshib tushadi va uchida
    # beton quyiladigan tik quvur bo'ladi — shu siluet uni ajratib turadi
    "concrete_pump": lambda: [
        *wheels([13, 27, 44], 49, 6.5, 2.6),
        rect(5, 28, 14, 14, 2),
        rect(21, 34, 36, 9, 2),
        *boom([(26, 34), (26, 11), (46, 5), (59, 16)], 3.5),
        line(59, 16, 59, 29, 2.5),
        line(7, 43, 3, 52, 2.5),
        line(55, 43, 59, 52, 2.5),
    ],

    # Greyder: uzun burun, orqada kabina va tandem g'ildiraklar, o'rtada —
    # ramaga osilgan qiya tig'
    "grader": lambda: [
        *wheels([9, 46, 58], 51, 5.5, 2.2),
        # ingichka uzun rama — tig' undan aniq ajralib tursin
        rect(5, 31, 55, 4, 2),
        rect(41, 18, 19, 13, 2),
        rect(44, 11, 13, 8, 1.5),
        # asosiy belgi: ramaga osilgan katta qiya tig'
        poly([(15, 38), (40, 38), (37, 50), (12, 50)]),
        line(26, 34, 26, 41, 2.5),
    ],

    # Katok: oldinda katta silliq baraban
    "roller": lambda: [
        rect(6, 38, 20, 18, 8),
        *wheels([50], 48, 8, 3.2),
        rect(24, 30, 28, 12, 2.5),
        rect(30, 20, 14, 11, 2),
        line(26, 44, 42, 44, 2.5),
    ],

    # Yamobur: vertikal machta va shnek
    "auger_drill": lambda: [
        *wheels([14, 30, 48], 49, 6.5, 2.6),
        rect(6, 28, 14, 14, 2),
        rect(22, 34, 36, 9, 2),
        # machta
        rect(44, 8, 6, 30, 1.5),
        # shnek
        line(47, 20, 47, 54, 2.5),
        *[line(43, y, 51, y + 4, 2) for y in (26, 34, 42)],
    ],

    # Tral / evakuator: qiya platforma
    "tow_truck": lambda: [
        *wheels([14, 34, 50], 49, 7, 2.8),
        rect(4, 24, 15, 18, 2),
        poly([(21, 42), (62, 26), (62, 34), (21, 46)]),
        line(21, 42, 21, 30, 2.5),
        *boom([(21, 32), (34, 26)], 3),
    ],

    # Kompressor: pritsepdagi quti
    "compressor": lambda: [
        rect(12, 26, 40, 22, 3),
        *wheels([22, 42], 51, 5, 2),
        line(12, 36, 2, 40, 2.5),
        line(20, 32, 44, 32, 2),
        line(20, 40, 34, 40, 2),
    ],

    # Boshqa texnika: umumiy belgi — g'ildirak va kalit
    "other": lambda: [
        ring(24, 34, 14, 5),
        circle(24, 34, 4),
        *boom([(35, 43), (52, 54)], 5),
        poly([(48, 14), (56, 14), (56, 22), (52, 26), (48, 22)]),
        line(52, 24, 52, 40, 4),
    ],
}


# --------------------------------------------------------------------- chizish

def to_svg(parts) -> str:
    body = []
    for kind, args in parts:
        if kind == "rect":
            x, y, w, h, r = args
            rx = f' rx="{r}"' if r else ""
            body.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}"{rx}/>')
        elif kind == "circle":
            cx, cy, r = args
            body.append(f'<circle cx="{cx}" cy="{cy}" r="{r}"/>')
        elif kind == "ring":
            cx, cy, r, w = args
            body.append(
                f'<circle cx="{cx}" cy="{cy}" r="{r - w / 2}" fill="none" '
                f'stroke="currentColor" stroke-width="{w}"/>'
            )
        elif kind == "poly":
            pts = " ".join(f"{x},{y}" for x, y in args)
            body.append(f'<polygon points="{pts}"/>')
        elif kind == "line":
            x1, y1, x2, y2, w = args
            body.append(
                f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" '
                f'stroke="currentColor" stroke-width="{w}" stroke-linecap="round"/>'
            )
    shapes = "\n  ".join(body)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" '
        f'fill="currentColor">\n  {shapes}\n</svg>\n'
    )


def draw_parts(draw, parts, color, k):
    """Primitivlarni Pillow bilan chizish. k — masshtab koeffitsienti."""
    def s(v):
        return v * k

    for kind, args in parts:
        if kind == "rect":
            x, y, w, h, r = args
            box = [s(x), s(y), s(x + w), s(y + h)]
            if r:
                draw.rounded_rectangle(box, radius=s(r), fill=color)
            else:
                draw.rectangle(box, fill=color)
        elif kind == "circle":
            cx, cy, r = args
            draw.ellipse([s(cx - r), s(cy - r), s(cx + r), s(cy + r)], fill=color)
        elif kind == "ring":
            cx, cy, r, w = args
            rr = r - w / 2
            draw.ellipse(
                [s(cx - rr), s(cy - rr), s(cx + rr), s(cy + rr)],
                outline=color, width=max(1, int(s(w))),
            )
        elif kind == "poly":
            draw.polygon([(s(x), s(y)) for x, y in args], fill=color)
        elif kind == "line":
            x1, y1, x2, y2, w = args
            draw.line([s(x1), s(y1), s(x2), s(y2)], fill=color,
                      width=max(1, int(s(w))), joint="curve")
            # uchlarini yumaloq qilish
            rr = w / 2
            for cx, cy in ((x1, y1), (x2, y2)):
                draw.ellipse([s(cx - rr), s(cy - rr), s(cx + rr), s(cy + rr)], fill=color)


def to_png(parts) -> Image.Image:
    """Xarita markeri: yashil doira, oq hoshiya, ichida oq belgi."""
    k = PNG_SIZE * SUPERSAMPLE / SIZE
    canvas = PNG_SIZE * SUPERSAMPLE
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    pad = canvas * 0.02
    draw.ellipse([pad, pad, canvas - pad, canvas - pad],
                 fill=MARKER_FILL, outline=MARKER_STROKE,
                 width=int(canvas * 0.045))

    # belgini doira ichiga sig'dirish uchun kichraytirib, markazga surish
    glyph = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw_parts(ImageDraw.Draw(glyph), parts, GLYPH_ON_MARKER, k)
    inner = int(canvas * 0.62)
    glyph = glyph.resize((inner, inner), Image.LANCZOS)
    off = (canvas - inner) // 2
    img.alpha_composite(glyph, (off, off))

    return img.resize((PNG_SIZE, PNG_SIZE), Image.LANCZOS)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for code, build in MACHINES.items():
        parts = build()

        with open(os.path.join(OUT_DIR, f"{code}.svg"), "w", encoding="utf-8") as f:
            f.write(to_svg(parts))

        to_png(parts).save(os.path.join(OUT_DIR, f"{code}.png"))

    print(f"{len(MACHINES)} ta tur uchun ikonka yasaldi: {OUT_DIR}")
    print("SVG — interfeys uchun, PNG — xarita markerlari uchun.")


if __name__ == "__main__":
    main()
