#!/usr/bin/env python3
"""
Texnika va qurilish materiallari uchun RANGLI ikonkalar.

Har bir mashina SVG yo'llari (path) bilan chizilgan va shu bitta tavsifdan
ikki xil fayl chiqadi:

  assets/equipment_types/<code>.svg   — interfeys uchun (katalog, kartochkalar,
                                        bildirishnomalar, tur tanlash)
  assets/equipment_types/<code>.png   — xarita markeri: oq yumaloq kvadrat,
                                        pastida yashil uchburchak, ichida mashina
  assets/material_types/<code>.svg    — qurilish materiallari (g'isht, sement…)

NEGA QAYTA CHIZILDI (05.10.2026). Eski ikonkalar Pillow bilan to'rtburchak
va chiziqlardan yig'ilardi: kabina — quticha, strela — tayoq, g'ildirak —
doira. Kichik o'lchamda mashinalar bir-biridan farq qilmasdi va "o'zi
yasalgan" ko'rinardi. Endi har bir mashina HAQIQIY siluet bo'yicha
chizilgan: kabinaning old ustuni qiya, strela uchiga qarab ingichkalashadi,
gusenitsa trakli, g'ildirakda shina/disk/stupitsa bor.

Ochiq ikonka to'plamlari (MDI, Tabler, Hugeicons) proporsiya uchun namuna
bo'lib xizmat qildi; ularda bizdagi 17 turdan faqat 6-7 tasi bor va hammasi
bir rangli, shuning uchun yo'llar o'zimizniki.

MATERIALLAR uchun ilgari emoji ishlatilardi (🧱, 🗿, 🏖). Telefonda ular
har xil ko'rinadi, 🗿 esa umuman Pasxa oroli haykali — qurilish toshi emas.

Ishga tushirish:
    pip install cairosvg
    python3 tool/generate_equipment_icons.py

Koordinatalar 64x64 maydonda, yer chizig'i y=56 da.
"""
import os

try:
    import cairosvg
except ImportError:  # PNG markerlarsiz ham SVG yasash mumkin
    cairosvg = None

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EQUIP_DIR = os.path.join(HERE, "assets", "equipment_types")
MATERIAL_DIR = os.path.join(HERE, "assets", "material_types")

#: Adminkadagi NUSXA. Panel PHP dan ishlaydi va mobil assets'ga qarab
#: tura olmaydi, shuning uchun unga nusxa kerak. Nusxani shu skript
#: o'zi qo'yadi: qo'lda ko'chirilganda ikkita to'plam bir-biridan
#: uzilib qolardi — xaritada eski mashina, ilovada yangisi.
ADMIN_EQUIP_DIR = os.path.join(
    os.path.dirname(HERE), "admin", "assets", "equipment_types"
)

# --------------------------------------------------------------------- palitra
#
# Ranglar haqiqiy texnikadan: sariq korpus, po'lat strela, qora shina
# kulrang disk bilan. Soya va blik bitta rangning ikki darajasi bilan
# beriladi — gradient YO'Q: u kichik o'lchamda ko'rinmaydi, faylni esa
# ikki barobar kattalashtiradi.
Y = "#FBB816"      # korpus
YD = "#D08E00"     # korpus soyada
YL = "#FFD766"     # korpus blikda
DK = "#2B3038"     # shassi, gusenitsa
DK2 = "#3D444E"    # shassi ochrog'i
STL = "#95A1AC"    # po'lat: kovsh, otval, valets
STD = "#67727D"    # po'lat soyada
STL2 = "#C2CAD2"   # po'lat blikda
GLS = "#7FB6DD"    # oyna
GLL = "#A9D2EF"    # oyna bliki
TIRE = "#23272E"   # shina
RIM = "#C9D0D6"    # disk
RED = "#E2574C"    # signal chiroq
LINE = "#1F242B"   # hoshiya

#: Hoshiya KERAK: ikonka oq fonda ham, kulrang fonda ham, xarita markerida
#: ham bir xil aniq ko'rinishi uchun. Qalinligi 1.2 — 24 px da yo'qolmaydi,
#: 150 px da esa qo'pol ko'rinmaydi.
S = f"stroke='{LINE}' stroke-width='1.2' stroke-linejoin='round'"
SW = f"stroke='{LINE}' stroke-width='1' stroke-linejoin='round'"


# ------------------------------------------------------------------ primitivlar
def shadow(cx=32, rx=24):
    """Yerdagi soya — mashina havoda osilib qolmasligi uchun."""
    return f"<ellipse cx='{cx}' cy='57.4' rx='{rx}' ry='1.9' fill='#000' opacity='0.10'/>"


def wheel(cx, cy, r):
    """Shina + protektor + disk + stupitsa."""
    return (
        f"<circle cx='{cx}' cy='{cy}' r='{r}' fill='{TIRE}'/>"
        f"<circle cx='{cx}' cy='{cy}' r='{r * 0.78:.2f}' fill='none' stroke='#3A4047' "
        f"stroke-width='{r * 0.16:.2f}'/>"
        f"<circle cx='{cx}' cy='{cy}' r='{r * 0.46:.2f}' fill='{RIM}' stroke='{LINE}' "
        f"stroke-width='0.6'/>"
        f"<path d='M{cx - r * 0.3:.2f} {cy - r * 0.3:.2f} A {r * 0.42:.2f} {r * 0.42:.2f} 0 0 1 "
        f"{cx + r * 0.1:.2f} {cy - r * 0.44:.2f}' fill='none' stroke='#FFFFFF' stroke-width='{r * 0.14:.2f}' "
        f"stroke-linecap='round' opacity='0.85'/>"
        f"<circle cx='{cx}' cy='{cy}' r='{r * 0.16:.2f}' fill='{STD}'/>"
    )


def track(x, y, w, h):
    """Gusenitsa: yumaloq lenta, traklar va yetakchi g'ildiraklar."""
    r = h / 2
    out = [f"<rect x='{x}' y='{y}' width='{w}' height='{h}' rx='{r}' fill='{DK}' {S}/>"]
    n = max(4, int(w // 3.4))
    for i in range(n):
        tx = x + r * 0.7 + i * (w - r * 1.4) / (n - 1)
        out.append(
            f"<line x1='{tx:.1f}' y1='{y + h - 1.7:.1f}' x2='{tx:.1f}' y2='{y + h - 0.5:.1f}' "
            f"stroke='#5A626C' stroke-width='1' stroke-linecap='round'/>"
        )
    out.append(f"<circle cx='{x + r:.1f}' cy='{y + r:.1f}' r='{r * 0.5:.2f}' fill='{RIM}'/>")
    out.append(f"<circle cx='{x + w - r:.1f}' cy='{y + r:.1f}' r='{r * 0.5:.2f}' fill='{RIM}'/>")
    return "".join(out)


def cab(x, y, w, h, flip=False, color=Y):
    """
    Kabina: old ustuni qiya, oynasi kattaroq.

    flip=True — mashina chapga qaragan.
    """
    if not flip:
        body = (f"M{x} {y + h} L{x} {y + 2.4} Q{x} {y} {x + 2.6} {y} "
                f"L{x + w - 1.4} {y} L{x + w} {y + h} Z")
        gx, gw = x + 1.5, w - 3.4
    else:
        body = (f"M{x + w} {y + h} L{x + w} {y + 2.4} Q{x + w} {y} {x + w - 2.6} {y} "
                f"L{x + 1.4} {y} L{x} {y + h} Z")
        gx, gw = x + 1.9, w - 3.4
    gy, gh = y + 1.9, h * 0.56
    glass = (
        # oyna
        f"<path d='M{gx:.1f} {gy:.1f} L{gx + gw:.1f} {gy:.1f} L{gx + gw + 0.6:.1f} {gy + gh:.1f} "
        f"L{gx:.1f} {gy + gh:.1f} Z' fill='{GLS}' stroke='{LINE}' stroke-width='0.7'/>"
        # blik — qiya oq yo'l
        f"<path d='M{gx + 0.4:.1f} {gy + 0.4:.1f} L{gx + gw * 0.42:.1f} {gy + 0.4:.1f} "
        f"L{gx + gw * 0.16:.1f} {gy + gh - 0.3:.1f} L{gx + 0.4:.1f} {gy + gh - 0.3:.1f} Z' "
        f"fill='{GLL}'/>"
        # kabina ostidagi soya
        f"<rect x='{x + 0.6:.1f}' y='{y + h - 2.2:.1f}' width='{w - 1.2:.1f}' height='1.8' "
        f"fill='{YD}' opacity='0.85'/>"
    )
    return f"<path d='{body}' fill='{color}' {S}/>" + glass


def exhaust(x, y, h=5.5):
    return f"<rect x='{x}' y='{y}' width='2.4' height='{h}' rx='1.1' fill='{DK2}'/>"


def beacon(x, y):
    return f"<rect x='{x}' y='{y}' width='3' height='2' rx='0.9' fill='{RED}'/>"


def bucket(x, y, w=9, h=12, teeth=3):
    """Kovsh: pastga kengayadigan idish va tishlar."""
    out = [
        f"<path d='M{x} {y} L{x + w} {y - 1.6} Q{x + w + 1.6} {y - 1.8} {x + w + 1.2} {y + 0.6} "
        f"L{x + w - 1.6} {y + h - 2} Q{x + w - 2.2} {y + h} {x + w - 4} {y + h} "
        f"L{x - 0.6} {y + h} Z' fill='{STL}' {S}/>",
        f"<path d='M{x - 0.6} {y + h} L{x + w - 4} {y + h} L{x + w - 4.4} {y + h + 0.9} "
        f"L{x - 0.9} {y + h + 0.9} Z' fill='{STD}'/>",
    ]
    step = (w - 4) / max(teeth - 1, 1)
    for i in range(teeth):
        tx = x - 0.2 + i * step
        out.append(
            f"<path d='M{tx:.1f} {y + h + 0.6:.1f} L{tx + 1.5:.1f} {y + h + 0.6:.1f} "
            f"L{tx + 1.1:.1f} {y + h + 2.4:.1f} L{tx + 0.4:.1f} {y + h + 2.4:.1f} Z' fill='{STD}'/>"
        )
    return "".join(out)


def joint(cx, cy, r=1.5):
    return f"<circle cx='{cx}' cy='{cy}' r='{r}' fill='{STD}' stroke='{LINE}' stroke-width='0.8'/>"


def cylinder(x1, y1, x2, y2, w=2.3):
    """Gidrosilindr: qalin po'lat tayoqcha."""
    return (f"<line x1='{x1}' y1='{y1}' x2='{x2}' y2='{y2}' stroke='{STD}' "
            f"stroke-width='{w}' stroke-linecap='round'/>")


def svg(parts):
    return ("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\">"
            + "".join(parts) + "</svg>")


# ------------------------------------------------------------------- mashinalar
def excavator():
    """Gusenitsali ekskavator — strela, kovsh, aylanuvchi platforma."""
    p = [shadow()]
    p.append(track(6, 46, 34, 10))
    p.append(f"<path d='M10 45 L10 37.6 Q10 35.6 12 35.6 L36 35.6 Q38 35.6 38 37.6 L38 45 Z' fill='{Y}' {S}/>")
    p.append(f"<rect x='10' y='42' width='28' height='3' fill='{YD}'/>")
    p.append(f"<path d='M7.4 44.6 L7.4 38 Q7.4 35.8 9.6 35.8 L13 35.8 L13 44.6 Z' fill='{YD}' {S}/>")
    p.append(cab(14, 23.5, 12.5, 12))
    p.append(exhaust(30, 30.6))
    # strela: ikki bo'g'in, uchiga qarab ingichka
    p.append(f"<path d='M34.6 33 L38.4 27.6 L49.4 15.6 L52.6 18.4 L41.8 31.4 L38 35.6 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M50 15.8 L53.2 18.6 L57.6 28.4 L54.2 30 Z' fill='{Y}' {S}/>")
    p.append(cylinder(38.6, 31.4, 46.4, 22))
    p.append(cylinder(51.6, 21, 54.6, 26.6, 1.9))
    p.append(bucket(52.4, 28.4, w=8.6, h=9.4))
    for cx, cy in ((36, 33.8), (51.3, 17.2), (53.6, 28.8)):
        p.append(joint(cx, cy))
    return svg(p)


def mini_excavator():
    """Mini ekskavator — xuddi shunday, lekin past va ixcham."""
    p = [shadow(32, 20)]
    p.append(track(11, 48, 26, 8))
    p.append(f"<path d='M14 47.4 L14 41 Q14 39.2 15.8 39.2 L34 39.2 Q35.8 39.2 35.8 41 L35.8 47.4 Z' fill='{Y}' {S}/>")
    p.append(f"<rect x='14' y='44.6' width='21.8' height='2.8' fill='{YD}'/>")
    p.append(cab(17, 29, 11, 10.4))
    p.append(f"<path d='M33 37.6 L36.4 32.8 L45 24 L47.6 26.6 L39.2 35.4 L35.8 39.4 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M45.4 24.2 L48 26.8 L51.4 34 L48.6 35.4 Z' fill='{Y}' {S}/>")
    p.append(cylinder(36.4, 36, 42.6, 29))
    p.append(bucket(46.8, 34.2, w=6.8, h=7.4, teeth=3))
    for cx, cy in ((34.4, 38), (46.6, 25.4)):
        p.append(joint(cx, cy, 1.3))
    return svg(p)


def bulldozer():
    """Buldozer — otval oldinda (o'ngda), gusenitsa, baland kabina."""
    p = [shadow()]
    p.append(track(8, 44, 34, 12))
    p.append(f"<path d='M13.4 43.6 L13.4 29.6 Q13.4 27.4 15.6 27.4 L27.6 27.4 L27.6 33.6 L37.6 33.6 "
             f"L37.6 43.6 Z' fill='{Y}' {S}/>")
    p.append(f"<rect x='13.4' y='39.8' width='24.2' height='3.8' fill='{YD}'/>")
    p.append(cab(14.6, 19.4, 13.4, 10))
    p.append(exhaust(31, 28, 6))
    # otval oldinda: qalin, pastda po'lat tig'i
    p.append(f"<path d='M44.6 28.6 L44.6 50.4 L49.4 50.4 Q52 50.4 52 47.8 "
             f"Q52 36.6 47.4 29.6 Q46.6 28.6 44.6 28.6 Z' fill='{STL}' {S}/>")
    p.append(f"<path d='M44.6 46.6 L52 46.6 Q52 50.4 49.4 50.4 L44.6 50.4 Z' fill='{STD}'/>")
    p.append(f"<path d='M46.8 30.6 Q49.8 36.4 50.4 45 L48.6 45 Q48 36.6 45.4 31.2 Z' "
             f"fill='{STL2}' opacity='0.7'/>")
    # ramalar otvaldan gusenitsaga
    p.append(f"<path d='M44.8 46.6 L38 43 L37 45.4 L44.4 49.4 Z' fill='{STD}'/>")
    p.append(cylinder(39, 36.6, 45.4, 34, 2))
    return svg(p)


def backhoe_loader():
    """Ekskavator-yuklagich: oldida kovsh, orqasida strela."""
    p = [shadow()]
    # oldingi kovsh
    p.append(f"<path d='M4.6 40 L11 40 L11 50.4 L6.4 50.4 Q4.6 50.4 4.6 48.6 Z' fill='{STL}' {S}/>")
    p.append(f"<path d='M4.6 47.6 L11 47.6 L11 50.4 L6.4 50.4 Q4.6 50.4 4.6 48.6 Z' fill='{STD}'/>")
    p.append(cylinder(11, 44, 18, 41.4))
    # korpus
    p.append(f"<path d='M15 46 L15 38 Q15 36.4 16.6 36.4 L40 36.4 L40 46 Z' fill='{Y}' {S}/>")
    p.append(f"<rect x='15' y='43' width='25' height='3' fill='{YD}'/>")
    p.append(cab(24, 24.6, 13, 12))
    p.append(exhaust(19.6, 31.4))
    # orqadagi strela
    p.append(f"<path d='M39 38 L44.6 30.6 L48.4 32.6 L43 40 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M44.8 30.8 L48.6 32.8 L53.6 40.6 L50.4 42.4 Z' fill='{Y}' {S}/>")
    p.append(bucket(49.6, 40.4, w=7.4, h=7, teeth=3))
    p.append(joint(46.6, 31.8, 1.3))
    p.extend([wheel(21, 48, 6.4), wheel(41, 46.4, 8.4)])
    return svg(p)


def front_loader():
    """Frontal yuklagich — kovsh oldinda (o'ngda), ko'tarilgan strela."""
    p = [shadow()]
    p.append(f"<path d='M8 46 L8 35.6 Q8 33.8 9.8 33.8 L32 33.8 Q34.6 33.8 34.6 36.4 L34.6 46 Z' fill='{Y}' {S}/>")
    p.append(f"<rect x='8' y='42.6' width='26.6' height='3.4' fill='{YD}'/>")
    p.append(cab(11, 22.6, 13.4, 11.2))
    p.append(exhaust(28.6, 29.4))
    # strela oldinga va yuqoriga
    p.append(f"<path d='M33 38.6 L44 30 L46.6 33.4 L35 42.6 Z' fill='{Y}' {S}/>")
    p.append(cylinder(34.6, 41.6, 41, 36.6))
    # kovsh: pastga qaragan, tishlari bilan
    p.append(f"<path d='M44.2 27.4 L50 31.6 Q51.2 32.4 50.8 33.8 L48.8 39.6 "
             f"Q48.2 41.2 46.2 40.6 L39 38 Z' fill='{STL}' {S}/>")
    p.append(f"<path d='M50.2 36.6 L48.8 39.6 Q48.2 41.2 46.2 40.6 L41.2 38.8 L42 36 Z' fill='{STD}'/>")
    for i in range(3):
        tx = 42.4 + i * 2.6
        p.append(f"<path d='M{tx:.1f} 40.4 L{tx + 1.4:.1f} 40.9 L{tx + 0.9:.1f} 42.6 "
                 f"L{tx + 0.2:.1f} 42.4 Z' fill='{STD}'/>")
    p.extend([wheel(14, 48, 7.4), wheel(30, 48, 7.4)])
    return svg(p)


def grader():
    """Greyder — uzun rama, o'rtasida qiya pichoq, kabina orqada."""
    p = [shadow()]
    # uzun rama
    p.append(f"<path d='M12 40.6 L44 40.6 L44 44.6 L12 44.6 Z' fill='{DK2}' {S}/>")
    # old kabina ustuni va dvigatel orqada (chapda)
    p.append(f"<path d='M8 44.6 L8 32.6 Q8 30.4 10.2 30.4 L24 30.4 Q26 30.4 26 32.4 L26 44.6 Z' fill='{Y}' {S}/>")
    p.append(f"<rect x='8' y='41' width='18' height='3.6' fill='{YD}'/>")
    p.append(cab(9.6, 20.6, 13.4, 10))
    p.append(exhaust(27.6, 26.6, 5))
    # qiya pichoq o'rtada
    p.append(f"<path d='M30 46.4 L48 39.6 L49.4 43.4 L31.4 50.2 Z' fill='{STL}' {S}/>")
    p.append(f"<path d='M30.6 48.4 L48.8 41.6 L49.4 43.4 L31.4 50.2 Z' fill='{STD}'/>")
    p.append(f"<path d='M31 46.6 L47.6 40.4 L47.9 41.4 L31.3 47.6 Z' fill='{STL2}' opacity='0.7'/>")
    p.append(cylinder(36, 42, 38, 35.6, 2))
    p.append(f"<path d='M44 36 L46.6 36 L46.6 41.6 L44 41.6 Z' fill='{Y}' {S}/>")
    p.extend([wheel(13.6, 48.6, 6.4), wheel(24.6, 48.6, 6.4), wheel(52.6, 48.6, 5.8)])
    return svg(p)


def roller():
    """Katok — ikki po'lat valets, o'rtasida kabina."""
    p = [shadow()]
    p.append(f"<rect x='18.6' y='33.6' width='27' height='7.4' rx='2' fill='{Y}' {S}/>")
    p.append(f"<rect x='18.6' y='37.8' width='27' height='3.2' fill='{YD}'/>")
    # ochiq kabina (ROPS)
    p.append(f"<rect x='26.6' y='21.4' width='17' height='2.6' rx='1.1' fill='{Y}' {S}/>")
    p.append(f"<rect x='29' y='24.6' width='11.4' height='9' rx='1' fill='{GLS}'/>")
    p.append(f"<path d='M29 24.6 L33.4 24.6 L31 33.6 L29 33.6 Z' fill='{GLL}'/>")
    p.append(f"<line x1='27.8' y1='23.6' x2='27.8' y2='33.6' stroke='{STD}' stroke-width='1.5'/>")
    p.append(f"<line x1='42.2' y1='23.6' x2='42.2' y2='33.6' stroke='{STD}' stroke-width='1.5'/>")
    # valetslar
    for vx in (8.6, 38.6):
        p.append(f"<rect x='{vx}' y='41.6' width='17' height='14' rx='7' fill='{STL}' {S}/>")
        p.append(f"<rect x='{vx + 2.4}' y='42.6' width='2.6' height='12' rx='1.3' fill='{STL2}'/>")
        p.append(f"<rect x='{vx + 12}' y='42.6' width='2.4' height='12' rx='1.2' fill='{STD}' opacity='0.6'/>")
    p.append(f"<line x1='25.6' y1='45.6' x2='38.6' y2='45.6' stroke='{DK2}' stroke-width='2.6'/>")
    return svg(p)


def dump_truck():
    """Samosval — ko'tarilgan kuzov va uch o'q."""
    p = [shadow()]
    p.append(f"<path d='M9 33.4 L50.6 21.4 L53 29.4 L12.6 41 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M9 33.4 L12.6 41 L10 41.8 L7 34.4 Z' fill='{YD}'/>")
    p.append(f"<path d='M11.6 31 L48.6 20.4 L49.4 23 L12.6 33.6 Z' fill='{YL}' opacity='0.55'/>")
    p.append(f"<rect x='9' y='41.4' width='46' height='5' rx='1.4' fill='{DK2}' {S}/>")
    p.append(f"<path d='M39.4 41.4 L39.4 27.4 L49.6 27.4 Q51.6 27.4 52.6 29.4 L55.6 35.4 L55.6 41.4 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M41.8 29.6 L49.6 29.6 Q50.6 29.6 51.2 30.6 L53.2 34.6 L41.8 34.6 Z' fill='{GLS}'/>")
    p.append(f"<path d='M41.8 29.6 L45.4 29.6 L44 34.6 L41.8 34.6 Z' fill='{GLL}'/>")
    p.append(f"<rect x='53' y='36.6' width='2.8' height='2.4' rx='0.8' fill='{YL}'/>")
    p.append(cylinder(19, 41.4, 25.4, 35.4, 2.6))
    p.extend([wheel(17.6, 48, 6.4), wheel(31, 48, 6.4), wheel(47.4, 48, 6.4)])
    return svg(p)


def concrete_mixer():
    """Beton aralashtirgich — aylanadigan baraban, spiral chizig'i bilan."""
    p = [shadow()]
    p.append(f"<rect x='9' y='41.4' width='46' height='5' rx='1.4' fill='{DK2}' {S}/>")
    # baraban
    p.append(f"<path d='M13.6 38.6 Q11.4 30.6 18.6 26.6 L30.6 20.6 Q38.6 17 42.6 24.6 "
             f"Q46.6 32.6 39.6 38 Q33.6 42.6 22.6 42.6 Q16 42.6 13.6 38.6 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M19.6 24.6 Q26.6 29.6 25.6 41.6' fill='none' stroke='{YD}' stroke-width='2.2'/>")
    p.append(f"<path d='M28.6 20.6 Q35.6 26.6 34.6 40' fill='none' stroke='{YD}' stroke-width='2.2'/>")
    p.append(f"<path d='M14 32 Q16.6 25.6 22.6 23' fill='none' stroke='{YL}' stroke-width='1.8' opacity='0.7'/>")
    # tarnov
    p.append(f"<path d='M12.6 36.6 L5.6 40.6 L7 43.4 L13.6 39.6 Z' fill='{STL}' {S}/>")
    # kabina
    p.append(f"<path d='M41.4 41.4 L41.4 27.4 L50.6 27.4 Q52.6 27.4 53.4 29.4 L55.6 35.4 L55.6 41.4 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M43.4 29.6 L50.4 29.6 Q51.4 29.6 52 30.6 L53.6 34.6 L43.4 34.6 Z' fill='{GLS}'/>")
    p.append(f"<path d='M43.4 29.6 L46.6 29.6 L45.4 34.6 L43.4 34.6 Z' fill='{GLL}'/>")
    p.extend([wheel(18.6, 48, 6.2), wheel(31.6, 48, 6.2), wheel(47.6, 48, 6.2)])
    return svg(p)


def concrete_pump():
    """Betonnasos — bukilgan uch bo'g'inli strela va beton quvuri."""
    p = [shadow()]
    p.append(f"<rect x='6' y='41' width='50' height='5.4' rx='1.4' fill='{DK2}' {S}/>")
    # kabina oldinda
    p.append(f"<path d='M42 41 L42 28.6 L50.6 28.6 Q52.6 28.6 53.6 30.6 L55.6 35.6 L55.6 41 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M44 30.6 L50.4 30.6 Q51.4 30.6 52 31.6 L53.4 35 L44 35 Z' fill='{GLS}'/>")
    p.append(f"<path d='M44 30.6 L46.6 30.6 L45.6 35 L44 35 Z' fill='{GLL}'/>")
    # nasos va bunker orqada
    p.append(f"<path d='M7 41 L7 34.6 Q7 32.6 9 32.6 L20 32.6 L20 41 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M8.6 34.6 L18.4 34.6 L16.6 39.6 L10.4 39.6 Z' fill='{DK2}'/>")
    p.append(f"<rect x='20.6' y='35.6' width='20' height='5.4' rx='1' fill='{Y}' {S}/>")
    # strela: uch bo'g'in, "garmon" ko'rinishida
    p.append(f"<path d='M24 35.6 L22.6 18 L26.6 17.6 L28 35.6 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M23 18.6 L27 18.2 L46 11.6 L47 15.6 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M45.4 12 L48.6 11 L53 20.6 L49.6 22 Z' fill='{Y}' {S}/>")
    # beton quvuri strela bo'ylab
    p.append(f"<path d='M25.6 20 L45.4 13.4' fill='none' stroke='{STD}' stroke-width='1.3'/>")
    p.append(f"<path d='M46.6 14 L51 22.6 Q51.6 24 50.4 24.6 L50 32.6' fill='none' "
             f"stroke='{STD}' stroke-width='1.4' stroke-linecap='round'/>")
    for cx, cy in ((24.6, 18.6), (46.4, 13)):
        p.append(joint(cx, cy, 1.5))
    # oyoqlar
    p.append(f"<path d='M9 41.6 L4 46.6 L4 49 L6.4 49 L11.6 43.6 Z' fill='{STD}'/>")
    p.append(f"<path d='M54 41.6 L59.4 46.6 L59.4 49 L57 49 L51.4 43.6 Z' fill='{STD}'/>")
    p.extend([wheel(17.6, 48.6, 5.8), wheel(29.6, 48.6, 5.8), wheel(46.6, 48.6, 5.8)])
    return svg(p)


def truck_crane():
    """Avtokran — uzun teleskopik strela va ilmoq."""
    p = [shadow()]
    p.append(f"<rect x='8' y='40.6' width='48' height='5.4' rx='1.4' fill='{DK2}' {S}/>")
    p.append(f"<path d='M20 40.6 L20 33.6 Q20 31.6 22 31.6 L42 31.6 Q44 31.6 44 33.6 L44 40.6 Z' fill='{Y}' {S}/>")
    p.append(f"<rect x='20' y='37.6' width='24' height='3' fill='{YD}'/>")
    # strela teleskopik: ikki qism, uchi ingichka
    p.append(f"<path d='M24 32.6 L26.6 29 L54 10.6 L56 13.6 L28.6 32.6 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M26.6 29 L54 10.6 L54.8 11.8 L27.4 30.2 Z' fill='{YL}' opacity='0.6'/>")
    p.append(cylinder(27, 33.6, 34.6, 27.6, 2.1))
    # ilmoq
    p.append(f"<line x1='55' y1='12.6' x2='55' y2='22.6' stroke='{STD}' stroke-width='1.1'/>")
    p.append(f"<path d='M53 22.6 L57 22.6 L57 24.6 L53 24.6 Z' fill='{STD}'/>")
    p.append(f"<path d='M55 24.6 Q57.6 26.6 55.6 28.6 Q53.6 30 53 27.6' fill='none' "
             f"stroke='{STD}' stroke-width='1.6' stroke-linecap='round'/>")
    # oyoqlar
    p.append(f"<path d='M10.6 41.4 L5.6 45.6 L5.6 48 L8 48 L13 44 Z' fill='{STD}'/>")
    p.append(cab(44.6, 30.6, 11, 10))
    p.extend([wheel(17.6, 48, 5.8), wheel(29.6, 48, 5.8), wheel(45.6, 48, 5.8)])
    return svg(p)


def aerial_platform():
    """Avtovishka — teleskopik strela uchida panjarali savat."""
    p = [shadow()]
    p.append(f"<rect x='7' y='41' width='48' height='5.4' rx='1.4' fill='{DK2}' {S}/>")
    # kabina oldinda
    p.append(f"<path d='M40.6 41 L40.6 29 L49.6 29 Q51.6 29 52.6 31 L55 35.6 L55 41 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M42.6 31 L49.4 31 Q50.4 31 51 32 L52.6 35.4 L42.6 35.4 Z' fill='{GLS}'/>")
    p.append(f"<path d='M42.6 31 L45.6 31 L44.4 35.4 L42.6 35.4 Z' fill='{GLL}'/>")
    # yuk platformasi
    p.append(f"<rect x='8' y='36' width='32' height='5' rx='1' fill='{Y}' {S}/>")
    p.append(f"<rect x='8' y='38.6' width='32' height='2.4' fill='{YD}'/>")
    # strela: ikki teleskopik bo'g'in yuqoriga chapga
    p.append(f"<path d='M30 36 L27.4 31.6 L12.6 18.6 L9.6 21.6 L25 34.6 L27 36.6 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M27.4 31.6 L12.6 18.6 L11.8 19.6 L26.6 32.6 Z' fill='{YL}' opacity='0.6'/>")
    p.append(cylinder(27.4, 36, 21, 31))
    # savat: panjarali
    p.append(f"<path d='M4 12.6 L17 12.6 L17 20.6 Q17 21.8 15.8 21.8 L5.2 21.8 Q4 21.8 4 20.6 Z' "
             f"fill='none' {S}/>")
    p.append(f"<rect x='4' y='19' width='13' height='2.8' rx='0.8' fill='{STL}' {S}/>")
    for gx in (7.4, 10.6, 13.8):
        p.append(f"<line x1='{gx}' y1='12.6' x2='{gx}' y2='19' stroke='{STD}' stroke-width='1.1'/>")
    p.append(f"<line x1='4' y1='15.6' x2='17' y2='15.6' stroke='{STD}' stroke-width='1.1'/>")
    p.append(f"<path d='M9.6 21.8 L13.4 21.8 L12.6 24 L10.4 24 Z' fill='{STD}'/>")
    p.append(beacon(44.6, 26.6))
    p.extend([wheel(16.6, 48.4, 5.8), wheel(45.6, 48.4, 5.8)])
    return svg(p)


def auger_drill():
    """Yamobur — vertikal shnekli burg'u."""
    p = [shadow()]
    p.append(f"<rect x='6' y='41' width='40' height='5.4' rx='1.4' fill='{DK2}' {S}/>")
    p.append(f"<path d='M7 41 L7 33.6 Q7 31.6 9 31.6 L18 31.6 Q20 31.6 20 33.6 L20 41 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M9 33.6 L17.6 33.6 L17.6 37.6 L9 37.6 Z' fill='{GLS}'/>")
    p.append(f"<rect x='20.6' y='36' width='20' height='5' rx='1' fill='{Y}' {S}/>")
    # machta
    p.append(f"<rect x='40.6' y='9' width='5' height='34' rx='1.4' fill='{Y}' {S}/>")
    p.append(f"<rect x='41.6' y='9' width='1.6' height='34' fill='{YL}' opacity='0.6'/>")
    # shnek
    p.append(f"<line x1='50' y1='14' x2='50' y2='50' stroke='{STD}' stroke-width='2.2' stroke-linecap='round'/>")
    for i in range(6):
        y0 = 18 + i * 5.2
        p.append(f"<path d='M50 {y0:.1f} Q56 {y0 + 1.4:.1f} 50 {y0 + 4.4:.1f}' fill='none' "
                 f"stroke='{STL}' stroke-width='2.2' stroke-linecap='round'/>")
    p.append(f"<path d='M48 50 L52 50 L50.6 54 L49.4 54 Z' fill='{STD}'/>")
    p.append(f"<rect x='44.6' y='12' width='7' height='4' rx='1.4' fill='{DK2}' {S}/>")
    p.extend([wheel(16.6, 48.4, 5.8), wheel(34.6, 48.4, 5.8)])
    return svg(p)


def manipulator():
    """Manipulyator — yuk platformasi va kabina ortidagi bukilgan kran."""
    p = [shadow()]
    p.append(f"<rect x='6' y='41' width='50' height='5.4' rx='1.4' fill='{DK2}' {S}/>")
    # kabina oldinda
    p.append(f"<path d='M43 41 L43 28.6 L51 28.6 Q53 28.6 54 30.6 L55.6 35.4 L55.6 41 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M44.8 30.6 L50.8 30.6 Q51.8 30.6 52.4 31.6 L53.6 35 L44.8 35 Z' fill='{GLS}'/>")
    p.append(f"<path d='M44.8 30.6 L47.4 30.6 L46.4 35 L44.8 35 Z' fill='{GLL}'/>")
    # yuk platformasi bortlari bilan
    p.append(f"<path d='M6.6 41 L6.6 34.6 L34 34.6 L34 41 Z' fill='{STL}' {S}/>")
    p.append(f"<path d='M6.6 38.6 L34 38.6 L34 41 L6.6 41 Z' fill='{STD}'/>")
    p.append(f"<rect x='9.6' y='29.6' width='9' height='5' rx='0.8' fill='{YL}' {SW}/>")
    p.append(f"<rect x='20' y='30.6' width='8' height='4' rx='0.8' fill='{STL2}' {SW}/>")
    # kran ustuni kabinaning ortida
    p.append(f"<rect x='35.6' y='26.6' width='5' height='14.4' rx='1.3' fill='{Y}' {S}/>")
    p.append(f"<rect x='36.6' y='26.6' width='1.6' height='14.4' fill='{YL}' opacity='0.6'/>")
    # strela chapga, bukilgan
    p.append(f"<path d='M36 28 L33 23.6 L18.6 13.6 L16.4 17 L30.6 26.6 L33.6 30.6 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M18.4 14 L16.2 17.4 L10.6 22.6 L8.6 19.6 Z' fill='{Y}' {S}/>")
    p.append(cylinder(34.6, 30, 27.6, 24.6, 2))
    p.append(joint(17.4, 15.6, 1.4))
    # arqon va ilmoq
    p.append(f"<line x1='9.6' y1='21.6' x2='9.6' y2='30.6' stroke='{STD}' stroke-width='1'/>")
    p.append(f"<path d='M7.6 30.6 Q11.6 32.6 9.6 35.6 Q7.6 37 7 34.6' fill='none' "
             f"stroke='{STD}' stroke-width='1.6' stroke-linecap='round'/>")
    p.extend([wheel(14.6, 48.4, 5.8), wheel(26.6, 48.4, 5.8), wheel(46.6, 48.4, 5.8)])
    return svg(p)


def tow_truck():
    """Tral / evakuator — qiya platforma va chekruk."""
    p = [shadow()]
    p.append(f"<rect x='7' y='41.4' width='48' height='5' rx='1.4' fill='{DK2}' {S}/>")
    # qiya platforma
    p.append(f"<path d='M5 48.6 L36 32.6 L38.6 36.6 L8.6 51.6 Z' fill='{STL}' {S}/>")
    p.append(f"<path d='M5 48.6 L36 32.6 L36.6 33.6 L6 49.6 Z' fill='{STL2}' opacity='0.7'/>")
    # ko'tarish mexanizmi
    p.append(f"<path d='M34.6 33.6 L38.6 31.6 L41.6 37.6 L37.6 39.6 Z' fill='{Y}' {S}/>")
    p.append(f"<line x1='36.6' y1='34.6' x2='44.6' y2='30.6' stroke='{STD}' stroke-width='1.6'/>")
    # kabina
    p.append(f"<path d='M41.4 41.4 L41.4 27 L50.6 27 Q52.6 27 53.6 29 L55.6 35 L55.6 41.4 Z' fill='{Y}' {S}/>")
    p.append(f"<path d='M43.4 29.2 L50.4 29.2 Q51.4 29.2 52 30.2 L53.6 34.2 L43.4 34.2 Z' fill='{GLS}'/>")
    p.append(f"<path d='M43.4 29.2 L46.6 29.2 L45.4 34.2 L43.4 34.2 Z' fill='{GLL}'/>")
    p.append(beacon(45.6, 24.6))
    p.extend([wheel(20.6, 48.4, 6), wheel(33.6, 48.4, 6), wheel(47.6, 48.4, 6)])
    return svg(p)


def compressor():
    """Kompressor — tirkamadagi qutи, havo shlangi bilan."""
    p = [shadow(30, 20)]
    # tirkama rama va tortqich
    p.append(f"<path d='M8.6 44 L16 44 L16 46.4 L8.6 46.4 Z' fill='{STD}'/>")
    p.append(f"<path d='M4 42.6 L10 44.6 L9.4 46.6 L3.4 44.6 Z' fill='{STD}'/>")
    # korpus
    p.append(f"<path d='M14 44.6 L14 30.6 Q14 28.4 16.2 28.4 L46 28.4 Q48.6 28.4 48.6 31 L48.6 44.6 Z' fill='{Y}' {S}/>")
    p.append(f"<rect x='14' y='40.6' width='34.6' height='4' fill='{YD}'/>")
    p.append(f"<path d='M16 30.4 L46 30.4 L46 32.6 L16 32.6 Z' fill='{YL}' opacity='0.5'/>")
    # panjara
    for i in range(4):
        p.append(f"<rect x='{18 + i * 4.6}' y='34.6' width='2.8' height='5' rx='0.9' fill='{DK2}'/>")
    # boshqaruv paneli
    p.append(f"<rect x='38' y='34' width='7.6' height='6' rx='1.2' fill='{DK2}' {S}/>")
    p.append(f"<circle cx='41.8' cy='37' r='1.6' fill='{STL2}'/>")
    # shlang
    p.append(f"<path d='M48.6 38 Q56 38 56 44 Q56 49 51 49' fill='none' stroke='{DK2}' "
             f"stroke-width='2.2' stroke-linecap='round'/>")
    p.extend([wheel(21.6, 48.4, 5.2), wheel(40.6, 48.4, 5.2)])
    return svg(p)


def other():
    """Boshqa texnika — umumiy siluet, ustida tishli g'ildirak belgisi."""
    p = [shadow(32, 20)]
    p.append(track(14, 46, 30, 9))
    p.append(f"<path d='M17.6 45.6 L17.6 36 Q17.6 34 19.6 34 L40 34 Q42.6 34 42.6 36.6 L42.6 45.6 Z' fill='{Y}' {S}/>")
    p.append(f"<rect x='17.6' y='42' width='25' height='3.6' fill='{YD}'/>")
    p.append(cab(21.6, 24, 12.6, 10))
    p.append(exhaust(36.6, 28.6))
    # tishli g'ildirak — "boshqa / aniqlanmagan" belgisi
    cx, cy, r = 48, 22, 7.2
    teeth = []
    import math
    for i in range(8):
        a0 = i * math.pi / 4
        x1 = cx + math.cos(a0) * (r - 1.2)
        y1 = cy + math.sin(a0) * (r - 1.2)
        x2 = cx + math.cos(a0) * (r + 2)
        y2 = cy + math.sin(a0) * (r + 2)
        teeth.append(f"<line x1='{x1:.1f}' y1='{y1:.1f}' x2='{x2:.1f}' y2='{y2:.1f}' "
                     f"stroke='{STD}' stroke-width='2.6' stroke-linecap='round'/>")
    p.extend(teeth)
    p.append(f"<circle cx='{cx}' cy='{cy}' r='{r}' fill='{STL}' {S}/>")
    p.append(f"<circle cx='{cx}' cy='{cy}' r='{r * 0.42:.1f}' fill='#FFFFFF' stroke='{LINE}' stroke-width='1'/>")
    return svg(p)


# ------------------------------------------------------- qurilish materiallari
#
# Ilgari bu yerda emoji ishlatilardi (🧱, 🗿, 🏖). Telefon va brauzerda
# ular har xil chiziladi, ba'zisi esa umuman mos emas: 🗿 — Pasxa oroli
# haykali, qurilish toshi emas. Endi texnikadagi uslubdagi chizmalar.

BRICK = "#C0563C"
BRICK_D = "#9E422C"
BRICK_L = "#D7715A"
GREY = "#B9C0C6"
GREY_D = "#99A2AA"
GREY_L = "#D5DAE0"
SAND = "#E3C077"
SAND_D = "#C9A458"
BAG = "#CFD5DB"
BAG_D = "#AEB6BE"
WOOD = "#C89A5B"
WOOD_D = "#A77C42"


def _brick_rect(x, y, w, h, fill, dark):
    return (f"<rect x='{x}' y='{y}' width='{w}' height='{h}' rx='1' fill='{fill}' {SW}/>"
            f"<rect x='{x}' y='{y + h - h * 0.3:.1f}' width='{w}' height='{h * 0.3:.1f}' fill='{dark}'/>")


def m_brick():
    """G'isht — uch qatorli taxlam."""
    p = [shadow(32, 20)]
    rows = [(10, 46, 3), (14, 36, 3), (18, 26, 2)]
    for x0, y0, n in rows:
        for i in range(n):
            p.append(_brick_rect(x0 + i * 15, y0, 14, 9, BRICK, BRICK_D))
    p.append(f"<rect x='18' y='26' width='14' height='2.4' fill='{BRICK_L}'/>")
    return svg(p)


def m_gas_block():
    """Gazoblok — yirik och kulrang bloklar, g'ovak yuzasi bilan."""
    p = [shadow(32, 20)]
    for x0, y0 in ((10, 38), (33, 38), (21, 20)):
        p.append(f"<rect x='{x0}' y='{y0}' width='21' height='17' rx='1.4' fill='{GREY_L}' {SW}/>")
        p.append(f"<rect x='{x0}' y='{y0 + 12}' width='21' height='5' fill='{GREY}'/>")
        for dx, dy in ((4, 4), (11, 6), (16, 3), (7, 9)):
            p.append(f"<circle cx='{x0 + dx}' cy='{y0 + dy}' r='1.1' fill='{GREY_D}' opacity='0.55'/>")
    return svg(p)


def m_cement():
    """Sement — qog'oz qop, ustida belgi."""
    p = [shadow(32, 17)]
    p.append(f"<path d='M18 18 Q32 14 46 18 L48 50 Q32 54 16 50 Z' fill='{BAG}' {S}/>")
    p.append(f"<path d='M16 42 Q32 46 48 42 L48 50 Q32 54 16 50 Z' fill='{BAG_D}'/>")
    p.append(f"<path d='M18 18 Q32 14 46 18 L46.4 23 Q32 19 17.8 23 Z' fill='{GREY_L}'/>")
    p.append(f"<rect x='24' y='28' width='16' height='10' rx='1.4' fill='{GREY_D}' opacity='0.45'/>")
    p.append(f"<path d='M27 36 L31 30 L34 34 L36.6 31 L38.6 36 Z' fill='{BAG}'/>")
    return svg(p)


def m_sand():
    """Qum — yumshoq uyum, ustida belkurak izi."""
    p = [shadow(32, 23)]
    p.append(f"<path d='M6 52 Q14 30 24 28 Q34 26 40 34 Q48 44 58 52 Z' fill='{SAND}' {S}/>")
    p.append(f"<path d='M6 52 Q16 44 26 44 Q42 44 58 52 Z' fill='{SAND_D}' opacity='0.55'/>")
    p.append(f"<path d='M12 48 Q18 36 24 32' fill='none' stroke='{SAND_D}' stroke-width='1.6' "
             f"stroke-linecap='round' opacity='0.8'/>")
    for cx, cy in ((20, 40), (33, 44), (44, 48)):
        p.append(f"<circle cx='{cx}' cy='{cy}' r='0.9' fill='{SAND_D}' opacity='0.7'/>")
    return svg(p)


def m_gravel():
    """Shag'al — mayda burchakli toshlar uyumi."""
    p = [shadow(32, 22)]
    p.append(f"<path d='M7 52 Q16 40 26 38 Q38 36 44 42 Q52 48 57 52 Z' fill='{GREY}' {S}/>")
    stones = [(16, 45, 5), (26, 41, 6), (36, 44, 5), (45, 48, 4.4), (21, 50, 4.4), (33, 50, 5)]
    for cx, cy, r in stones:
        p.append(f"<path d='M{cx - r:.1f} {cy:.1f} L{cx - r * 0.4:.1f} {cy - r:.1f} "
                 f"L{cx + r * 0.6:.1f} {cy - r * 0.8:.1f} L{cx + r:.1f} {cy + r * 0.2:.1f} "
                 f"L{cx + r * 0.3:.1f} {cy + r * 0.8:.1f} L{cx - r * 0.7:.1f} {cy + r * 0.6:.1f} Z' "
                 f"fill='{GREY_L}' {SW}/>")
    return svg(p)


def m_stone():
    """Tosh — yirik bo'lak, qirrali."""
    p = [shadow(32, 20)]
    p.append(f"<path d='M12 44 L16 24 L30 16 L46 20 L52 36 L46 50 L22 52 Z' fill='{GREY_L}' {S}/>")
    p.append(f"<path d='M12 44 L22 52 L46 50 L52 36 L38 40 Z' fill='{GREY}'/>")
    p.append(f"<path d='M16 24 L30 16 L38 30 L22 34 Z' fill='#E4E8EC'/>")
    p.append(f"<path d='M38 30 L52 36 L38 40 Z' fill='{GREY_D}'/>")
    return svg(p)


def m_rebar():
    """Armatura — burama tayoqchalar bog'lami."""
    p = [shadow(32, 22)]
    for i, x0 in enumerate((12, 20, 28, 36, 44)):
        y0 = 16 + (i % 2) * 2
        p.append(f"<rect x='{x0}' y='{y0}' width='6' height='36' rx='3' fill='{STL}' {SW}/>")
        p.append(f"<rect x='{x0 + 1}' y='{y0}' width='1.6' height='36' fill='{STL2}'/>")
        for k in range(6):
            yy = y0 + 4 + k * 5.6
            p.append(f"<line x1='{x0}' y1='{yy:.1f}' x2='{x0 + 6}' y2='{yy - 2:.1f}' "
                     f"stroke='{STD}' stroke-width='1.1'/>")
    p.append(f"<rect x='9' y='28' width='42' height='3.4' rx='1.7' fill='{DK2}'/>")
    p.append(f"<rect x='9' y='40' width='42' height='3.4' rx='1.7' fill='{DK2}'/>")
    return svg(p)


def m_concrete():
    """Tayyor beton — qolipga quyilgan blok va yuzasidagi tekislash izi."""
    p = [shadow(32, 20)]
    # blok: yuqori yuzasi ko'rinadigan parallelepiped
    p.append(f"<path d='M8 28 L32 18 L56 28 L32 38 Z' fill='{GREY_L}' {S}/>")
    p.append(f"<path d='M8 28 L8 44 L32 54 L32 38 Z' fill='{GREY}' {S}/>")
    p.append(f"<path d='M56 28 L56 44 L32 54 L32 38 Z' fill='{GREY_D}' {S}/>")
    # yuzadagi mayda shag'al
    for dx, dy in ((20, 26), (30, 23), (40, 27), (26, 30), (38, 32), (33, 27)):
        p.append(f"<circle cx='{dx}' cy='{dy}' r='1.2' fill='{GREY_D}' opacity='0.5'/>")
    # tekislash izi (moladan)
    p.append(f"<path d='M14 29.6 Q32 22 50 29.6' fill='none' stroke='#FFFFFF' "
             f"stroke-width='1.6' opacity='0.55'/>")
    # yon yuzadagi qolip taxtalari
    p.append(f"<line x1='16' y1='32.6' x2='16' y2='48.6' stroke='{GREY_D}' stroke-width='1' opacity='0.6'/>")
    p.append(f"<line x1='24' y1='36' x2='24' y2='52' stroke='{GREY_D}' stroke-width='1' opacity='0.6'/>")
    p.append(f"<line x1='40' y1='50' x2='40' y2='34' stroke='{GREY}' stroke-width='1' opacity='0.5'/>")
    p.append(f"<line x1='48' y1='46' x2='48' y2='30.6' stroke='{GREY}' stroke-width='1' opacity='0.5'/>")
    return svg(p)


def m_lumber():
    """Yog'och — taxta va brus taxlami, uchida yillik halqalar."""
    p = [shadow(32, 22)]
    for i, (x0, y0) in enumerate(((10, 40), (10, 30), (16, 20))):
        w = 40 if i < 2 else 34
        p.append(f"<rect x='{x0}' y='{y0}' width='{w}' height='9' rx='1.2' fill='{WOOD}' {SW}/>")
        p.append(f"<rect x='{x0}' y='{y0 + 6}' width='{w}' height='3' fill='{WOOD_D}'/>")
        p.append(f"<ellipse cx='{x0 + w - 4}' cy='{y0 + 4.5}' rx='3' ry='4' fill='#E0B377' {SW}/>")
        p.append(f"<ellipse cx='{x0 + w - 4}' cy='{y0 + 4.5}' rx='1.3' ry='2' fill='{WOOD_D}'/>")
    return svg(p)


def m_other():
    """Boshqa material — yopilgan quti."""
    p = [shadow(32, 20)]
    p.append(f"<path d='M10 26 L32 18 L54 26 L54 46 L32 54 L10 46 Z' fill='{SAND}' {S}/>")
    p.append(f"<path d='M10 26 L32 34 L32 54 L10 46 Z' fill='{SAND_D}'/>")
    p.append(f"<path d='M21 22 L43 30 L43 36 L21 28 Z' fill='#F0DCB0'/>")
    p.append(f"<path d='M32 34 L54 26 L54 32 L32 40 Z' fill='#EFD7A6' opacity='0.6'/>")
    return svg(p)


MATERIALS = {
    "brick": m_brick,
    "gas_block": m_gas_block,
    "cement": m_cement,
    "sand": m_sand,
    "gravel": m_gravel,
    "stone": m_stone,
    "rebar": m_rebar,
    "concrete": m_concrete,
    "lumber": m_lumber,
    "other": m_other,
}


# ------------------------------------------------------------- xarita markeri
#
# Marker — oq yumaloq kvadrat, pastida yashil uchburchak, ichida mashina.
# Ilgari u Pillow bilan alohida chizilardi, ya'ni ikkita chizma manbasi
# bor edi va ular bir-biridan uzilib qolardi. Endi bitta: SVG dan
# render qilinadi.
MARKER_W, MARKER_H = 256, 308
GREEN = "#22C55E"


def marker_svg(inner_svg):
    """Mashina SVG'sini marker ichiga joylaydi."""
    body = inner_svg.split(">", 1)[1].rsplit("</svg>", 1)[0]
    return (
        f"<svg xmlns='http://www.w3.org/2000/svg' width='{MARKER_W}' height='{MARKER_H}' "
        f"viewBox='0 0 {MARKER_W} {MARKER_H}'>"
        f"<rect x='6' y='6' width='244' height='244' rx='56' fill='#000' opacity='0.10'/>"
        f"<rect x='2' y='2' width='244' height='244' rx='56' fill='#FFFFFF' "
        f"stroke='#E3E7EB' stroke-width='3'/>"
        f"<path d='M94 240 L154 240 L124 300 Z' fill='{GREEN}'/>"
        f"<g transform='translate(26 46) scale(2.9)'>{body}</g>"
        f"</svg>"
    )


MACHINES = {
    "excavator": excavator,
    "mini_excavator": mini_excavator,
    "bulldozer": bulldozer,
    "backhoe_loader": backhoe_loader,
    "front_loader": front_loader,
    "grader": grader,
    "roller": roller,
    "dump_truck": dump_truck,
    "concrete_mixer": concrete_mixer,
    "concrete_pump": concrete_pump,
    "truck_crane": truck_crane,
    "aerial_platform": aerial_platform,
    "auger_drill": auger_drill,
    "manipulator": manipulator,
    "tow_truck": tow_truck,
    "compressor": compressor,
    "other": other,
}


def main():
    os.makedirs(EQUIP_DIR, exist_ok=True)
    os.makedirs(MATERIAL_DIR, exist_ok=True)

    for code, fn in MACHINES.items():
        with open(os.path.join(EQUIP_DIR, f"{code}.svg"), "w", encoding="utf-8") as f:
            f.write(fn())
    print(f"texnika SVG: {len(MACHINES)} ta → {EQUIP_DIR}")

    for code, fn in MATERIALS.items():
        with open(os.path.join(MATERIAL_DIR, f"{code}.svg"), "w", encoding="utf-8") as f:
            f.write(fn())
    print(f"material SVG: {len(MATERIALS)} ta → {MATERIAL_DIR}")

    # adminkaga nusxa
    if os.path.isdir(os.path.dirname(ADMIN_EQUIP_DIR)):
        os.makedirs(ADMIN_EQUIP_DIR, exist_ok=True)
        for code, fn in MACHINES.items():
            with open(os.path.join(ADMIN_EQUIP_DIR, f"{code}.svg"), "w", encoding="utf-8") as f:
                f.write(fn())
        print(f"adminka nusxasi: {len(MACHINES)} ta → {ADMIN_EQUIP_DIR}")

    if cairosvg is None:
        print("cairosvg yo'q — xarita markerlari (PNG) yasalmadi. "
              "O'rnatish:  pip install cairosvg")
        return
    for code, fn in MACHINES.items():
        cairosvg.svg2png(
            bytestring=marker_svg(fn()).encode("utf-8"),
            write_to=os.path.join(EQUIP_DIR, f"{code}.png"),
            output_width=MARKER_W,
            output_height=MARKER_H,
        )
    print(f"xarita markerlari (PNG): {len(MACHINES)} ta")


if __name__ == "__main__":
    main()
