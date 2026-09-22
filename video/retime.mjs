#!/usr/bin/env node
// Writes timings.json into index.html.
//   node retime.mjs                         -> update index.html
//   node retime.mjs --words audio/transcript.json
//                                           -> print the transcript in VIDEO seconds (to pick new cues)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dir = path.dirname(fileURLToPath(import.meta.url));
const T = JSON.parse(fs.readFileSync(path.join(dir, "timings.json"), "utf8"));
const r3 = (x) => Math.round(x * 1000) / 1000;
const voiceLen = r3(T.source.voiceOut - T.source.voiceIn);

const wi = process.argv.indexOf("--words");
if (wi > 0) {
  const words = JSON.parse(fs.readFileSync(path.resolve(process.argv[wi + 1]), "utf8"));
  for (const w of words) {
    const s = w.start - T.source.voiceIn;
    if (s < -0.5 || s > voiceLen + 0.5) continue;
    console.log(s.toFixed(2).padStart(6), w.text);
  }
  process.exit(0);
}

const total = r3(voiceLen + T.tail);
const XF = T.xfade;
const names = Object.keys(T.scenes);
const scenes = {};
names.forEach((n, i) => {
  const cut = T.scenes[n];
  const next = i < names.length - 1 ? T.scenes[names[i + 1]] : total;
  const start = i === 0 ? 0 : r3(cut - XF);
  scenes[n] = { cut, start, end: r3(next), dur: r3(next - start) };
});

// media windows derived from the scene plan
const C = T.cues;
const media = {
  "voiceover": [0, voiceLen],
  "presenter": [0, voiceLen],
  "live": [0, r3(scenes.play.cut + XF)],
  "take-video": [r3(C.record - 0.45), r3(scenes.local.cut + XF - (C.record - 0.45))],
};

const file = path.join(dir, "index.html");
let html = fs.readFileSync(file, "utf8");
const setAttr = (id, attr, val) => {
  const re = new RegExp(`(<[^>]*\\bid="${id}"[^>]*?\\b${attr}=")[^"]*(")`);
  if (!re.test(html)) throw new Error(`#${id} has no ${attr}`);
  html = html.replace(re, `$1${val}$2`);
};
setAttr("root", "data-duration", total);
setAttr("layer-wallpaper", "data-duration", total);
for (const n of names) {
  setAttr(`scene-${n}`, "data-start", scenes[n].start);
  setAttr(`scene-${n}`, "data-duration", scenes[n].dur);
}
for (const [id, [s, d]] of Object.entries(media)) {
  setAttr(id, "data-start", s);
  setAttr(id, "data-duration", d);
  if (id !== "voiceover") setAttr(id, "data-media-start", s);
}

const block = `<!-- TIMINGS:BEGIN (written by retime.mjs from timings.json — edit timings.json, then run: node retime.mjs) -->
    <script>
      window.NP_TIMINGS = ${JSON.stringify({ total, xfade: XF, voiceLen, cues: C, scenes })};
    </script>
    <!-- TIMINGS:END -->`;
html = html.replace(/<!-- TIMINGS:BEGIN[\s\S]*?<!-- TIMINGS:END -->/, block);
fs.writeFileSync(file, html);
console.log(`total ${total}s, voice ${voiceLen}s`);
for (const n of names) console.log(`  ${n.padEnd(7)} cut ${String(scenes[n].cut).padStart(6)}  clip ${scenes[n].start}–${scenes[n].end}`);
