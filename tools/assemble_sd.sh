#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
REL="$PWD/release"
mkdir -p "$REL/_Other" "$REL/games/VideoPlayer" "$REL/Scripts" "$REL/video"
[ -f install/Install_VideoPlayer.sh ] && cp install/Install_VideoPlayer.sh "$REL/Scripts/Install_VideoPlayer.sh"
cat > "$REL/video/_PUT_VIDEOS_HERE.txt" <<'EOF'
Use MiSTer OSD -> Load Video. Recommended first validation format:
AVI / XVID (MPEG-4 Part 2) / 640x480 / 30fps / MP3.
EOF
echo "Release tree ready at: $REL"
find "$REL" -maxdepth 3 -type f | sort
