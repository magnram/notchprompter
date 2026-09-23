# Translating the promo videos

Source: `video/l10n/en.json`. Write `video/l10n/<lang>.json` with exactly the same keys (`ui` and `subs`), no `_readme`, plus `"lang": "<lang>"`.
UTF-8, real characters (no \u escapes), valid JSON.

## Reuse existing wording (terms must match the site and app)
- `website/i18n/<lang>.json` → `strings` (English key → translation). Exact matches to reuse:
  - "Any language, automatically" (for tt_follow_sub / lang_h1 wording), "Follows your voice" → tt_follow_h1,
  - "Keeps up when you skip" → skip_h1, "Record yourself" → record_h1, "Invisible to your audience" → hidden_h1,
  - "Runs completely on your Mac" → local_h1, "Or press play", "Built-in editor",
  - "NotchPrompter – Teleprompter under your camera" → end_tag is the part after the dash,
  - "<small>Download on the</small><strong>Mac App Store</strong>" → badge_small / badge_big (copy exactly),
  - "Free and open source ..." / "© 2026 Magnus Ramm · Free and open source (MIT)" → wording for tt_free_h1 / tt_end_free.
  - The site's voice-over lines ("You know the feeling. ...") show how the site already translated the same sentences: reuse them for `subs` where they match.
- `NotchPrompter/Localizable.xcstrings` (app UI): "Play mode" → play_h1, "%@ REC %@" (the app's REC word) → rec, "Record", "Scripts", "Script", "Teleprompter", "Prompter".
- `NotchPrompter/ScreenshotContent.swift` (marketing lines per language): "Keep eye contact while you read", "It follows your voice", "Or press play", "Invisible to your audience".
- `fastlane/metadata/<locale>/` (App Store text) for tone and terms.
Use the same address form (du/Sie, tu/vous, ты/вы …) as the website for that language.

## Space limits (the text must fit; shorter is better)
Landscape video headlines (open_h1, tagline, lang_h1, pause_h1, skip_h1, play_h1, editor_h1, record_h1) are one line: keep to about 26 Latin characters (about 13 CJK characters). *_sub lines about 40 Latin chars. local_h1 and hidden_h1 about 30. skip_tag, sharing, rec: one or two short words. badge_small ≤ 22 chars. screen_mine / screen_theirs ≤ 20 chars. take_cap ≤ 45 chars.
TikTok (tt_*): headlines may take two lines of about 16 Latin chars each (8 CJK). tt_hook_pill ≤ 34 chars; tt_end_free ≤ 22 chars.
"NotchPrompter", "Mac App Store", "GitHub", "MIT", "Word", "Markdown", "RTF" stay as is.

## Subtitles (`subs`)
Burned-in subtitles over the English voice. Each cue in `video/l10n/cues.json` is shown while that English phrase is spoken (from/to seconds), so a cue must translate that phrase only, by meaning, not word for word. Natural, spoken, short. Max about 42 Latin characters per cue line and 2 lines (CJK: about 18 characters per line). Use "\n" to mark a good line break for a cue longer than about 40 chars (CJK: longer than 18); never break inside a word. CJK: no spaces between words; normal full-width punctuation (、。？). If the target word order needs two neighbouring cues joined, put the joined text in the first cue and "" in the second (it then stays on screen for both). Use that rarely. The skipped line is not spoken, so no cue for it. "NotchPrompter" is the product name, not translated.
