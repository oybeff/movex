#!/usr/bin/env python3
"""
Texnika turlari uchun ikonkalarni yasaydi.

Har bir mashina primitivlar ro'yxati sifatida tasvirlangan va shu bitta
tavsifdan IKKI xil fayl chiqadi:

  assets/equipment_types/<code>.svg   — interfeys uchun, IKKI RANGLI:
                                        korpus to'q, ishchi qismi (cho'mich,
                                        tig', baraban, strela) yashil
  assets/equipment_types/<code>.png   — Yandex xaritadagi marker: yashil
                                        doira ichida oq belgi

Nega ishchi qismi ajratilgan: mashinalar bir-biridan aynan shu bilan farq
qiladi. Buldozerni tig'i, katokni barabani, betonnasosni strelasi bilan
taniydilar — rang shu detalga qaratadi.

Nega tayyor to'plam emas: bepul MIT to'plamlarda (Tabler va boshqalar) bizga
kerak 17 turdan atigi 6 tasi bor — greyder, katok, yamobur, betonnasos,
avtovishka uchun umuman ikonka yo'q.

Ishga tushirish:
    python3 tool/generate_equipment_icons.py

Koordinatalar 64x64 maydonda, yer chizig'i y=56 da.
"""
import os

try:
    from PIL import Image, ImageDraw
except ImportError:
    raise SystemExit("Pillow kerak:  pip install Pillow")

SIZE = 64
# Xarita markeri: 256 * 0.45 ≈ 115 px ekranda (client_main_page.dart)
PNG_SIZE = 256
MARKER_SCALE_HINT = 0.45
SUPERSAMPLE = 3

BODY_COLOR = "#1C1C1C"        # AppColors.black
ACCENT_COLOR = "#2ECC71"      # AppColors.primaryGreen

MARKER_FILL = (46, 204, 113)
MARKER_STROKE = (255, 255, 255)
GLYPH_ON_MARKER = (255, 255, 255)

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "assets", "equipment_types")

BODY = "body"
ACCENT = "accent"


# ---------------------------------------------------------------- primitivlar
# Har bir primitivning oxirgi elementi — rang roli.

def rect(x, y, w, h, r=0, c=BODY):
    return ("rect", (x, y, w, h, r), c)


def circle(cx, cy, r, c=BODY):
    return ("circle", (cx, cy, r), c)


def ring(cx, cy, r, w, c=BODY):
    return ("ring", (cx, cy, r, w), c)


def poly(points, c=BODY):
    return ("poly", tuple(points), c)


def line(x1, y1, x2, y2, w, c=BODY):
    return ("line", (x1, y1, x2, y2, w), c)


def wheels(xs, cy, r, w=None, c=BODY):
    return [ring(x, cy, r, w or max(2, r * 0.55), c) for x in xs]


def tracks(x, y, w, h, c=BODY):
    """Kraul izlar: cho'zilgan yumaloq to'rtburchak."""
    return [rect(x, y, w, h, h / 2, c)]


def boom(points, w=4, c=BODY):
    return [line(points[i][0], points[i][1], points[i + 1][0], points[i + 1][1], w, c)
            for i in range(len(points) - 1)]


def cab(x, y, w, h):
    """Kabina: korpus va ichida oynani bildiruvchi yorug' to'rtburchak."""
    return [
        rect(x, y, w, h, 2),
        rect(x + 2, y + 2, w - 4, h * 0.45, 1, ACCENT),
    ]


# ------------------------------------------------------------------ mashinalar

MACHINES = {
    # Ekskavator: izlar, aylanuvchi korpus, pastga egilgan strela va cho'mich
    "excavator": lambda: [
        *tracks(6, 46, 40, 10),
        *wheels([13, 22, 31, 40], 51, 3.2, 1.6),
        rect(14, 32, 26, 13, 2.5),
        *cab(16, 22, 12, 11),
        *boom([(36, 30), (50, 16), (56, 30)], 4, ACCENT),
        poly([(51, 30), (61, 28), (59, 38), (50, 38)], ACCENT),
    ],

    # Mini ekskavator: past va ixcham — kattasidan aniq farq qilishi kerak
    "mini_excavator": lambda: [
        *tracks(10, 46, 30, 9),
        *wheels([16, 24, 32], 50.5, 2.6, 1.4),
        rect(15, 34, 20, 12, 2.5),
        *cab(17, 25, 10, 9),
        *boom([(31, 32), (41, 24), (45, 33)], 3, ACCENT),
        poly([(42, 33), (50, 31), (49, 39), (42, 39)], ACCENT),
    ],

    # Ekskavator-yuklagich: oldida cho'mich, orqasida strela — ikkalasi ham yashil
    "backhoe_loader": lambda: [
        *wheels([15, 47], 48, 8, 3.2),
        rect(20, 34, 24, 11, 2.5),
        *cab(26, 24, 12, 11),
        *boom([(22, 38), (10, 34)], 3.5, ACCENT),
        poly([(11, 30), (4, 32), (4, 42), (11, 40)], ACCENT),
        *boom([(42, 32), (52, 22), (58, 34)], 3.5, ACCENT),
        poly([(54, 34), (62, 33), (61, 41), (53, 40)], ACCENT),
    ],

    # Buldozer: asosiy belgisi — oldindagi baland tig'
    "bulldozer": lambda: [
        *tracks(18, 42, 36, 13),
        *wheels([25, 34, 43, 50], 48.5, 3.6, 1.8),
        rect(24, 30, 26, 12, 2.5),
        *cab(28, 20, 14, 11),
        poly([(3, 26), (13, 30), (13, 56), (3, 60)], ACCENT),
        line(13, 44, 20, 42, 3, ACCENT),
    ],

    # Frontal yuklagich: orqada strela yo'q, oldida juda katta cho'mich
    "front_loader": lambda: [
        *wheels([28, 52], 47, 8, 3.2),
        rect(36, 30, 20, 14, 2.5),
        *cab(38, 20, 13, 11),
        *boom([(38, 36), (21, 29)], 4, ACCENT),
        poly([(21, 24), (3, 30), (3, 44), (21, 38)], ACCENT),
    ],

    # Avtokran: uzun teleskopik strela — eng taniqli siluet
    "truck_crane": lambda: [
        *wheels([13, 26, 40, 52], 49, 6.5, 2.6),
        rect(8, 34, 50, 10, 2),
        *cab(9, 24, 13, 11),
        *boom([(28, 34), (58, 12)], 5, ACCENT),
        line(58, 12, 58, 24, 2, ACCENT),
        circle(58, 26, 3, ACCENT),
        line(10, 44, 6, 52, 2.5),
        line(56, 44, 60, 52, 2.5),
    ],

    # Manipulyator: tik ustun va Z shaklida bukilgan kran
    "manipulator": lambda: [
        *wheels([14, 32, 50], 49, 6.5, 2.6),
        *cab(5, 24, 14, 12),
        rect(21, 36, 39, 6, 1.5),
        rect(36, 27, 23, 9, 1.5),
        rect(23, 14, 5, 22, 1, ACCENT),
        *boom([(25, 16), (40, 10), (53, 19)], 3.5, ACCENT),
        line(53, 19, 53, 26, 2, ACCENT),
        circle(53, 28, 2.5, ACCENT),
    ],

    # Avtovishka: strela va tepadagi savat
    "aerial_platform": lambda: [
        *wheels([14, 30, 48], 49, 6.5, 2.6),
        *cab(8, 24, 14, 12),
        rect(24, 34, 34, 9, 2),
        *boom([(30, 34), (52, 14)], 4, ACCENT),
        rect(48, 6, 14, 9, 1.5, ACCENT),
        line(10, 43, 6, 52, 2.5),
        line(56, 43, 60, 52, 2.5),
    ],

    # Samosval: ko'tarilgan kuzov
    "dump_truck": lambda: [
        *wheels([16, 34, 48], 49, 7, 2.8),
        *cab(6, 26, 15, 16),
        poly([(22, 34), (60, 34), (60, 42), (22, 42)]),
        poly([(24, 30), (62, 14), (64, 22), (26, 36)], ACCENT),
        line(24, 34, 24, 42, 2),
    ],

    # Beton aralashtirgich: yotiq baraban
    "concrete_mixer": lambda: [
        *wheels([14, 32, 48], 49, 7, 2.8),
        *cab(4, 26, 14, 16),
        rect(20, 38, 40, 5, 1.5),
        poly([(24, 34), (34, 18), (54, 18), (58, 34)], ACCENT),
        line(30, 22, 52, 22, 2),
        line(27, 28, 56, 28, 2),
    ],

    # Betonnasos: strela tik ko'tarilib, oldinga oshib tushadi
    "concrete_pump": lambda: [
        *wheels([13, 27, 44], 49, 6.5, 2.6),
        *cab(5, 28, 14, 14),
        rect(21, 34, 36, 9, 2),
        *boom([(26, 34), (26, 11), (46, 5), (59, 16)], 3.5, ACCENT),
        line(59, 16, 59, 29, 2.5, ACCENT),
        line(7, 43, 3, 52, 2.5),
        line(55, 43, 59, 52, 2.5),
    ],

    # Greyder: uzun burun, o'rtada ramaga osilgan qiya tig'
    "grader": lambda: [
        *wheels([9, 46, 58], 51, 5.5, 2.2),
        rect(5, 31, 55, 4, 2),
        rect(41, 18, 19, 13, 2),
        *cab(44, 11, 13, 8),
        poly([(15, 38), (40, 38), (37, 50), (12, 50)], ACCENT),
        line(26, 34, 26, 41, 2.5, ACCENT),
    ],

    # Katok: oldinda katta silliq baraban
    "roller": lambda: [
        rect(6, 38, 20, 18, 8, ACCENT),
        *wheels([50], 48, 8, 3.2),
        rect(24, 30, 28, 12, 2.5),
        *cab(30, 20, 14, 11),
        line(26, 44, 42, 44, 2.5),
    ],

    # Yamobur: vertikal machta va shnek
    "auger_drill": lambda: [
        *wheels([14, 30, 48], 49, 6.5, 2.6),
        *cab(6, 28, 14, 14),
        rect(22, 34, 36, 9, 2),
        rect(44, 8, 6, 30, 1.5, ACCENT),
        line(47, 20, 47, 54, 2.5, ACCENT),
        *[line(43, y, 51, y + 4, 2, ACCENT) for y in (26, 34, 42)],
    ],

    # Tral / evakuator: qiya platforma
    "tow_truck": lambda: [
        *wheels([14, 34, 50], 49, 7, 2.8),
        *cab(4, 24, 15, 18),
        poly([(21, 42), (62, 26), (62, 34), (21, 46)], ACCENT),
        line(21, 42, 21, 30, 2.5),
        *boom([(21, 32), (34, 26)], 3),
    ],

    # Kompressor: pritsepdagi quti
    "compressor": lambda: [
        rect(12, 26, 40, 22, 3),
        rect(18, 31, 26, 5, 1, ACCENT),
        *wheels([22, 42], 51, 5, 2),
        line(12, 36, 2, 40, 2.5),
        line(20, 41, 34, 41, 2),
    ],

    # Boshqa texnika: g'ildirak va kalit
    "other": lambda: [
        ring(24, 34, 14, 5),
        circle(24, 34, 4, ACCENT),
        *boom([(35, 43), (52, 54)], 5, ACCENT),
        poly([(48, 14), (56, 14), (56, 22), (52, 26), (48, 22)], ACCENT),
        line(52, 24, 52, 40, 4, ACCENT),
    ],
}


# --------------------------------------------------------------------- chizish

def _svg_color(role):
    return ACCENT_COLOR if role == ACCENT else BODY_COLOR


def to_svg(parts) -> str:
    body = []
    for kind, args, role in parts:
        color = _svg_color(role)
        if kind == "rect":
            x, y, w, h, r = args
            rx = f' rx="{r}"' if r else ""
            body.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}"{rx} fill="{color}"/>')
        elif kind == "circle":
            cx, cy, r = args
            body.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{color}"/>')
        elif kind == "ring":
            cx, cy, r, w = args
            body.append(
                f'<circle cx="{cx}" cy="{cy}" r="{r - w / 2}" fill="none" '
                f'stroke="{color}" stroke-width="{w}"/>'
            )
        elif kind == "poly":
            pts = " ".join(f"{x},{y}" for x, y in args)
            body.append(f'<polygon points="{pts}" fill="{color}"/>')
        elif kind == "line":
            x1, y1, x2, y2, w = args
            body.append(
                f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" '
                f'stroke="{color}" stroke-width="{w}" stroke-linecap="round"/>'
            )
    shapes = "\n  ".join(body)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}">\n'
        f'  {shapes}\n</svg>\n'
    )


def draw_parts(draw, parts, color, k):
    """Pillow bilan chizish. Marker uchun hamma narsa bitta rangda."""
    def s(v):
        return v * k

    for kind, args, _role in parts:
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
            draw.ellipse([s(cx - rr), s(cy - rr), s(cx + rr), s(cy + rr)],
                         outline=color, width=max(1, int(s(w))))
        elif kind == "poly":
            draw.polygon([(s(x), s(y)) for x, y in args], fill=color)
        elif kind == "line":
            x1, y1, x2, y2, w = args
            draw.line([s(x1), s(y1), s(x2), s(y2)], fill=color,
                      width=max(1, int(s(w))), joint="curve")
            rr = w / 2
            for cx, cy in ((x1, y1), (x2, y2)):
                draw.ellipse([s(cx - rr), s(cy - rr), s(cx + rr), s(cy + rr)], fill=color)


def to_png(parts) -> Image.Image:
    """
    Xarita markeri: yashil doira, oq hoshiya, ichida OQ belgi.

    Bu yerda ikki rang ishlamaydi — 100 px doira ichida yashil detal
    yashil fonda ko'rinmay qoladi.
    """
    k = PNG_SIZE * SUPERSAMPLE / SIZE
    canvas = PNG_SIZE * SUPERSAMPLE
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    pad = canvas * 0.02
    draw.ellipse([pad, pad, canvas - pad, canvas - pad],
                 fill=MARKER_FILL, outline=MARKER_STROKE,
                 width=int(canvas * 0.045))

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
    print("SVG — ikki rangli, interfeys uchun. PNG — xarita markerlari uchun.")


if __name__ == "__main__":
    main()
