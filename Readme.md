# skilja

Fast, terminal-native stem separation and audio visualization powered by ONNX Runtime and Odin

## Prerequisites

- **Odin compiler**: [`odin`](https://odin-lang.org/)
- **C compiler**: `gcc` / `clang`
- **Dependencies**: `librnnoise-dev`, `pthread`, `m`, `dl`

## Build & Run

### 1. Build C Audio Library & FFI Wrappers

Run the audio build script (compiles miniaudio capture, RNNoise denoiser wrapper, and ONNX Runtime demuxer FFI into `libaudio_capture.a`):

```bash
./scripts/build_audio.sh
```

Or manually:

```bash
cd audio
gcc -c -O3 audio_capture.c -o audio_capture.o
gcc -c -O3 denoise.c -o denoise.o
gcc -c -O3 demuxer.c -I../third_party/onnxruntime-linux-x64-1.29.0/include -o demuxer.o
ar rcs libaudio_capture.a audio_capture.o denoise.o demuxer.o
cd ..
```

### 2. Build the Odin Executable

Link against ONNX Runtime and system libraries:

```bash
odin build . -out:skilja -extra-linker-flags:"-Lthird_party/onnxruntime-linux-x64-1.29.0/lib -lonnxruntime -lrnnoise -lpthread -lm -ldl"
```

### 3. Run Skilja

Make sure ONNX Runtime shared libraries are available in your dynamic link path (or present in `third_party/onnxruntime-linux-x64-1.29.0/lib`):

```bash
LD_LIBRARY_PATH=third_party/onnxruntime-linux-x64-1.29.0/lib:$LD_LIBRARY_PATH ./skilja
```

*Press `q`, `Q`, or `Esc` to quit.*
