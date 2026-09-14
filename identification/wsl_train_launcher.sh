#!/bin/bash
VENV=/home/dev/tigervenv
NVDIR="$VENV/lib/python3.12/site-packages/nvidia"

LDPATH=""
for d in "$NVDIR"/*/lib; do
  LDPATH="$LDPATH:$d"
done
export LD_LIBRARY_PATH="$LDPATH"

cd /home/dev/vikasit/identification
exec "$VENV/bin/python3" -u train_embedding.py
