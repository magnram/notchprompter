---
workflow: product-launch-video
flow: automation
storyboard: no
message: "Keep eye contact while you read your script."
destination: website-embed + youtube
aspect: 1920x1080
language: en
audience: "People who present, record videos, and take video calls"
length: 51s
voice: user-recorded (camera audio of take 12.09.41)
vo_mode: verbatim
angle: problem-solution
---

## Intent

A ~30 second promo for NotchPrompter, a macOS teleprompter that hangs a small black
panel from the top centre of the screen, right under the camera (it merges with the
notch on MacBooks). Problem -> solution: open on the pain (reading notes makes your eyes
drift down and away from people), reveal the prompter under the notch, show it following
a voice live, then quick beats for Play mode, the script Editor, invisible-to-audience,
and an end card. Calm, rounded, Apple-like motion. No glitch effects.

UPDATE (mid-run, from the user): the user will record their own voice-over from
`Voiceover-manuscript.txt` (6 lines, verbatim, in order). No generated speech. Scenes follow
the lines in order; on-screen text supports the voice and never repeats it word for word.
The recording does not exist yet: build and render with estimated timings (~150 wpm, short
pauses between lines) and no audio. All timings live in one place (`timings.json`) so a
`voiceover.m4a`/`.wav` can be dropped in and the scenes retimed later. Music: none.

UPDATE 2 (v2, from the user): rebuilt on the real take 12.09.41. The voice is the camera
movie's own audio (denoised, about -16 LUFS, silence trimmed). The animated prompter is replaced
by real screen footage of the panel, cropped from the take's screen recording, in the hero,
voice-follow, pause and skip beats; the skip shows the skipped line marked, then the jump.
The user appears as a background-removed cut-out (Apple Vision person segmentation): large at
the open, looking into the lens with the real prompter above him; small in the lower-right corner
during the prompter beats; the unmatted take in a REC card at "record yourself" (the take was
filmed by the app); on the right of the end card. He never covers panel text or headlines, and
is never flipped. Headlines: "Any language", "Waits when you pause", "Keeps up when you skip",
"Record yourself", "Runs completely on your Mac". The v1 render is kept as website/media/promo-v1.mp4.

## Assets

- source/take-120941-camera.mov, source/take-120941-screen.mov: copies of the take (read only).
- assets/presenter.webm: Vision person matte, VP9 alpha. assets/prompter-live.mp4: panel crop.
- audio/voiceover.wav: the trimmed voice. See RETIME.md and prep.sh.

- AppStore/icon-1024.png — app icon; end card.
- AppStore/screenshots/window-editor.png — script editor window (1720x1040 @2x); Editor beat.
- AppStore/screenshots/prompter-playing.png — prompter in Play mode with button bar; Play beat.
- AppStore/screenshots/prompter-reading.png, prompter-big.png — prompter mid-read; reference for the hero.
- AppStore/screenshots/window-popover.png, window-settings.png, window-welcome.png — optional.
- AppStore/screenshots/appstore-*.png — finished marketing stills; look reference only.

Real app captures: do not alter the UI they show.

## Customizations

- Hero moment rebuilt in HTML so it truly animates: black notch panel at top centre of a
  Mac desktop (wallpaper gradient #FC8C61 -> #9E40D9 -> #294DDB); script text inside; words
  turn from white to 30% grey one by one on a speaking rhythm while the text glides up so
  the next words stay on the top line; a 5-bar white mic meter bounces beside the notch.
  Sample text: "You know the feeling. You read your notes, and your eyes drift down and
  away from the people you are talking to. With NotchPrompter, your script sits right
  under the camera."
- End card: app icon, "NotchPrompter", "Teleprompter under your camera",
  "Download on the Mac App Store".

## Notes

- Product facts: follows your voice (red mic, text scrolls with you, said words fade to
  grey, 5-bar mic meter, waits when you pause or go off script, click a word to jump);
  Play mode (steady scroll, 3-2-1 countdown, hover to pause, tortoise/hare speed);
  built-in editor (script list left, text right, "Read with Voice"; imports Word,
  Markdown, RTF, text); hidden from screen sharing and recordings; private, no account,
  no tracking, audio never saved; macOS 15+, Mac App Store.
- Brand: dark UI, black prompter panel, white bold system-ui / Inter text, accent red
  #FA4F4A for the mic.
- Output: MP4 1920x1080, 30 fps, H.264 -> copy to website/media/promo.mp4 plus poster
  website/media/promo-poster.png. Do not publish, upload, or commit.
- Autonomous run: ask the user nothing.
