#!/bin/bash
set -e
BASE="/media/fat/games/VideoPlayer"
BIN="$BASE/VideoPlayer"
START="/media/fat/linux/user-startup.sh"
LOGDIR="/media/fat/logs/VideoPlayer"

clear
echo "========================================"
echo " VideoPlayer Core Installer"
echo "========================================"
[ -x "$BIN" ] || { echo "Missing $BIN"; sleep 8; exit 1; }
mkdir -p "$LOGDIR" /media/fat/video /media/fat/linux
[ -f "$START" ] || { echo '#!/bin/bash' > "$START"; chmod +x "$START"; }
# Remove previous managed block, then append exactly once.
TMP="${START}.vp.tmp"
awk '/# BEGIN VIDEOPLAYER CORE/{skip=1;next}/# END VIDEOPLAYER CORE/{skip=0;next}!skip{print}' "$START" > "$TMP"
cat >> "$TMP" <<'EOF'
# BEGIN VIDEOPLAYER CORE
if [ -x /media/fat/games/VideoPlayer/VideoPlayer ]; then
  pgrep -f '/media/fat/games/VideoPlayer/VideoPlayer' >/dev/null 2>&1 || \
    /media/fat/games/VideoPlayer/VideoPlayer >>/media/fat/logs/VideoPlayer/engine.log 2>&1 &
fi
# END VIDEOPLAYER CORE
EOF
mv "$TMP" "$START"
chmod +x "$START"
sync
echo
echo "Installed autostart into:"
echo "  $START"
echo
echo "Reboot MiSTer once, then load VideoPlayer core."
sleep 6
