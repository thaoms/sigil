#!/bin/sh
# Copies the addon into the local WoW Forever install. Then /reload in game
# (or restart the game the first time, so it notices the new addon).
set -e
SRC="$(cd "$(dirname "$0")/.." && pwd)/Sigil"
DEST="${1:-/Applications/World of Warcraft/_forever_/Interface/AddOns}/Sigil"
mkdir -p "$DEST"
rsync -a --delete "$SRC/" "$DEST/"
echo "Installed to $DEST"
