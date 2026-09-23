# Translated promo videos

Both compositions (`../index.html` landscape, `../tiktok/index.html` vertical) have one variable, `lang`
(default `en`). English is the text written in the HTML and renders exactly as before. Any other language:

- takes its on-screen text from `<lang>.json` (`ui`), matched by the `data-l10n` attributes;
- swaps the app captures (`data-l10n-img`) for `assets/l10n/<lang>/` (editor window, Play mode);
- adds burned-in subtitles from `<lang>.json` (`subs`), timed by `cues.json`;
- shrinks text that does not fit its box (`data-fit`: 1 = one line, 2/3 = that many lines);
- uses Hiragino Sans (ja), Apple SD Gothic Neo (ko) or PingFang SC/TC (zh) next to SF Pro, from the Mac's
  own fonts (`local()`), so render on a Mac.

The audio, the presenter and the screen recording of the prompter are the same in every language.

## Files

- `en.json`: the English source and the list of keys. `TRANSLATING.md`: rules for translators.
- `<lang>.json`: one per language. A subtitle of `""` joins that cue to the one before it; `\n` is a preferred line break.
- `cues.json`: when each subtitle shows, in landscape seconds. The TikTok maps them through `../tiktok/cut.json`.
- `build.mjs`: writes all of it into both `index.html` files (the `L10N` block) and copies the app captures
  from `build/Screens/<lang>/` (made by `Tools/render-all-languages.sh`).
- `render.mjs`: builds, then renders.
- `snap.sh`: snapshots of one language without a render.

## Commands (from `video/`)

    node l10n/build.mjs                          # after editing a json file
    node l10n/render.mjs                         # all 19 languages, both videos
    node l10n/render.mjs de ja                   # some languages
    node l10n/render.mjs --only landscape fi     # one video
    sh l10n/snap.sh landscape de snapshots/de 10,25,47
    npx hyperframes render --variables '{"lang":"de"}' --output renders/de.mp4   # by hand

Outputs: `website/media/<lang>/promo.mp4` and `promo-poster.png` (frame at 10 s), `renders/tiktok/<lang>.mp4`.
Then run `python3 website/i18n/build.py` so each language page points at its own video.
