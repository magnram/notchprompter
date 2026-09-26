#!/bin/zsh
# Renders the screenshots in every app language and copies them to where they are used:
#   fastlane/screenshots/<App Store locale>/1-eye-contact.jpg ... 7-private.jpg  (2880 × 1800, JPEG quality 92)
#   website/media/<lang>/2-voice.webp ... 5-private.webp (1600 × 1000, WebP quality 82), editor.webp (lossless)
#   and 1-eye-contact.jpg (the link preview, JPEG quality 80)
#   English: AppStore/screenshots/ (all captures), fastlane/screenshots/en-US/ and website/media/ itself.
#
#   Tools/render-all-languages.sh            # all languages
#   Tools/render-all-languages.sh de ja      # only these
#
# Each language runs with its own empty home folder (CFFIXED_USER_HOME), so the renderer never
# touches your real scripts or settings, and every run starts with the practice script in its language.
set -e
cd "$(dirname "$0")/.."
ROOT=$PWD
LANGS=(en nb de fr es it pt-BR pt-PT nl sv da fi pl ja ko zh-Hans zh-Hant ru uk tr)
(( $# )) && LANGS=($@)
RAW=$ROOT/build/Screens
APP=$ROOT/build/Render/Build/Products/Debug/NotchPrompter.app/Contents/MacOS/NotchPrompter

# App language -> App Store Connect locale folders (fastlane).
typeset -A ASC
ASC=(en "en-US" nb "no" de "de-DE" fr "fr-FR" es "es-ES es-MX" it "it" pt-BR "pt-BR" pt-PT "pt-PT"
     nl "nl-NL" sv "sv" da "da" fi "fi" pl "pl" ja "ja" ko "ko" zh-Hans "zh-Hans" zh-Hant "zh-Hant"
     ru "ru" uk "uk" tr "tr")
# App language -> region for the locale (date and number formats).
typeset -A REGION
REGION=(en en_US nb nb_NO de de_DE fr fr_FR es es_ES it it_IT pt-BR pt_BR pt-PT pt_PT nl nl_NL sv sv_SE
        da da_DK fi fi_FI pl pl_PL ja ja_JP ko ko_KR zh-Hans zh_CN zh-Hant zh_TW ru ru_RU uk uk_UA tr tr_TR)
SHOTS=(1-eye-contact 2-voice 3-sync 4-editor 5-record 6-play 7-private)
# The website shows these App Store shots under its own, older names.
typeset -A WEB
WEB=(2-voice 2-voice 3-editor 4-editor 4-play 6-play 5-private 7-private)
# The camera preview's picture (the camera stays off), and the iPhone app's editor in each language
# for the sync shot (NotchPrompter-iOS: Tools/screenshots/make.sh, its raw "sync" capture).
MEDIA=${MEDIA:-$ROOT/build/ScreenshotMedia}
PHONE=${PHONE:-$ROOT/../NotchPrompter-iOS/build/Screens}
[[ -f $MEDIA/camera.jpg ]] || { echo "Missing $MEDIA/camera.jpg"; exit 1; }

xcodebuild -project NotchPrompter.xcodeproj -scheme NotchPrompter -configuration Debug \
  -derivedDataPath build/Render ENABLE_APP_SANDBOX=NO CODE_SIGN_ENTITLEMENTS= CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build -quiet

for lang in $LANGS; do
  [[ -n ${REGION[$lang]} ]] || { echo "Unknown language: $lang"; exit 1; }
  echo "== $lang"
  out=$RAW/$lang home=$RAW/.home-$lang
  rm -rf "$out" "$home"
  mkdir -p "$home"
  CFFIXED_USER_HOME=$home "$APP" -renderScreens "$out" \
    -AppleLanguages "($lang)" -AppleLocale "${REGION[$lang]}" \
    -demoCamera "$MEDIA/camera.jpg" -demoPhone "$PHONE/$lang/sync.png"
  [[ -f $PHONE/$lang/sync.png ]] || { echo "Missing $PHONE/$lang/sync.png"; exit 1; }
  rm -rf "$home"
  for s in $SHOTS; do [[ -f $out/appstore-$s.png ]] || { echo "Missing $out/appstore-$s.png"; exit 1; }; done

  for loc in ${=ASC[$lang]}; do
    # JPEG at full size: App Store Connect takes it, and it is a tenth of the PNG size.
    rm -rf fastlane/screenshots/$loc && mkdir -p fastlane/screenshots/$loc
    for s in $SHOTS; do
      sips -s format jpeg -s formatOptions 92 "$out/appstore-$s.png" --out "fastlane/screenshots/$loc/$s.jpg" >/dev/null
      jpegtran -copy none -optimize -progressive -outfile "fastlane/screenshots/$loc/$s.jpg" "fastlane/screenshots/$loc/$s.jpg"
    done
  done

  if [[ $lang == en ]]; then media=website/media; else media=website/media/$lang; fi
  mkdir -p $media
  # WebP for the page images: under half the size of JPEG at the same quality.
  # The first shot is only the link preview (og:image), and some sites can't show WebP, so it stays JPEG.
  sips -Z 1600 "$out/appstore-1-eye-contact.png" --out "$RAW/.og.png" >/dev/null
  sips -s format jpeg -s formatOptions 80 "$RAW/.og.png" --out "$media/1-eye-contact.jpg" >/dev/null
  jpegtran -copy none -optimize -progressive -outfile "$media/1-eye-contact.jpg" "$media/1-eye-contact.jpg"
  for s in ${(k)WEB}; do
    sips -Z 1600 "$out/appstore-${WEB[$s]}.png" --out "$RAW/.page.png" >/dev/null
    cwebp -quiet -q 82 -m 6 "$RAW/.page.png" -o "$media/$s.webp"
  done
  rm -f "$RAW/.og.png" "$RAW/.page.png"
  cwebp -quiet -lossless -z 9 "$out/window-editor.png" -o "$media/editor.webp"

  if [[ $lang == en ]]; then
    rm -rf AppStore/screenshots && cp -R "$out" AppStore/screenshots
  fi
done
echo "Done. Raw captures are in $RAW."
