#!/usr/bin/env node
// Writes cut.json into index.html: the media clips of every segment, the cue times, and word-level captions.
//   node build.mjs            -> update index.html (and audio/words.json)
//   node build.mjs --words    -> print the aligned words (source and output seconds)
//
// Word timing: whisper.cpp with DTW token timestamps (audio/whisper-dtw.json), made with
//   whisper-cli -m ggml-medium.en.bin -f voice16k.wav -l en -dtw medium.en -nfa -ojf -of whisper-dtw
// A DTW stamp marks the END of a token, so a word starts at the stamp of the token before it.
// When a silence (silencedetect -40 dB, 0.15 s, on ../audio/voiceover.wav) ends inside that
// window, the word starts at the end of the silence instead.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const dir = path.dirname(fileURLToPath(import.meta.url));
const CUT = JSON.parse(fs.readFileSync(path.join(dir, "cut.json"), "utf8"));
const FPS = CUT.fps;
const fr = (t) => Math.round(t * FPS);
const r3 = (x) => Math.round(x * 1000) / 1000;

// ---- segments, snapped to frames
let outF = 0;
const segs = CUT.segments.map((s) => {
  const a = fr(s.from), b = fr(s.to);
  const seg = { id: s.id, src: r3(a / FPS), srcEnd: r3(b / FPS), start: r3(outF / FPS), dur: r3((b - a) / FPS) };
  seg.end = r3(seg.start + seg.dur);
  seg.off = r3(seg.src - seg.start); // out = src - off
  outF += b - a;
  return seg;
});
const voiceOut = r3(outF / FPS);
const total = r3(Math.round((voiceOut + CUT.tail) * FPS) / FPS);
const toOut = (t) => {
  for (const s of segs) if (t >= s.src - 1e-6 && t < s.srcEnd + 1e-6) return r3(t - s.off);
  return null;
};

// ---- cues in output seconds
const cues = {};
for (const [k, v] of Object.entries(CUT.cues)) {
  if (k.startsWith("_")) continue;
  const o = toOut(v);
  if (o === null) throw new Error(`cue ${k} (${v}) falls outside the cut`);
  cues[k] = o;
}

// ---- silences (ffmpeg logs to stderr, so fold it into stdout)
const sdLog = execFileSync("sh", ["-c", `ffmpeg -hide_banner -i "${path.join(dir, "../audio/voiceover.wav")}" -af silencedetect=n=-40dB:d=0.15 -f null - 2>&1`], { encoding: "utf8" });
const SIL = [];
let s0 = null;
for (const line of sdLog.split("\n")) {
  const m1 = line.match(/silence_start: ([\d.]+)/); if (m1) s0 = +m1[1];
  const m2 = line.match(/silence_end: ([\d.]+)/); if (m2) SIL.push([s0, +m2[1]]);
}

// ---- words from DTW tokens
const dtw = JSON.parse(fs.readFileSync(path.join(dir, "audio/whisper-dtw.json"), "utf8"));
const toks = [];
for (const seg of dtw.transcription) for (const t of seg.tokens) if (!t.text.startsWith("[_")) toks.push({ text: t.text, t: t.t_dtw / 100 });
const words = [];
toks.forEach((tk, i) => {
  const prev = i > 0 ? toks[i - 1].t : 0;
  if (tk.text.startsWith(" ") || words.length === 0) words.push({ text: tk.text.trim(), win: [prev, tk.t], tokEnd: tk.t });
  else { words[words.length - 1].text += tk.text; words[words.length - 1].tokEnd = tk.t; }
});
// merge "Notch" + "Promptor" into one word
for (let i = 0; i < words.length - 1; i++) {
  if (words[i].text === "Notch" && /^Prompt/.test(words[i + 1].text)) {
    words[i].text = "Notch" + words[i + 1].text;
    words[i].tokEnd = words[i + 1].tokEnd;
    words.splice(i + 1, 1);
  }
}
for (const w of words) {
  let st = w.win[0];
  for (const [a, b] of SIL) if (b > w.win[0] - 0.05 && b <= w.win[1] + 0.05) st = Math.max(st, b);
  w.start = r3(st);
  for (const [k, v] of Object.entries(CUT.captionFixes || {})) w.text = w.text.split(k).join(v);
  if (w.text === "Prompter") w.text = "prompter"; // "the prompter", not the product name
}
words.forEach((w, i) => {
  let end = i < words.length - 1 ? words[i + 1].start : w.tokEnd;
  for (const [a] of SIL) if (a > w.start && a < end) { end = a; break; }
  w.end = r3(end);
});

if (process.argv.includes("--words")) {
  for (const w of words) console.log(w.start.toFixed(2).padStart(6), String(toOut(w.start) ?? "  -").padStart(7), w.text);
  process.exit(0);
}

// ---- caption groups (output seconds): break on sentence end, a gap, a cut, or 4 words / 20 characters
const kept = words.map((w) => ({ ...w, os: toOut(w.start), seg: segs.find((s) => w.start >= s.src - 1e-6 && w.start < s.srcEnd + 1e-6)?.id }))
  .filter((w) => w.os !== null)
  .map((w) => ({ t: w.text, s: w.os, e: r3(Math.min(w.end, segs.find((s) => s.id === w.seg).srcEnd) - (w.start - w.os)), seg: w.seg }));
const groups = [];
let g = null;
for (const w of kept) {
  const chars = g ? g.w.reduce((n, x) => n + x.t.length + 1, 0) + w.t.length : 0;
  const prevW = g && g.w[g.w.length - 1];
  const brk = !g || /[.?!,]$/.test(prevW.t) || w.s - prevW.e > 0.35 || w.seg !== prevW.seg || g.w.length >= 4 || chars > 20;
  if (brk) { g = { w: [] }; groups.push(g); }
  g.w.push(w);
}
const caps = groups.map((gr, i) => {
  const s = gr.w[0].s;
  const lastEnd = gr.w[gr.w.length - 1].e;
  const next = i < groups.length - 1 ? groups[i + 1].w[0].s : total;
  const e = r3(Math.min(next, lastEnd + 0.5));
  return { s, e, w: gr.w.map((x) => [x.t, x.s]) };
});
fs.writeFileSync(path.join(dir, "audio/words.json"), JSON.stringify(kept, null, 1));

// ---- write index.html
const file = path.join(dir, "index.html");
let html = fs.readFileSync(file, "utf8");
const block = (name, body) => {
  const re = new RegExp(`(<!-- ${name}:BEGIN[^>]*-->)[\\s\\S]*?(<!-- ${name}:END -->)`);
  if (!re.test(html)) throw new Error(`index.html has no ${name} block`);
  html = html.replace(re, `$1\n${body}\n$2`);
};
const I = "          ";
block("PRESENTER", segs.map((s, i) =>
  `${I}<video id="pres-${s.id}" class="clip pres" src="assets/presenter.webm" muted playsinline data-start="${s.start}" data-duration="${s.dur}" data-media-start="${s.src}" data-track-index="${10 + i}"></video>`).join("\n"));
const a = segs[0];
block("LIVE", `${I}<video id="live" class="clip" src="assets/prompter-live.mp4" muted playsinline data-start="${a.start}" data-duration="${a.dur}" data-media-start="${a.src}" data-track-index="9"></video>`);
block("VOICE", segs.map((s, i) =>
  `      <audio id="voice-${s.id}" src="audio/voice.wav" data-start="${s.start}" data-duration="${s.dur}" data-media-start="${s.src}" data-track-index="${20 + i}" data-volume="1"></audio>`).join("\n"));
block("TIMINGS", `    <script>\n      window.NP_CUT = ${JSON.stringify({ total, voiceOut, segs, cues, caps })};\n    </script>`);
const setClip = (id, start, dur) => {
  const re = new RegExp(`(<div id="${id}"[^>]*data-start=")[^"]*("[^>]*data-duration=")[^"]*(")`);
  if (!re.test(html)) throw new Error(`#${id} not found`);
  html = html.replace(re, `$1${start}$2${dur}$3`);
};
const [sa, sb, sc, sdd] = segs;
setClip("scene-editor", sb.start, sb.dur);
setClip("scene-local", sc.start, sc.dur);
setClip("scene-end", sdd.start, r3(total - sdd.start));
setClip("layer-text", 0, sdd.start);
setClip("layer-captions", 0, total);
html = html.replace(/(<div id="root"[^>]*data-duration=")[^"]*(")/, `$1${total}$2`);
html = html.replace(/(<div id="layer-wallpaper"[^>]*data-duration=")[^"]*(")/, `$1${total}$2`);
fs.writeFileSync(file, html);

console.log(`total ${total}s, voice ${voiceOut}s, ${kept.length} words in ${caps.length} captions`);
for (const s of segs) console.log(`  seg ${s.id}: src ${s.src}-${s.srcEnd} -> out ${s.start}-${s.end}`);
console.log("  cues:", Object.entries(cues).map(([k, v]) => `${k} ${v}`).join(", "));
