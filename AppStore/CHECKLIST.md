# Before submitting NotchPrompter

## Done in the project
- [x] Xcode project with App Sandbox, hardened runtime, mic entitlement, user-selected files (read/write)
- [x] Usage texts for the microphone and speech recognition
- [x] Privacy manifest (`PrivacyInfo.xcprivacy`): no tracking, no data collected, UserDefaults and file timestamp reasons
- [x] `ITSAppUsesNonExemptEncryption = NO` (no export compliance question)
- [x] App icon at every macOS size, plus `icon-1024.png`
- [x] Five 2880 × 1800 screenshots (`screenshots/appstore-*.png`)
- [x] Listing text, keywords, privacy answers and review notes (`metadata.md`)
- [x] Welcome guide, help menu, support and privacy pages
- [x] Matcher tests (`Tools/test-matcher.sh`)

## Needs you
- [x] Support goes through GitHub Issues (no email needed)
- [x] Website: GitHub Pages at https://magnram.github.io/notchprompter/, published from `website/` by `.github/workflows/pages.yml`
- [ ] Make the repo public (Pages on a free account needs a public repo), then turn on Pages with "GitHub Actions" as the source
- [ ] Test voice-follow and recording (camera + mic, saved in ~/Movies/NotchPrompter) in the sandboxed build (`./build.sh && open NotchPrompter.app`)
- [ ] Record the voice-over from the updated `video/Voiceover-manuscript.txt` (lines 3 and 5 changed), then follow `video/RETIME.md`
- [ ] App Store Connect: create the app (bundle ID `com.magnusramm.NotchPrompter`), paste `metadata.md`, upload screenshots,
      answer App Privacy with "Data Not Collected"
- [ ] Xcode → Product → Archive → Distribute App → App Store Connect → Upload, then submit for review
- [ ] After approval: put the App Store link in `website/index.html` (the `store-badge` link)
