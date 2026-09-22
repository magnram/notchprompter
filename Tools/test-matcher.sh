#!/bin/zsh
# Compiles and runs the VoiceMatcher tests.
set -e
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/notchprompter-matcher-tests"
swiftc -O -o "$OUT" Tools/MatcherTests/main.swift NotchPrompter/Voice.swift
"$OUT"
