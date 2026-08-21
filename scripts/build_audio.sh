#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIO_DIR="$(cd "$SCRIPT_DIR/../audio" && pwd)"

cd "$AUDIO_DIR"

gcc -c -O3 audio_capture.c -o audio_capture.o
gcc -c -O3 denoise.c -o denoise.o
gcc -c -O3 demuxer.c -I../third_party/onnxruntime-linux-x64-1.29.0/include -o demuxer.o
ar rcs libaudio_capture.a audio_capture.o denoise.o demuxer.o

echo "Built libaudio_capture.a successfully with RNNoise denoiser wrapper and ONNX demuxer FFI."
