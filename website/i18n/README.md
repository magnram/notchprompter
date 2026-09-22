# Website translations

The English pages in `website/` (`index.html`, `support.html`, `privacy.html`) are the
source. `build.py` makes a copy of each page for every other language in
`website/<lang>/`, for example `website/de/support.html`. GitHub Pages serves these files
as they are. There is no build step in the workflow, so you must run the script and
commit its output.

Languages: en (the root), da, de, es, fr, it, nl, nb, pl, pt-BR, pt-PT, fi, sv, tr, ru,
uk, ja, ko, zh-Hans, zh-Hant. The list is `LANGS` in `build.py`.

## How it works

- The script finds each piece of text in the English pages: headings, paragraphs, list
  items, links, `alt` and `aria-label` text, `<title>` and the description and `og:` meta
  tags. The English text (with its HTML, whitespace made single) is the key.
- `i18n/<lang>.json` maps each key to its translation:
  `{"ui": {...}, "strings": {"English text": "Translated text"}}`.
- Translated pages use `../style.css` and `../media/...`. The promo video stays English.
- The script also adds three marked blocks to every page, the English pages too:
  `<!-- i18n:alternates -->` (hreflang links), `<!-- i18n:picker -->` (language picker in
  the footer) and `<!-- i18n:script -->` (remembers the chosen language; on the English
  home page it also shows the "This page is also available in ..." banner). Do not edit
  these blocks by hand. The script replaces them each time.
- `ui` in each language file: `language` (picker label), `banner`, `switch` and
  `dismiss` (the banner on the English home page), and `pause_cue` (the translated
  "(pause)" note in the hero demo, which the animation waits on).

## After you change an English page

1. Edit the English page in `website/` as usual.
2. Run `python3 website/i18n/build.py --check`. It lists each string that is new or
   changed ("missing") and each translation that is no longer used ("unused"), per language.
3. Add the new strings to each `i18n/<lang>.json`. For a changed string, change the key
   to the new English text and update the translation. Delete unused keys.
   `python3 website/i18n/build.py --extract` writes `i18n/strings.en.json`, the full list
   of keys, which is useful to give to a translator.
4. Run `python3 website/i18n/build.py`. It writes all `website/<lang>/` pages and puts the
   blocks back in the English pages.
5. Commit the English pages, the JSON files and the `website/<lang>/` folders together.

A missing string does not stop the build: that text stays in English on the translated
page, and the script prints it.

## Add a page or a language

- New page: add it to `PAGES` in `build.py`. It needs a `<footer>` with a `.wrap` div
  (the picker goes at its end), and must link to style.css and media/ with relative paths.
- New language: add `(code, name in its own language)` to `LANGS`, add `i18n/<code>.json`,
  and run the build. If Chinese or Japanese-like text needs word splitting in the hero
  demo, check the `noSpaces` test in the hero script in `index.html`.
