#!/bin/bash
# Launcher: runs a python script inside the WSL venv with GPU libraries on
# the dynamic linker path. Usage: bash run_wsl.sh <script.py> [args...]
set -e
VENV=/home/dev/tigervenv
NVDIR="$VENV/lib/python3.12/site-packages/nvidia"

LDPATH=""
for d in "$NVDIR"/*/lib; do
  LDPATH="$LDPATH:$d"
done
export LD_LIBRARY_PATH="$LDPATH"

cd /home/dev/vikasit/identification
exec "$VENV/bin/python3" "$@"
