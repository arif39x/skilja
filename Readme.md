# skilja

To build and run skilja, you must have 'odin' and 'gcc' installed.

```bash
# 1. Compile the audio helper statically
cd audio
gcc -c -O2 -Os -fPIC audio_capture.c -o audio_capture.o
ar rcs libaudio_capture.a audio_capture.o
cd ..

# 2. Build the Odin project
odin build . -out:skilja -extra-linker-flags:"-lpthread -lm -ldl"

# 3. Run it
./skilja
```

*Press `q`, `Q`, or `Esc` to safely quit.*
