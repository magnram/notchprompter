#!/usr/bin/env python3
"""Build the translated pages of the NotchPrompter website.

The English pages in website/ are the source. This script finds every piece of
visible text in them (headings, paragraphs, list items, links, alt text, the
title and meta tags), looks each one up in website/i18n/<lang>.json, and writes
website/<lang>/<page>.html. It also puts the hreflang links, the language
picker and a small script into every page, the English pages included.

    python3 website/i18n/build.py            # build all languages
    python3 website/i18n/build.py --check    # only report missing or unused strings
    python3 website/i18n/build.py --extract  # write i18n/strings.en.json, the list of all strings

Only the Python standard library is used. See README.md in this folder.
"""
from __future__ import annotations

import html
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent
I18N = SITE / "i18n"
BASE_URL = "https://magnram.github.io/notchprompter/"
PAGES = ["index.html", "support.html", "privacy.html"]

# (code, name in its own language). The code is the folder, the hreflang and <html lang>.
# The picker lists them in this order.
LANGS = [
    ("da", "Dansk"),
    ("de", "Deutsch"),
    ("en", "English"),
    ("es", "Español"),
    ("fr", "Français"),
    ("it", "Italiano"),
    ("nl", "Nederlands"),
    ("nb", "Norsk"),
    ("pl", "Polski"),
    ("pt-BR", "Português (Brasil)"),
    ("pt-PT", "Português (Portugal)"),
    ("fi", "Suomi"),
    ("sv", "Svenska"),
    ("tr", "Türkçe"),
    ("ru", "Русский"),
    ("uk", "Українська"),
    ("ja", "日本語"),
    ("ko", "한국어"),
    ("zh-Hans", "简体中文"),
    ("zh-Hant", "繁體中文"),
]
NAMES = dict(LANGS)

# Elements whose content is one translatable string, when everything inside is inline.
TEXT_TAGS = {"title", "h1", "h2", "h3", "h4", "p", "li", "summary", "a", "span",
             "small", "strong", "button", "label", "figcaption", "td", "th", "dt", "dd"}
INLINE_TAGS = {"a", "strong", "em", "b", "i", "kbd", "code", "small", "span", "br", "abbr"}
VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
             "source", "track", "wbr"}
TRANSLATED_ATTRS = {"alt", "aria-label", "title", "placeholder"}
TRANSLATED_META = {"description", "og:title", "og:description", "twitter:title", "twitter:description"}
NOT_TEXT = {"NotchPrompter", "GitHub"}  # the same in every language

# Blocks this script adds. They are removed before the text is read, and put back after.
BLOCK_RE = re.compile(r"[ \t]*<!-- i18n:(\w+) -->.*?<!-- /i18n:\1 -->\n", re.S)


# --------------------------------------------------------------------------- reading the source

class Units(HTMLParser):
    """Finds the (start, end) character ranges of every translatable string."""

    def __init__(self, source: str):
        super().__init__(convert_charrefs=False)
        self.src = source
        self.line_starts = [0]
        for m in re.finditer("\n", source):
            self.line_starts.append(m.end())
        self.stack: list[dict] = []
        self.found: list[tuple[int, int]] = []
        self.feed(source)
        self.close()

    def here(self) -> int:
        line, col = self.getpos()
        return self.line_starts[line - 1] + col

    def handle_starttag(self, tag, attrs):
        start = self.here()
        text = self.get_starttag_text() or ""
        self.attributes(tag, attrs, start, text)
        if tag not in INLINE_TAGS:
            for frame in self.stack:
                frame["mixed"] = True
        if tag in VOID_TAGS:
            return
        self.stack.append({"tag": tag, "start": start + len(text), "mixed": False, "text": False})

    def handle_startendtag(self, tag, attrs):
        self.attributes(tag, attrs, self.here(), self.get_starttag_text() or "")

    def handle_endtag(self, tag):
        end = self.here()
        while self.stack:
            frame = self.stack.pop()
            if frame["tag"] == tag:
                break
        else:
            return
        if tag in TEXT_TAGS and frame["text"] and not frame["mixed"]:
            raw = self.src[frame["start"]:end]
            if raw.strip() not in NOT_TEXT:
                self.found.append((frame["start"], end))

    def handle_data(self, data):
        if data.strip() and not (self.stack and self.stack[-1]["tag"] in ("script", "style")):
            for frame in self.stack:
                frame["text"] = True

    def handle_entityref(self, name):
        self.handle_data("&")

    def handle_charref(self, name):
        self.handle_data("&")

    def attributes(self, tag, attrs, start, text):
        attrs = dict(attrs)
        wanted = [a for a in TRANSLATED_ATTRS if attrs.get(a)]
        if tag == "meta" and (attrs.get("name") in TRANSLATED_META or attrs.get("property") in TRANSLATED_META):
            wanted.append("content")
        for name in wanted:
            m = re.search(r'\s%s="([^"]*)"' % re.escape(name), text)
            if m and m.group(1).strip() and m.group(1).strip() not in NOT_TEXT:
                self.found.append((start + m.start(1), start + m.end(1)))


def units(source: str) -> list[tuple[int, int]]:
    """Outermost translatable ranges, in document order."""
    found = sorted(set(Units(source).found))
    outer: list[tuple[int, int]] = []
    for s, e in found:
        if outer and s >= outer[-1][0] and e <= outer[-1][1]:
            continue  # inside a string we already have
        outer.append((s, e))
    return outer


def key_of(raw: str) -> str:
    """The lookup key: the English text with its whitespace made single spaces."""
    return re.sub(r"\s+", " ", raw).strip()


def read_source(page: str) -> str:
    return BLOCK_RE.sub("", (SITE / page).read_text(encoding="utf-8"))


# --------------------------------------------------------------------------- language data

def load(code: str) -> dict:
    path = I18N / f"{code}.json"
    if not path.exists():
        return {"ui": {}, "strings": {}}
    data = json.loads(path.read_text(encoding="utf-8"))
    data.setdefault("ui", {})
    data.setdefault("strings", {})
    return data


def page_url(code: str, page: str) -> str:
    folder = "" if code == "en" else code + "/"
    return BASE_URL + folder + ("" if page == "index.html" else page)


def rel_link(from_code: str, to_code: str, page: str) -> str:
    """A relative link from a page in one language to the same page in another."""
    up = "" if from_code == "en" else "../"
    folder = "" if to_code == "en" else to_code + "/"
    target = up + folder + ("" if page == "index.html" else page)
    return target or "./"


def esc(text: str) -> str:
    return html.escape(text, quote=True)


# --------------------------------------------------------------------------- added blocks

def alternates_block(page: str) -> str:
    lines = ["  <!-- i18n:alternates -->"]
    for code, _ in LANGS:
        lines.append(f'  <link rel="alternate" hreflang="{code}" href="{page_url(code, page)}">')
    lines.append(f'  <link rel="alternate" hreflang="x-default" href="{page_url("en", page)}">')
    lines.append("  <!-- /i18n:alternates -->\n")
    return "\n".join(lines)


GLOBE = ('<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" '
         'stroke-width="1.8" aria-hidden="true"><circle cx="12" cy="12" r="9"/>'
         '<path d="M3 12h18M12 3c2.5 2.7 3.8 5.7 3.8 9s-1.3 6.3-3.8 9c-2.5-2.7-3.8-5.7-3.8-9S9.5 5.7 12 3z"/></svg>')


def picker_block(code: str, page: str, ui: dict) -> str:
    label = ui.get("language", "Language")
    lines = [
        "      <!-- i18n:picker -->",
        '      <details class="lang">',
        f'        <summary>{GLOBE}<span class="sr">{esc(label)}: </span>{esc(NAMES[code])}</summary>',
        f'        <ul aria-label="{esc(label)}">',
    ]
    for other, name in LANGS:
        current = ' aria-current="page"' if other == code else ""
        lines.append(f'          <li><a href="{rel_link(code, other, page)}" hreflang="{other}" '
                     f'lang="{other}"{current}>{esc(name)}</a></li>')
    lines += ["        </ul>", "      </details>", "      <!-- /i18n:picker -->\n"]
    return "\n".join(lines)


REMEMBER_JS = """\
    // Remember the language the visitor picks, so the English page stops suggesting another one.
    for (const a of document.querySelectorAll("a[hreflang]")) {
      a.addEventListener("click", () => { try { localStorage.setItem("np-lang", a.hreflang); } catch (e) {} });
    }
"""

SUGGEST_JS = """\
    // First visit, no choice stored: suggest the page in the browser's language. Never redirects.
    (() => {
      const offers = %s;
      let stored = null;
      try { stored = localStorage.getItem("np-lang"); } catch (e) { return; }
      if (stored) return;
      const match = tag => {
        tag = tag.toLowerCase();
        if (/^(nb|no|nn)\\b/.test(tag)) return "nb";
        if (/^pt\\b/.test(tag)) return /^pt-(pt|ao|mz|cv|gw|st|tl|ch|lu|gq)\\b/.test(tag) ? "pt-PT" : "pt-BR";
        if (/^zh\\b/.test(tag)) return /^zh-(hant|tw|hk|mo)\\b/.test(tag) ? "zh-Hant" : "zh-Hans";
        const base = tag.split("-")[0];
        return base === "en" || offers[base] ? base : null;
      };
      let pick = null;
      for (const tag of navigator.languages || [navigator.language || ""]) {
        if ((pick = match(tag))) break;
      }
      if (!pick || pick === "en") return;
      const o = offers[pick];
      const bar = document.createElement("div");
      bar.className = "lang-banner";
      bar.lang = pick;
      bar.setAttribute("role", "region");
      bar.setAttribute("aria-label", o.name);
      bar.innerHTML = '<p></p><a></a><button type="button">×</button>';
      bar.querySelector("p").textContent = o.text;
      const go = bar.querySelector("a");
      go.textContent = o.go;
      go.href = pick + "/";
      go.hreflang = pick;
      const close = bar.querySelector("button");
      close.setAttribute("aria-label", o.close);
      go.addEventListener("click", () => { try { localStorage.setItem("np-lang", pick); } catch (e) {} });
      close.addEventListener("click", () => {
        try { localStorage.setItem("np-lang", "en"); } catch (e) {}
        bar.remove();
      });
      document.body.append(bar);
    })();
"""


def script_block(code: str, page: str) -> str:
    js = REMEMBER_JS
    if code == "en" and page == "index.html":
        offers = {}
        for other, name in LANGS:
            if other == "en":
                continue
            ui = load(other)["ui"]
            if ui.get("banner"):
                offers[other] = {"name": name, "text": ui["banner"], "go": ui.get("switch", name),
                                 "close": ui.get("dismiss", "Close")}
        js += SUGGEST_JS % json.dumps(offers, ensure_ascii=False, separators=(",", ":"))
    return "  <!-- i18n:script -->\n  <script>\n" + js + "  </script>\n  <!-- /i18n:script -->\n"


def insert_blocks(text: str, code: str, page: str, ui: dict) -> str:
    text = text.replace("</head>", alternates_block(page) + "</head>", 1)
    footer_end = re.search(r"\n(\s*)</div>\n\s*</footer>", text)
    if not footer_end:
        sys.exit(f"{page}: no </div></footer> to put the language picker in front of")
    at = footer_end.start() + 1
    text = text[:at] + picker_block(code, page, ui) + text[at:]
    return text.replace("</body>", script_block(code, page) + "</body>", 1)


# --------------------------------------------------------------------------- building

ASSET_RE = re.compile(r'(\s(?:href|src|poster|content)=")((?:media/|style\.css)[^"]*")')


def localize_asset(match: re.Match, code: str) -> str:
    """Point an asset at ../, and a media file at ../media/<lang>/ when that language has its own copy
    (the screenshots are rendered per language by Tools/render-all-languages.sh)."""
    attr, path = match.group(1), match.group(2)
    if path.startswith("media/"):
        name = path[len("media/"):-1]  # without the closing quote
        if "/" not in name and (SITE / "media" / code / name).is_file():
            return f'{attr}../media/{code}/{name}"'
    return f"{attr}../{path}"


def translate(source: str, code: str, strings: dict, missing: set, used: set) -> str:
    out = []
    pos = 0
    for s, e in units(source):
        key = key_of(source[s:e])
        value = strings.get(key)
        if value is None:
            missing.add(key)
            value = source[s:e]
        else:
            used.add(key)
        out.append(source[pos:s])
        out.append(value)
        pos = e
    out.append(source[pos:])
    return "".join(out)


def build_page(code: str, page: str, data: dict, missing: set, used: set) -> str:
    source = read_source(page)
    if code == "en":
        return insert_blocks(source, code, page, load("en")["ui"])
    text = translate(source, code, data["strings"], missing, used)
    text = text.replace('<html lang="en">', f'<html lang="{code}">', 1)
    text = ASSET_RE.sub(lambda m: localize_asset(m, code), text)
    pause = data["ui"].get("pause_cue")
    if pause and 'id="demo-script"' in text:
        text = text.replace('id="demo-script"', f'id="demo-script" data-pause="{esc(pause)}"', 1)
    return insert_blocks(text, code, page, data["ui"])


def all_keys() -> dict[str, str]:
    keys: dict[str, str] = {}
    for page in PAGES:
        source = read_source(page)
        for s, e in units(source):
            keys.setdefault(key_of(source[s:e]), key_of(source[s:e]))
    return keys


def main(argv: list[str]) -> int:
    if "--extract" in argv:
        path = I18N / "strings.en.json"
        path.write_text(json.dumps(all_keys(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {path.relative_to(SITE.parent)} ({len(all_keys())} strings)")
        return 0

    check_only = "--check" in argv
    keys = set(all_keys())
    problems = 0
    for code, _ in LANGS:
        if code == "en":
            continue
        data = load(code)
        missing: set = set()
        used: set = set()
        pages = {page: build_page(code, page, data, missing, used) for page in PAGES}
        unused = set(data["strings"]) - keys
        pause = data["ui"].get("pause_cue")
        if pause and pause not in pages["index.html"]:
            print(f"{code}: the pause cue {pause!r} is not in the translated hero script")
            problems += 1
        for key in sorted(missing):
            print(f"{code}: missing  {key[:90]}")
        for key in sorted(unused):
            print(f"{code}: unused   {key[:90]}")
        problems += len(missing)
        if not check_only:
            folder = SITE / code
            folder.mkdir(exist_ok=True)
            for page, text in pages.items():
                (folder / page).write_text(text, encoding="utf-8")
    if not check_only:
        for page in PAGES:
            (SITE / page).write_text(build_page("en", page, load("en"), set(), set()), encoding="utf-8")
        print(f"built {len(LANGS)} languages x {len(PAGES)} pages")
    if problems:
        print(f"{problems} missing string(s): those parts stay in English")
    return 1 if (check_only and problems) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
