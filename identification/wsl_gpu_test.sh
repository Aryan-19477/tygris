#!/bin/bash
set -e
VENV=/home/dev/tigervenv
NVDIR="$VENV/lib/python3.12/site-packages/nvidia"

LDPATH=""
for d in "$NVDIR"/*/lib; do
  LDPATH="$LDPATH:$d"
done
export LD_LIBRARY_PATH="$LDPATH"

echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
echo ""
echo "checking libcudart.so.12 exists on disk:"
ls -la "$NVDIR/cuda_runtime/lib/libcudart.so.12"
echo ""

"$VENV/bin/python3" -c "
import ctypes
ctypes.CDLL('libcudart.so.12')
print('libcudart OK')
ctypes.CDLL('libcudnn.so.9')
print('libcudnn OK')

import tensorflow as tf
print('TF version:', tf.__version__)
print('GPUs:', tf.config.list_physical_devices('GPU'))
"
