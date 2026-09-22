#!/usr/bin/env python3
"""Check the App Store metadata in fastlane/metadata before running deliver.

Checks every locale folder for the files deliver uploads and the App Store
Connect limits. Exits with status 1 if anything is wrong.

    python3 fastlane/check_metadata.py
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "metadata")
PRIMARY = "en-US"

# Characters (Unicode code points), as App Store Connect counts them.
LIMITS = {
    "name": 30,
    "subtitle": 30,
    "promotional_text": 170,
    "keywords": 100,
    "description": 4000,
    "release_notes": 4000,
}
URL_FILES = ("support_url", "marketing_url", "privacy_url")
REQUIRED = tuple(LIMITS) + URL_FILES

# Folders under metadata/ that are not locales.
NOT_LOCALES = {"review_information", "trade_representative_contact_information"}

# How many languages the release notes claim. Keep in sync with the app.
LANGUAGE_COUNT = "20"


def read(locale, key):
    path = os.path.join(ROOT, locale, key + ".txt")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as fh:
        return fh.read().strip()


def words(text):
    return {w.casefold() for w in re.findall(r"\w+", text)}


def main():
    locales = sorted(
        d for d in os.listdir(ROOT)
        if os.path.isdir(os.path.join(ROOT, d)) and d not in NOT_LOCALES
    )
    errors, warnings = [], []
    primary_urls = {k: read(PRIMARY, k) for k in URL_FILES}

    width = max(len(l) for l in locales)
    print(f"{'locale':<{width}}  name  sub  promo  kw   desc  notes")
    for locale in locales:
        values = {}
        for key in REQUIRED:
            value = read(locale, key)
            if value is None:
                errors.append(f"{locale}: {key}.txt is missing")
            elif not value:
                errors.append(f"{locale}: {key}.txt is empty")
            values[key] = value or ""

        for key, limit in LIMITS.items():
            n = len(values[key])
            if n > limit:
                errors.append(f"{locale}: {key} is {n} characters (limit {limit})")

        name = values["name"]
        if name and not name.startswith("NotchPrompter"):
            errors.append(f"{locale}: name must start with 'NotchPrompter': {name!r}")

        kw = values["keywords"]
        if kw:
            items = kw.split(",")
            if any(i != i.strip() for i in items):
                errors.append(f"{locale}: keywords have spaces around a comma")
            if any(not i.strip() for i in items):
                errors.append(f"{locale}: keywords have an empty item")
            seen = [i.strip().casefold() for i in items]
            dupes = sorted({i for i in seen if seen.count(i) > 1})
            if dupes:
                errors.append(f"{locale}: keywords repeat {', '.join(dupes)}")
            # Words in the name and subtitle are indexed already, so repeating
            # them in keywords wastes characters.
            overlap = sorted(words(kw) & words(name + " " + values["subtitle"]))
            if overlap:
                warnings.append(
                    f"{locale}: keywords repeat words from name/subtitle: {', '.join(overlap)}")

        for key in URL_FILES:
            if values[key] and values[key] != primary_urls[key]:
                errors.append(f"{locale}: {key} differs from {PRIMARY}")
            if values[key] and not values[key].startswith("https://"):
                errors.append(f"{locale}: {key} is not an https URL")

        notes = values["release_notes"]
        if notes and LANGUAGE_COUNT not in notes:
            errors.append(f"{locale}: release_notes do not mention {LANGUAGE_COUNT} languages")

        print(f"{locale:<{width}}  {len(name):>4}  {len(values['subtitle']):>3}  "
              f"{len(values['promotional_text']):>5}  {len(kw):>3}  "
              f"{len(values['description']):>4}  {len(notes):>5}")

    print(f"\n{len(locales)} locales: {', '.join(locales)}")
    for w in warnings:
        print(f"WARNING {w}")
    for e in errors:
        print(f"ERROR   {e}")
    if errors:
        print(f"\nFAILED: {len(errors)} error(s)")
        return 1
    print("\nOK: all limits pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
