"""
Oferta va maxfiylik siyosati matnlari.

Matnlar app/legal/*.txt da — git ostida, oddiy deploy bilan prodga
boradi. Ilgari ular faqat app_settings da turishi kerak edi, lekin
adminkada ularni yozadigan sahifa yo'q edi va prodda ilova
"Maxfiylik siyosati hali yuklanmagan" deb ko'rsatardi — Google Play esa
siyosat ilova ichida ham bo'lishini talab qiladi.

Bitta manba — ikki ko'rinish: ilova ekrani oddiy matnni oladi
(/settings/terms|privacy/{lang}), sayt esa shu matndan yasalgan sahifani
(/terms, /privacy). Ikkita alohida nusxa bir-biridan albatta uzoqlashardi.

app_settings dagi qiymat (agar kimdir to'ldirsa) fayldan ustun turadi.
"""
import html
import os
import re
from functools import lru_cache

LEGAL_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "legal")

TITLES = {
    "privacy": "MoveX GO — Политика конфиденциальности / Maxfiylik siyosati / Privacy Policy",
    "terms": "MoveX GO — Пользовательское соглашение / Foydalanuvchi shartnomasi",
}
LANGS = {
    "privacy": (("ru", "Русский"), ("uz", "O‘zbekcha"), ("en", "English")),
    "terms": (("ru", "Русский"), ("uz", "O‘zbekcha")),
}


@lru_cache(maxsize=None)
def text(kind: str, lang: str) -> str:
    path = os.path.join(LEGAL_DIR, f"{kind}_{lang}.txt")
    with open(path, encoding="utf-8") as f:
        return f.read().strip()


_HEADING = re.compile(r"^\d+\.\s+\S")
_CLAUSE = re.compile(r"^\d+\.\d+\.\s")


def _section_html(raw: str, anchor: str) -> str:
    blocks = [b.strip() for b in raw.split("\n\n") if b.strip()]
    out = []
    for i, block in enumerate(blocks):
        lines = block.split("\n")
        if i == 0:
            out.append(f'<h1 id="{anchor}">{html.escape(lines[0])}</h1>')
            continue
        if i == 1:
            out.append(f'<p class="upd">{html.escape(block)}</p>')
            continue
        if len(lines) == 1 and _HEADING.match(lines[0]) and not _CLAUSE.match(lines[0]):
            out.append(f"<h2>{html.escape(lines[0])}</h2>")
            continue
        items = [ln for ln in lines if ln.startswith("• ")]
        rest = [ln for ln in lines if not ln.startswith("• ")]
        for ln in rest:
            out.append(f"<p>{html.escape(ln)}</p>")
        if items:
            out.append("<ul>" + "".join(f"<li>{html.escape(ln[2:])}</li>" for ln in items) + "</ul>")
    return "\n".join(out)


@lru_cache(maxsize=None)
def page(kind: str) -> str:
    langs = LANGS[kind]
    nav = "".join(f'<a href="#{code}">{name}</a>' for code, name in langs)
    sections = "\n<hr>\n".join(_section_html(text(kind, code), code) for code, _ in langs)
    return f"""<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(TITLES[kind])}</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ max-width: 780px; margin: 0 auto; padding: 24px 20px 72px;
         font: 16px/1.65 -apple-system, "Segoe UI", Roboto, sans-serif; }}
  h1 {{ font-size: 1.55rem; margin: 0 0 .2em; }}
  h2 {{ font-size: 1.12rem; margin-top: 1.9em; }}
  ul {{ padding-left: 1.3em; }}
  li {{ margin: .3em 0; }}
  .upd {{ opacity: .7; font-size: .9rem; margin-top: 0; }}
  .nav {{ margin: 1.5em 0 2.5em; padding: 12px 14px; border: 1px solid #8884; border-radius: 8px; }}
  .nav a {{ margin-right: 1.2em; }}
  hr {{ margin: 3.5em 0; border: 0; border-top: 1px solid #8884; }}
</style>
</head>
<body>
<div class="nav">{nav}</div>
{sections}
</body>
</html>
"""
