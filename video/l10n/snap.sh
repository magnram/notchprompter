#!/bin/sh
# Snapshots of one language without rendering: makes a throwaway copy of the project whose `lang`
# variable defaults to <lang> (snapshot has no --variables), then runs hyperframes snapshot.
#   sh l10n/snap.sh <landscape|tiktok> <lang> <out-dir> <t1,t2,...>
set -e
KIND=$1 LANG_=$2 OUT=$3 AT=$4
VIDEO=$(cd "$(dirname "$0")/.." && pwd)
if [ "$KIND" = tiktok ]; then SRC=$VIDEO/tiktok; else SRC=$VIDEO; fi
TMP=$(mktemp -d "${TMPDIR:-/tmp}/np-snap.XXXXXX")
for f in "$SRC"/*; do
  case "$(basename "$f")" in index.html|renders|snapshots|node_modules) ;; *) ln -s "$f" "$TMP/";; esac
done
sed "s/\"default\":\"en\"/\"default\":\"$LANG_\"/" "$SRC/index.html" > "$TMP/index.html"
mkdir -p "$OUT"
npx --yes hyperframes@0.8.62 snapshot "$TMP" --at "$AT" --no-end --output "$OUT" --timeout 20000
rm -rf "$TMP"
