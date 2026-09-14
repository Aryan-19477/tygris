#!/bin/bash
set -e
VENV=/home/dev/tigervenv
NVDIR="$VENV/lib/python3.12/site-packages/nvidia"

LDPATH=""
for d in "$NVDIR"/*/lib; do
  LDPATH="$LDPATH:$d"
done
export LD_LIBRARY_PATH="$LDPATH"

"$VENV/bin/python3" -c "
import time
import tensorflow as tf

print('GPUs:', tf.config.list_physical_devices('GPU'))

with tf.device('/GPU:0'):
    a = tf.random.normal([4000, 4000])
    b = tf.random.normal([4000, 4000])
    start = time.time()
    c = tf.matmul(a, b)
    _ = c.numpy()
    print('GPU matmul time:', time.time() - start, 's')

with tf.device('/CPU:0'):
    a = tf.random.normal([4000, 4000])
    b = tf.random.normal([4000, 4000])
    start = time.time()
    c = tf.matmul(a, b)
    _ = c.numpy()
    print('CPU matmul time:', time.time() - start, 's')
"
