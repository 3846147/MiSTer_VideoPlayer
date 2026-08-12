#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./arm/build_arm.sh
./fpga/build_fpga.sh
./tools/assemble_sd.sh
echo
echo "Copy the CONTENTS of release/ to the root of the MiSTer SD card."
