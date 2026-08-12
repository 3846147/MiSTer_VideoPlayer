#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ -d sys ]; then
  echo "sys/ already exists."
  exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone --depth 1 https://github.com/MiSTer-devel/Template_MiSTer.git "$TMP/template"
cp -a "$TMP/template/sys" ./sys
# Copy the official PLL files expected by sys if Template keeps them at root.
[ -f "$TMP/template/Template.sdc" ] && cp "$TMP/template/Template.sdc" ./VideoPlayer.sdc || true
echo "Fetched official MiSTer Template sys/."
