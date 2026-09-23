#!/usr/bin/env node
// Writes the translations (l10n/<lang>.json) and the subtitle cues (l10n/cues.json) into
// index.html and tiktok/index.html as window.NP_L10N. English is the text authored in the HTML, so it is not in the block.
// It also copies the app's localized captures (editor window, Play mode) from build/Screens/<lang>/ when they exist.
//   node l10n/build.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dir = path.dirname(fileURLToPath(import.meta.url));
const video = path.join(dir, "..");
const repo = path.join(video, "..");
const CUES = JSON.parse(fs.readFileSync(path.join(dir, "cues.json"), "utf8")).cues;
const EN = JSON.parse(fs.readFileSync(path.join(dir, "en.json"), "utf8"));
export const LANGS = ["nb", "de", "fr", "es", "it", "pt-BR", "pt-PT", "nl", "sv", "da", "fi", "pl", "ja", "ko", "zh-Hans", "zh-Hant", "ru", "uk", "tr"];

const all = {};
for (const lang of LANGS) {
  const T = JSON.parse(fs.readFileSync(path.join(dir, `${lang}.json`), "utf8"));
  for (const k of Object.keys(EN.ui)) if (!(k in T.ui)) throw new Error(`${lang}: ui.${k} missing`);
  const subs = [];
  for (const c of CUES) {
    const t = T.subs[c.id];
    if (t == null) throw new Error(`${lang}: subs.${c.id} missing`);
    if (t === "") {
      if (!subs.length) throw new Error(`${lang}: the first cue can't be empty`);
      subs[subs.length - 1].e = c.to; // joined with the cue before
    } else subs.push({ s: c.from, e: c.to, t });
  }
  const ui = {};
  for (const k of Object.keys(EN.ui)) ui[k] = T.ui[k];
  all[lang] = { ui, subs };

  // app captures in this language (rendered by Tools/render-all-languages.sh)
  const shots = path.join(repo, "build/Screens", lang);
  const copy = (name, to) => {
    const from = path.join(shots, name);
    if (!fs.existsSync(from)) return;
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(from, to);
  };
  copy("window-editor.png", path.join(video, "assets/l10n", lang, "window-editor.png"));
  copy("prompter-playing.png", path.join(video, "assets/l10n", lang, "prompter-playing.png"));
  copy("window-editor.png", path.join(video, "tiktok/assets/l10n", lang, "window-editor.png"));
  for (const f of ["assets/l10n/" + lang + "/window-editor.png", "assets/l10n/" + lang + "/prompter-playing.png", "tiktok/assets/l10n/" + lang + "/window-editor.png"])
    if (!fs.existsSync(path.join(video, f))) throw new Error(`missing ${f} (run Tools/render-all-languages.sh ${lang} first)`);
}

const json = JSON.stringify(all);
for (const file of ["index.html", "tiktok/index.html"]) {
  const p = path.join(video, file);
  let html = fs.readFileSync(p, "utf8");
  const re = /(<!-- L10N:BEGIN[^>]*-->)[\s\S]*?(<!-- L10N:END -->)/;
  if (!re.test(html)) throw new Error(`${file} has no L10N block`);
  html = html.replace(re, (_, a, b) => `${a}\n    <script>\n      window.NP_L10N = ${json};\n    </script>\n    ${b}`);
  fs.writeFileSync(p, html);
}
console.log(`${LANGS.length} languages, ${CUES.length} cues, ${(json.length / 1024).toFixed(0)} KB per composition`);
