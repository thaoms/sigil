#!/bin/sh
# Builds the upload zip: only the Sigil folder, named after the TOC version.
# Works on macOS and Linux, on Windows from Git Bash, and from WSL.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(sed -n 's/^## Version: *//p' Sigil/Sigil.toc | tr -d '\r')"
[ -n "$VERSION" ] || { echo "No version in Sigil.toc" >&2; exit 1; }

# LuaJIT to run the tests with. On Windows a native luajit.exe can be blocked
# (Smart App Control), so fall back to the one inside WSL.
if luajit -v >/dev/null 2>&1; then
  LUAJIT="luajit"
elif command -v wsl.exe >/dev/null 2>&1 && wsl.exe luajit -v >/dev/null 2>&1; then
  LUAJIT="wsl.exe luajit"
else
  echo "LuaJIT not found; it is needed to run the tests before packaging." >&2
  exit 1
fi
{ $LUAJIT tests/run.lua >/dev/null && $LUAJIT tests/mock.lua >/dev/null; } || { echo "Tests failed; not packaging." >&2; exit 1; }

mkdir -p dist
OUT="dist/Sigil-$VERSION.zip"
rm -f "$OUT"
if command -v zip >/dev/null 2>&1; then
  zip -qr -X "$OUT" Sigil -x '*.DS_Store'
else
  # No zip (Git Bash on Windows has none): Windows' own tar (bsdtar) writes zips.
  # Called by full path, because Git Bash's tar is GNU tar, which cannot.
  WINTAR=""
  for t in /c/Windows/System32/tar.exe /mnt/c/Windows/System32/tar.exe; do
    if [ -x "$t" ]; then WINTAR="$t"; break; fi
  done
  [ -n "$WINTAR" ] || { echo "Neither zip nor Windows tar found; cannot build the zip." >&2; exit 1; }
  "$WINTAR" -a -c -f "$OUT" --exclude '.DS_Store' Sigil
fi
echo "$ROOT/$OUT"
