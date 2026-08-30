#!/usr/bin/env python3
"""
Texnika turlari uchun RANGLI ikonkalar.

Har bir mashina primitivlar ro'yxati sifatida tasvirlangan va shu bitta
tavsifdan ikki xil fayl chiqadi:

  assets/equipment_types/<code>.svg   — interfeys uchun (katalog, kartochkalar,
                                        bildirishnomalar, tur tanlash)
  assets/equipment_types/<code>.png   — xarita markeri: oq yumaloq kvadrat,
                                        pastida yashil uchburchak, ichida mashina

Ranglar haqiqiy texnikadan olingan: sariq korpus, qora oyna, qora g'ildiraklar
kulrang disk bilan, po'lat rangli strela va gidravlika. Kichik o'lchamda ham
mashina taniladigan bo'lishi uchun asosiy shakllarda quyuq hoshiya bor.

Ishga tushirish:
    python3 tool/generate_equipment_icons.py

Koordinatalar 64x64 maydonda, yer chizig'i y=56 da.
"""
import os

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    raise SystemExit("Pillow kerak:  pip install Pillow")

SIZE = 64                 # chizma koordinatalari va SVG viewBox

# Xarita markeri: oq kvadrat + pastdagi uchburchak.
# Kvadrat 256x256, uchburchak yana 52 px — jami 256x308.
PNG_W, PNG_H = 256, 308
MARKER_SQUARE = 256
MARKER_TAIL = 52
SUPERSAMPLE = 3

# --------------------------------------------------------------------- palitra

YELLOW      = "#F2B10A"   # asosiy korpus
YELLOW_DK   = "#C98D05"   # soya, korpusning pastki qismi
ORANGE      = "#E2631F"   # yuk mashinalari kabinasi
ORANGE_DK   = "#B44C14"
DARK        = "#23282E"   # g'ildiraklar, izlar, shassi
DARK_2      = "#33393F"   # kabina ramkasi
GLASS       = "#5B87AD"   # oyna
GLASS_LT    = "#8FBCDC"   # oynadagi yorug'lik
STEEL       = "#8A939B"   # strela, gidravlika, baraban
STEEL_DK    = "#5E666D"
HUB         = "#B9C0C6"   # g'ildirak diski
WHITE       = "#FFFFFF"
GREEN       = "#2ECC71"   # marker dumi (AppColors.primaryGreen)
BORDER      = "#E3E6E8"   # marker kvadratining hoshiyasi

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "assets", "equipment_types")


# ---------------------------------------------------------------- primitivlar
# Har biri: (tur, argumentlar, to'ldirish rangi, hoshiya rangi yoki None)

def rect(x, y, w, h, r=0, c=YELLOW, stroke=None):
    return ("rect", (x, y, w, h, r), c, stroke)


def circle(cx, cy, r, c=DARK, stroke=None):
    return ("circle", (cx, cy, r), c, stroke)


def poly(points, c=YELLOW, stroke=None):
    return ("poly", tuple(points), c, stroke)


def line(x1, y1, x2, y2, w, c=STEEL):
    return ("line", (x1, y1, x2, y2, w), c, None)


# --------------------------------------------------------------- yig'ma qismlar

def wheel(cx, cy, r):
    """Shina + disk. Ikki doira — kichkina o'lchamda ham g'ildirakka o'xshaydi."""
    return [
        circle(cx, cy, r, DARK),
        circle(cx, cy, r * 0.45, HUB),
    ]


def wheels(xs, cy, r):
    out = []
    for x in xs:
        out += wheel(x, cy, r)
    return out


def track(x, y, w, h):
    """Kraul iz: quyuq yumaloq to'rtburchak va ichidagi g'ildirakchalar."""
    parts = [rect(x, y, w, h, h / 2, DARK)]
    step = w / 5
    for i in range(1, 5):
        parts.append(circle(x + step * i, y + h / 2, h * 0.22, HUB))
    return parts


def cab(x, y, w, h, body=YELLOW):
    """Kabina: korpus + oyna + oynadagi yorug'lik."""
    return [
        rect(x, y, w, h, 2, body, DARK),
        rect(x + 1.6, y + 1.6, w - 3.2, h * 0.5, 1, GLASS),
        rect(x + 2.2, y + 2.2, (w - 3.2) * 0.4, h * 0.5 - 1.2, 0.6, GLASS_LT),
    ]


def boom(points, w=4, c=YELLOW):
    """Strela: bo'g'inlar + tutashgan joylarda shtiftlar."""
    out = []
    for i in range(len(points) - 1):
        (x1, y1), (x2, y2) = points[i], points[i + 1]
        out.append(line(x1, y1, x2, y2, w, c))
    for x, y in points:
        out.append(circle(x, y, w * 0.42, STEEL_DK))
    return out


def bucket(points):
    """Cho'mich: po'lat korpus, quyuq hoshiya."""
    return [poly(points, STEEL, DARK)]


# ------------------------------------------------------------------ mashinalar

MACHINES = {
    # Ekskavator: izlar, sariq korpus, kabina, strela va cho'mich
    "excavator": lambda: [
        *track(6, 46, 40, 10),
        rect(13, 31, 28, 14, 3, YELLOW, DARK),
        rect(13, 41, 28, 4, 1.5, YELLOW_DK),
        *cab(15, 21, 13, 11),
        rect(35, 27, 5, 5, 1, DARK_2),           # dvigatel bloki
        *boom([(37, 30), (50, 16), (56, 29)], 4.5),
        line(41, 24, 47, 29, 2, STEEL_DK),        # gidrosilindr
        *bucket([(51, 29), (62, 27), (60, 38), (50, 38)]),
    ],

    # Mini ekskavator: past va ixcham
    "mini_excavator": lambda: [
        *track(11, 47, 28, 8),
        rect(15, 34, 20, 12, 2.5, YELLOW, DARK),
        *cab(16, 25, 10, 9),
        *boom([(32, 32), (41, 24), (45, 32)], 3.4),
        *bucket([(42, 32), (51, 30), (50, 39), (42, 39)]),
    ],

    # Ekskavator-yuklagich: oldida cho'mich, orqasida strela
    "backhoe_loader": lambda: [
        *wheels([15], 47, 9),
        *wheels([47], 48, 8),
        rect(20, 33, 25, 12, 2.5, YELLOW, DARK),
        *cab(26, 22, 13, 11),
        *boom([(22, 37), (11, 33)], 3.6),
        *bucket([(12, 29), (3, 31), (3, 42), (12, 40)]),
        *boom([(43, 31), (52, 21), (58, 33)], 3.6),
        *bucket([(54, 33), (62, 32), (61, 41), (53, 40)]),
    ],

    # Buldozer: oldindagi baland tig'
    "bulldozer": lambda: [
        *track(18, 42, 36, 13),
        rect(24, 29, 26, 13, 2.5, YELLOW, DARK),
        *cab(28, 19, 15, 11),
        poly([(3, 25), (13, 29), (13, 55), (3, 59)], STEEL, DARK),
        line(13, 43, 21, 41, 3, YELLOW),
        line(13, 34, 24, 32, 2.4, STEEL_DK),
    ],

    # Frontal yuklagich: katta cho'mich oldinda
    "front_loader": lambda: [
        *wheels([28, 52], 47, 8.5),
        rect(34, 29, 23, 15, 2.5, YELLOW, DARK),
        *cab(38, 19, 14, 11),
        *boom([(38, 35), (21, 28)], 4.2),
        *bucket([(22, 23), (3, 29), (3, 44), (22, 38)]),
    ],

    # Avtokran: uzun teleskopik strela
    "truck_crane": lambda: [
        *wheels([13, 26, 41, 53], 49, 6.5),
        rect(7, 33, 52, 11, 2, ORANGE, DARK),
        rect(7, 40, 52, 4, 1.5, ORANGE_DK),
        *cab(8, 23, 13, 11, ORANGE),
        *boom([(27, 33), (58, 11)], 5, STEEL),
        line(58, 11, 58, 23, 2, DARK),
        circle(58, 25, 3, STEEL_DK),
        line(9, 44, 5, 52, 2.6, DARK),
        line(57, 44, 61, 52, 2.6, DARK),
    ],

    # Manipulyator: tik ustun va bukilgan kran
    "manipulator": lambda: [
        *wheels([14, 32, 50], 49, 6.5),
        *cab(4, 23, 15, 13, ORANGE),
        rect(21, 36, 40, 6, 1.5, DARK_2),
        rect(36, 26, 24, 10, 1.5, YELLOW, DARK),
        rect(23, 13, 5, 23, 1, STEEL, DARK),
        *boom([(25, 15), (40, 9), (53, 18)], 3.6, STEEL),
        line(53, 18, 53, 25, 2, DARK),
        circle(53, 27, 2.6, STEEL_DK),
    ],

    # Avtovishka: strela va tepadagi savat
    "aerial_platform": lambda: [
        *wheels([14, 30, 48], 49, 6.5),
        *cab(5, 23, 15, 13, ORANGE),
        rect(22, 34, 37, 9, 2, YELLOW, DARK),
        *boom([(29, 33), (51, 13)], 4.4, STEEL),
        # savat — sariq, quyuq hoshiya bilan, tepada aniq ko'rinadi
        rect(45, 4, 16, 10, 1.5, YELLOW, DARK),
        rect(45, 4, 16, 3.5, 1, YELLOW_DK),
        line(9, 43, 5, 52, 2.6, DARK),
        line(57, 43, 61, 52, 2.6, DARK),
    ],

    # Samosval: ko'tarilgan kuzov
    "dump_truck": lambda: [
        *wheels([16, 35, 49], 49, 7),
        *cab(5, 24, 16, 17, ORANGE),
        rect(22, 35, 38, 7, 1.5, DARK_2),
        poly([(24, 31), (62, 13), (64, 22), (26, 37)], YELLOW, DARK),
        line(24, 32, 24, 42, 2.4, DARK),
    ],

    # Beton aralashtirgich: yotiq baraban
    "concrete_mixer": lambda: [
        *wheels([14, 33, 49], 49, 7),
        *cab(3, 25, 15, 16, ORANGE),
        rect(19, 38, 42, 5, 1.5, DARK_2),
        # baraban: bochkasimon, o'ng tomonda tarnov. Qiya chiziqlar aylanishni
        # ko'rsatadi — tekis chiziqlar bilan u panjaraga o'xshab qolgan edi.
        poly([(25, 34), (30, 19), (52, 17), (56, 34)], STEEL, DARK),
        line(34, 20, 31, 33, 1.8, STEEL_DK),
        line(41, 19, 39, 33, 1.8, STEEL_DK),
        line(48, 18, 47, 33, 1.8, STEEL_DK),
        poly([(55, 22), (62, 26), (62, 32), (56, 30)], STEEL_DK),
    ],

    # Betonnasos: strela ko'tarilib, oldinga oshib tushadi
    "concrete_pump": lambda: [
        *wheels([13, 28, 45], 49, 6.5),
        *cab(3, 27, 15, 15, ORANGE),
        rect(20, 34, 39, 9, 2, YELLOW, DARK),
        # strela — qalinroq va sariq: kulrang ingichka chiziq ko'rinmasdi
        *boom([(26, 34), (26, 9), (46, 3), (59, 14)], 4.2, YELLOW),
        line(59, 14, 59, 30, 3, STEEL_DK),
        line(6, 43, 2, 52, 2.6, DARK),
        line(56, 43, 60, 52, 2.6, DARK),
    ],

    # Greyder: uzun burun, o'rtada qiya tig'
    "grader": lambda: [
        *wheels([9, 46, 58], 50, 6),
        rect(5, 30, 55, 5, 2, YELLOW, DARK),
        rect(40, 17, 20, 14, 2, YELLOW, DARK),
        *cab(43, 9, 14, 9),
        poly([(15, 37), (40, 37), (37, 49), (12, 49)], STEEL, DARK),
        line(26, 33, 26, 40, 2.6, STEEL_DK),
    ],

    # Katok: oldinda katta silliq baraban
    "roller": lambda: [
        # baraban — tik silindr, doira emas: aks holda oddiy g'ildirakka o'xshaydi
        rect(4, 34, 20, 22, 4, STEEL, DARK),
        line(9, 37, 9, 53, 1.6, STEEL_DK),
        line(14, 37, 14, 53, 1.6, STEEL_DK),
        line(19, 37, 19, 53, 1.6, STEEL_DK),
        *wheels([50], 48, 8),
        rect(24, 29, 28, 13, 2.5, YELLOW, DARK),
        *cab(30, 19, 15, 11),
        rect(22, 41, 22, 4, 1.5, YELLOW_DK),
    ],

    # Yamobur: vertikal machta va shnek
    "auger_drill": lambda: [
        *wheels([14, 30, 48], 49, 6.5),
        *cab(5, 27, 15, 15, ORANGE),
        rect(21, 34, 37, 9, 2, YELLOW, DARK),
        rect(43, 6, 7, 32, 1.5, YELLOW, DARK),
        line(46.5, 18, 46.5, 54, 2.6, STEEL_DK),
        *[line(42, y, 51, y + 4, 2.2, STEEL) for y in (24, 33, 42)],
    ],

    # Tral / evakuator: qiya platforma
    "tow_truck": lambda: [
        *wheels([14, 35, 51], 49, 7),
        *cab(3, 23, 16, 18, ORANGE),
        poly([(21, 41), (62, 25), (62, 34), (21, 45)], YELLOW, DARK),
        line(21, 41, 21, 29, 2.6, DARK),
        line(22, 31, 35, 25, 3, STEEL),
    ],

    # Kompressor: pritsepdagi quti
    "compressor": lambda: [
        rect(11, 25, 42, 23, 3, YELLOW, DARK),
        rect(17, 30, 28, 6, 1, DARK_2),
        rect(17, 39, 16, 4, 1, STEEL_DK),
        *wheels([22, 43], 51, 5),
        line(11, 35, 2, 39, 2.6, DARK),
    ],

    # Boshqa texnika: g'ildirak va kalit
    # Boshqa texnika: tishli g'ildirak — "mexanizm" degan umumiy belgi
    "other": lambda: [
        *[rect(30 - 4, 8, 8, 48, 1, STEEL_DK) for _ in (0,)],
        poly([(8, 26), (14, 20), (50, 20), (56, 26), (56, 38), (50, 44),
              (14, 44), (8, 38)], YELLOW, DARK),
        circle(32, 32, 15, YELLOW, DARK),
        circle(32, 32, 7, DARK_2),
        circle(32, 32, 3.5, HUB),
    ],
}


# --------------------------------------------------------------------- chizish

def to_svg(parts) -> str:
    body = []
    for kind, args, fill, stroke in parts:
        sw = ' stroke="%s" stroke-width="0.9"' % stroke if stroke else ""
        if kind == "rect":
            x, y, w, h, r = args
            rx = f' rx="{r}"' if r else ""
            body.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}"{rx} fill="{fill}"{sw}/>')
        elif kind == "circle":
            cx, cy, r = args
            body.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"{sw}/>')
        elif kind == "poly":
            pts = " ".join(f"{x},{y}" for x, y in args)
            body.append(f'<polygon points="{pts}" fill="{fill}"{sw}/>')
        elif kind == "line":
            x1, y1, x2, y2, w = args
            body.append(
                f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" '
                f'stroke="{fill}" stroke-width="{w}" stroke-linecap="round"/>'
            )
    shapes = "\n  ".join(body)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}">\n'
        f'  {shapes}\n</svg>\n'
    )


def _rgb(color: str):
    color = color.lstrip("#")
    return tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))


def draw_parts(draw, parts, k, dx=0.0, dy=0.0):
    """Primitivlarni Pillow bilan chizish. k — masshtab, dx/dy — siljish."""
    def sx(v):
        return v * k + dx

    def sy(v):
        return v * k + dy

    for kind, args, fill, stroke in parts:
        fill_rgb = _rgb(fill)
        stroke_rgb = _rgb(stroke) if stroke else None
        width = max(1, int(k * 0.9))

        if kind == "rect":
            x, y, w, h, r = args
            box = [sx(x), sy(y), sx(x + w), sy(y + h)]
            if r:
                draw.rounded_rectangle(box, radius=r * k, fill=fill_rgb,
                                       outline=stroke_rgb, width=width)
            else:
                draw.rectangle(box, fill=fill_rgb, outline=stroke_rgb, width=width)
        elif kind == "circle":
            cx, cy, r = args
            draw.ellipse([sx(cx - r), sy(cy - r), sx(cx + r), sy(cy + r)],
                         fill=fill_rgb, outline=stroke_rgb, width=width)
        elif kind == "poly":
            draw.polygon([(sx(x), sy(y)) for x, y in args], fill=fill_rgb,
                         outline=stroke_rgb)
        elif kind == "line":
            x1, y1, x2, y2, w = args
            draw.line([sx(x1), sy(y1), sx(x2), sy(y2)], fill=fill_rgb,
                      width=max(1, int(w * k)), joint="curve")
            rr = w / 2
            for cx, cy in ((x1, y1), (x2, y2)):
                draw.ellipse([sx(cx - rr), sy(cy - rr), sx(cx + rr), sy(cy + rr)],
                             fill=fill_rgb)


def to_png(parts) -> Image.Image:
    """
    Xarita markeri: oq yumaloq kvadrat, ostida yashil uchburchak, ichida
    rangli mashina. Oq fon rangli texnikani xaritada aniq ko'rsatadi.
    """
    s = SUPERSAMPLE
    W, H = PNG_W * s, PNG_H * s
    square = MARKER_SQUARE * s
    tail = MARKER_TAIL * s

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    # Yumshoq soya — marker xarita ustida "yotgandek" ko'rinadi
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [6 * s, 10 * s, square - 6 * s, square - 2 * s],
        radius=54 * s, fill=(0, 0, 0, 70),
    )
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(7 * s)))

    draw = ImageDraw.Draw(img)

    # Yashil uchburchak — joyni ko'rsatadi
    draw.polygon(
        [(square * 0.38, square - 8 * s),
         (square * 0.62, square - 8 * s),
         (square * 0.50, square + tail - 8 * s)],
        fill=_rgb(GREEN),
    )

    # Oq kvadrat
    draw.rounded_rectangle([0, 0, square, square], radius=54 * s,
                           fill=(255, 255, 255, 255),
                           outline=_rgb(BORDER), width=int(2 * s))

    # Mashina kvadrat ichida, chetlaridan bo'sh joy qoldirib
    inset = square * 0.11
    scale = (square - inset * 2) / SIZE
    draw_parts(draw, parts, scale, dx=inset, dy=inset)

    return img.resize((PNG_W, PNG_H), Image.LANCZOS)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for code, build in MACHINES.items():
        parts = build()

        with open(os.path.join(OUT_DIR, f"{code}.svg"), "w", encoding="utf-8") as f:
            f.write(to_svg(parts))

        to_png(parts).save(os.path.join(OUT_DIR, f"{code}.png"))

    print(f"{len(MACHINES)} ta tur uchun rangli ikonka yasaldi: {OUT_DIR}")
    print(f"SVG — interfeys uchun, PNG {PNG_W}x{PNG_H} — xarita markerlari uchun.")


if __name__ == "__main__":
    main()
