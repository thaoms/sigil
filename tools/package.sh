#!/bin/sh
# Builds the upload zip: only the Sigil folder, named after the TOC version.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^## Version: *//p' "$ROOT/Sigil/Sigil.toc" | tr -d '\r')"
[ -n "$VERSION" ] || { echo "No version in Sigil.toc" >&2; exit 1; }
luajit "$ROOT/tests/run.lua" >/dev/null && (cd "$ROOT" && luajit tests/mock.lua >/dev/null) || { echo "Tests failed; not packaging." >&2; exit 1; }
mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/Sigil-$VERSION.zip"
rm -f "$OUT"
(cd "$ROOT" && zip -qr -X "$OUT" Sigil -x '*.DS_Store')
echo "$OUT"
