#!/usr/bin/env node
// Renders the translated promo videos.
//   node l10n/render.mjs                    -> every language, both videos
//   node l10n/render.mjs de ja              -> only these languages
//   node l10n/render.mjs --only landscape de   (or --only tiktok)
//   node l10n/render.mjs en                 -> English check renders (renders/l10n/), nothing published
// Landscape: website/media/<lang>/promo.mp4 (H.264 CRF 24 veryslow, AAC 128k, faststart) + promo-poster.webp (frame at 10 s).
// TikTok:    renders/tiktok/<lang>.mp4 (H.264 CRF 20, AAC 128k).
// The master render from HyperFrames stays in renders/l10n/ (git-ignored) until the next run.
// Runs node l10n/build.mjs first, so edits to l10n/*.json are always picked up.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const dir = path.dirname(fileURLToPath(import.meta.url));
const video = path.join(dir, "..");
const site = path.join(video, "../website/media");
const HF = "hyperframes@0.8.62";
const ALL = ["nb", "de", "fr", "es", "it", "pt-BR", "pt-PT", "nl", "sv", "da", "fi", "pl", "ja", "ko", "zh-Hans", "zh-Hant", "ru", "uk", "tr"];
const POSTER_AT = 10.0;

const args = process.argv.slice(2);
let only = null;
const oi = args.indexOf("--only");
if (oi >= 0) { only = args[oi + 1]; args.splice(oi, 2); }
const langs = args.length ? args : ALL;
for (const l of langs) if (l !== "en" && !ALL.includes(l)) throw new Error(`unknown language ${l}`);

const run = (cmd, a, cwd = video) => execFileSync(cmd, a, { cwd, stdio: "inherit" });
run("node", [path.join(dir, "build.mjs")]);
const masters = path.join(video, "renders/l10n");
fs.mkdirSync(masters, { recursive: true });

function render(project, lang, out) {
  run("npx", ["--yes", HF, "render", project, "--variables", JSON.stringify({ lang }), "--quality", "looks", "--fps", "30", "--strict-variables", "--output", out]);
}
function encode(src, dst, crf) {
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  run("ffmpeg", ["-v", "error", "-y", "-i", src, "-c:v", "libx264", "-preset", "veryslow", "-crf", String(crf), "-pix_fmt", "yuv420p",
    "-profile:v", "high", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", dst]);
}
const mb = (f) => (fs.statSync(f).size / 1048576).toFixed(1) + " MB";

for (const lang of langs) {
  const t0 = Date.now();
  if (only !== "tiktok") {
    const master = path.join(masters, `promo-${lang}.mp4`);
    render(video, lang, master);
    if (lang === "en") console.log(`en landscape master: ${master}`);
    else {
      const out = path.join(site, lang, "promo.mp4");
      encode(master, out, 24);
      const png = path.join(masters, `poster-${lang}.png`);
      run("ffmpeg", ["-v", "error", "-y", "-ss", String(POSTER_AT), "-i", master, "-frames:v", "1", png]);
      run("cwebp", ["-quiet", "-q", "82", "-m", "6", png, "-o", path.join(site, lang, "promo-poster.webp")]);
      console.log(`${lang} landscape: ${out} ${mb(out)}`);
    }
  }
  if (only !== "landscape") {
    const master = path.join(masters, `tiktok-${lang}.mp4`);
    render(path.join(video, "tiktok"), lang, master);
    if (lang === "en") console.log(`en tiktok master: ${master}`);
    else {
      const out = path.join(video, "renders/tiktok", `${lang}.mp4`);
      encode(master, out, 20);
      console.log(`${lang} tiktok: ${out} ${mb(out)}`);
    }
  }
  console.log(`== ${lang} done in ${((Date.now() - t0) / 1000).toFixed(0)} s`);
}
