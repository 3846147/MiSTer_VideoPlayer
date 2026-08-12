#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
command -v docker >/dev/null || { echo "Docker is required"; exit 1; }
docker build -t mister-videoplayer-arm .
CID="$(docker create mister-videoplayer-arm)"
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT
mkdir -p ../release/games/VideoPlayer
docker cp "$CID:/work/VideoPlayer" ../release/games/VideoPlayer/VideoPlayer
chmod +x ../release/games/VideoPlayer/VideoPlayer
echo "Built ../release/games/VideoPlayer/VideoPlayer"
