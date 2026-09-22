# NotchPrompter: App Store listing

Paste these into App Store Connect → the app → macOS App → version 1.0.

## Basics

| Field | Value |
|---|---|
| Name (30) | NotchPrompter: Teleprompter |
| Subtitle (30) | Eye contact while you read |
| Bundle ID | com.magnusramm.NotchPrompter |
| SKU | notchprompter-mac-1 |
| Primary category | Productivity |
| Secondary category | Video |
| Price | Free |
| Age rating | 4+ (answer "None" to every question) |
| Copyright | © 2026 Magnus Ramm |
| Support URL | https://magnram.github.io/notchprompter/support.html |
| Marketing URL | https://magnram.github.io/notchprompter/ |
| Privacy Policy URL | https://magnram.github.io/notchprompter/privacy.html |

## Promotional text (170)

Read your script and keep eye contact. NotchPrompter hangs under your camera and follows your voice in any language, completely on your Mac.

## Keywords (100)

teleprompter,prompter,script,autocue,speech,video,webcam,presentation,eye contact,notch,voice,record

## Description

Look people in the eye while you read your script.

NotchPrompter puts your script in a small black panel that hangs from the top of your screen, right under the camera. On a MacBook with a notch it blends into the notch. To the people watching, it looks like you are talking straight to them.

FOLLOWS YOUR VOICE, IN ANY LANGUAGE
Press the microphone and just talk. NotchPrompter listens as you read and moves the text with you, so the next words are always right under the camera. Words you have said fade out. It sees which language your script is in and listens for it: English, Norwegian, German, Spanish, Japanese and dozens more. Nothing to set up.

KEEPS UP WHEN YOU SKIP
Skip a sentence, change a word, say "uh". NotchPrompter finds where you are and jumps ahead with you. Pause, take a breath: it waits. Lost your place? Click the word you are on.

OR PRESS PLAY
Prefer a steady pace? Press play for smooth scrolling with a 3-2-1 countdown. Hover over the text to pause. The tortoise and the hare change the speed.

A LITTLE EDITOR FOR YOUR SCRIPTS
Write and edit your scripts in the built-in editor, or import text, Markdown, Word, RTF and HTML files. Everything saves automatically. See the word count and about how long each script takes to read.

RECORD YOURSELF
Press record to film yourself with your camera and microphone while the script follows your voice. Each take is saved as a movie in Movies › NotchPrompter.

INVISIBLE TO YOUR AUDIENCE
The prompter is hidden from screen sharing, screenshots and recordings, so only you can see it.

MADE FOR
• Video calls and online meetings
• YouTube, courses and screen recordings
• Presentations, pitches and webinars
• Anyone who wants to sound natural and look confident on camera

FREE AND OPEN SOURCE
No ads, no subscription, no account. The source code is on GitHub: github.com/magnram/notchprompter

RUNS COMPLETELY ON YOUR MAC
Speech is recognised on your Mac, not in the cloud. No account, no tracking, no ads. Your scripts and recordings never leave your Mac. Voice-follow never saves audio.

## What's new (version 1.0)

First release.

## Screenshots (2880 × 1800, in this order)

1. `screenshots/appstore-1-eye-contact.png`
2. `screenshots/appstore-2-voice.png`
3. `screenshots/appstore-3-editor.png`
4. `screenshots/appstore-4-play.png`
5. `screenshots/appstore-5-private.png`

Rebuild them with `Tools/render-screens.sh`.

## App Privacy (the nutrition label)

- **Data collection:** "No, we do not collect data from this app."
- Why this is right: the app has no server, no analytics and no account. Scripts are saved only in the app's own folder on the Mac. Speech recognition runs on the Mac by default; if the user allows Apple's servers, Apple is the processor, not the developer. Recordings are saved only in the user's Movies folder and are never uploaded. Apple's guidance says data processed only on device, or by Apple's own frameworks on the user's behalf, is not "collected" by the developer.

## App Review information

**Sign-in:** not needed.

**Notes for the reviewer:**

> NotchPrompter is a teleprompter that sits at the top centre of the screen, under the camera.
>
> To test voice-follow:
> 1. On first launch, a welcome guide opens. Click "Allow Microphone and Speech Recognition" and allow both.
> 2. Click "Try It Now". The prompter appears at the top of the screen with a practice script.
> 3. Read the practice script out loud. The text scrolls as you speak, and words you have said fade out.
>
> To test play mode, press the play button (or Space) in the prompter. Hover over the prompter to see the buttons.
> The pencil button opens the script editor. Scripts can also be imported from File → Import.
>
> The prompter window is hidden from screen sharing and screenshots on purpose (a setting in Settings → Privacy), so it will not show in screen recordings of the review session unless that setting is turned off.
>
> To test recording, press the record button (the circle) in the prompter, or Prompter → Record Video (⌥⌘R). Allow the camera and microphone. The prompter counts down, films you while it follows your voice, and saves the movie in ~/Movies/NotchPrompter when you press stop. Settings → Recording → "Also record the screen" adds a second movie of the screen (ScreenCaptureKit; macOS asks for screen recording access). Text in (parentheses) or [brackets] is a stage direction: shown, but not read out.
>
> The microphone is used for speech recognition while the microphone button is on, and for the sound of a recording while recording. Speech recognition runs on the Mac by default (Settings → Privacy). Audio is stored only in recordings the user starts, in their own Movies folder.

## Export compliance

The app uses no encryption beyond what macOS provides. Answer "None of the algorithms mentioned above" (or set `ITSAppUsesNonExemptEncryption = NO`, which the project already does).
