#!/bin/zsh
# Renders the screenshots in every app language and copies them to where they are used:
#   fastlane/screenshots/<App Store locale>/1-eye-contact.jpg ... 5-private.jpg  (2880 × 1800, JPEG quality 92)
#   website/media/<lang>/1-eye-contact.jpg ... 5-private.jpg (1600 × 1000, JPEG quality 80) and editor.png
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
SHOTS=(1-eye-contact 2-voice 3-editor 4-play 5-private)

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
    -AppleLanguages "($lang)" -AppleLocale "${REGION[$lang]}"
  rm -rf "$home"
  for s in $SHOTS; do [[ -f $out/appstore-$s.png ]] || { echo "Missing $out/appstore-$s.png"; exit 1; }; done

  for loc in ${=ASC[$lang]}; do
    # JPEG at full size: App Store Connect takes it, and it is a tenth of the PNG size.
    rm -rf fastlane/screenshots/$loc && mkdir -p fastlane/screenshots/$loc
    for s in $SHOTS; do
      sips -s format jpeg -s formatOptions 92 "$out/appstore-$s.png" --out "fastlane/screenshots/$loc/$s.jpg" >/dev/null
    done
  done

  if [[ $lang == en ]]; then media=website/media; else media=website/media/$lang; fi
  mkdir -p $media
  for s in $SHOTS; do
    sips -s format jpeg -s formatOptions 80 -Z 1600 "$out/appstore-$s.png" --out "$media/$s.jpg" >/dev/null
  done
  cp "$out/window-editor.png" "$media/editor.png"

  if [[ $lang == en ]]; then
    rm -rf AppStore/screenshots && cp -R "$out" AppStore/screenshots
  fi
done
echo "Done. Raw captures are in $RAW."
