#!/bin/sh
# Copies the addon into the local WoW Forever install. Then /reload in game
# (or restart the game the first time, so it notices the new addon).
#
#   tools/install.sh                  finds the game in the usual places
#   tools/install.sh <AddOns folder>  installs there instead
#
# Works on macOS and Linux, on Windows from Git Bash, and from WSL.
set -e
SRC="$(cd "$(dirname "$0")/.." && pwd)/Sigil"

# The first _forever_/Interface/AddOns found in the usual install places:
# /Applications on macOS, then each drive as Git Bash (/c) and WSL (/mnt/c) see it.
find_addons() {
  for root in /Applications /c /d /e /f /g /mnt/c /mnt/d /mnt/e /mnt/f /mnt/g; do
    for dir in "World of Warcraft" "Program Files (x86)/World of Warcraft" \
               "Program Files/World of Warcraft" "Games/World of Warcraft"; do
      if [ -d "$root/$dir/_forever_" ]; then
        echo "$root/$dir/_forever_/Interface/AddOns"
        return
      fi
    done
  done
}

if [ -n "$1" ]; then
  ADDONS="$1"
  # Accept a Windows path such as "D:\World of Warcraft\_forever_\Interface\AddOns".
  if command -v cygpath >/dev/null 2>&1; then ADDONS="$(cygpath -u "$ADDONS")"; fi
  mkdir -p "$ADDONS"
else
  ADDONS="$(find_addons)"
  if [ -z "$ADDONS" ]; then
    echo "Could not find World of Warcraft/_forever_. Pass the AddOns folder:" >&2
    echo "  tools/install.sh \"/path/to/World of Warcraft/_forever_/Interface/AddOns\"" >&2
    exit 1
  fi
  mkdir -p "$ADDONS"
fi
DEST="$ADDONS/Sigil"

if command -v rsync >/dev/null 2>&1; then
  mkdir -p "$DEST"
  rsync -a --delete "$SRC/" "$DEST/"
else
  # No rsync (Git Bash on Windows has none): replace the folder with a fresh
  # copy, which leaves the same result as rsync --delete.
  rm -rf "$DEST"
  cp -R "$SRC" "$DEST"
fi
echo "Installed to $DEST"
