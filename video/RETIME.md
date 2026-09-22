# Timing and media (v2: real take 12.09.41)

All timing lives in `timings.json`. Times in `cues` and `scenes` are VIDEO seconds.
Video time = camera time - `source.voiceIn` (1.75 s). Screen-recording time = camera time + `source.screenLead` (1.00 s,
read from the REC timer in the panel).

- Change a scene cut or a headline cue: edit `timings.json`, run `node retime.mjs`, then check and render.
- Use a different take: copy the camera and screen movies into `source/`, point `source.camera` / `source.screen`
  at them, set `voiceIn` / `voiceOut` / `screenLead`, then run `sh prep.sh`. It rebuilds the voice, the presenter
  cut-out, the prompter crop, and reruns `retime.mjs`.
- Find new cue times: `npx hyperframes transcribe audio/voice-full.wav` writes `transcript.json`, and
  `node retime.mjs --words transcript.json` prints the words in video seconds. Whisper can run 0.4 to 1.0 s early,
  so confirm onsets with `ffmpeg -i audio/voiceover.wav -af silencedetect=n=-40dB:d=0.2 -f null -`.

Do not hand-edit the `TIMINGS` block or the `data-start` / `data-duration` / `data-media-start` of the scenes,
`#live`, `#presenter`, `#take-video` or `#voiceover` in index.html. `retime.mjs` owns them.

Check and render:

    npx hyperframes check
    npx hyperframes render --quality high --fps 30 --output renders/promo-v2.mp4
