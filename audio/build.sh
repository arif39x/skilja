#!/bin/bash
set -e

gcc -c -O3 audio_capture.c -o audio_capture.o
gcc -c -O3 denoise.c -o denoise.o
ar rcs libaudio_capture.a audio_capture.o denoise.o

echo "Built libaudio_capture.a successfully with RNNoise denoiser wrapper."
