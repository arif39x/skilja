#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

echo "Building and running ONNX C API verification"
gcc -O3 -Ithird_party/onnxruntime/include \
    audio/verify_onnx.c \
    -Lthird_party/onnxruntime/lib -lonnxruntime -lm \
    -Wl,-rpath,"$ROOT_DIR/third_party/onnxruntime/lib" \
    -o audio/verify_onnx

./audio/verify_onnx models/2stem_separator_fp32.onnx
./audio/verify_onnx models/2stem_separator_int8.onnx
