#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
[ -d sys ] || ./bootstrap_sys.sh
command -v quartus_sh >/dev/null || { echo "Quartus 17.0.2 not found in PATH"; exit 1; }
DATE="$(date +%y%m%d)"
printf '`define BUILD_DATE "%s"\n' "$DATE" > build_id.v
quartus_sh --flow compile VideoPlayer
RBF="output_files/VideoPlayer.rbf"
[ -f "$RBF" ] || { echo "RBF build failed"; exit 1; }
mkdir -p ../release/_Other
cp "$RBF" "../release/_Other/VideoPlayer_${DATE}.rbf"
echo "Built ../release/_Other/VideoPlayer_${DATE}.rbf"
