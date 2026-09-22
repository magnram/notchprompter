<p align="center"><img src="AppStore/icon-1024.png" width="128" alt=""></p>

# NotchPrompter

A free, open-source teleprompter for the Mac that hangs right under your camera and follows your voice.
Read your script and keep eye contact.

**Website:** https://magnram.github.io/notchprompter/

![NotchPrompter following a script under the camera](AppStore/screenshots/appstore-2-voice.png)

## Features

- **Follows your voice.** Press the microphone and talk. The text moves as you read, so the next words are always under the camera.
- **Any language.** It sees which language your script is in and listens for it.
- **Keeps up when you skip.** Skip a sentence or say "uh", and it finds your place. Pause, and it waits.
- **Or press play.** Smooth scrolling with a 3-2-1 countdown and speed controls.
- **Built-in script editor.** Import Word, Markdown, RTF, HTML or text. Notes in (parentheses) or [brackets] are shown but not read out.
- **Record yourself.** Film your camera and microphone while you read, and optionally the screen too. Takes go to Movies › NotchPrompter.
- **Invisible to your audience.** Hidden from screen sharing, screenshots and recordings.
- **Runs completely on your Mac.** Speech is recognised on-device (with Dictation turned on). No account, no tracking.

## Requirements

macOS 15 Sequoia or later. Works best on a MacBook with a notch.

## Build

Open `NotchPrompter.xcodeproj` in Xcode 16 or later and run, or from the terminal:

```sh
./build.sh && open NotchPrompter.app
```

To sign with your own team, change `DEVELOPMENT_TEAM` in the project settings.

## Project layout

| Folder | What's in it |
|---|---|
| `NotchPrompter/` | The app (AppKit + SwiftUI) |
| `Config/` | Entitlements and Info.plist |
| `Tools/` | Icon generator, screenshot renderer and matcher tests (`Tools/test-matcher.sh`) |
| `website/` | The website, published to GitHub Pages by `.github/workflows/pages.yml` |
| `AppStore/` | App Store listing text, screenshots and the submission checklist |
| `video/` | The promo video, made with HyperFrames |

## Contributing

Bug reports and ideas are welcome in [Issues](https://github.com/magnram/notchprompter/issues). Pull requests too.

## License

[MIT](LICENSE)
