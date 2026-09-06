#!/bin/bash
# Builds the jack-transcribe-stream helper (transcribe.cpp + our stdin-PCM
# shim) and installs it to ~/Library/Application Support/Jack/bin/ where
# TranscribeCppStreamingEngine looks for it.
#
# The transcribe.cpp clone and all build artifacts stay out of git
# (see .gitignore); only Vendor/jack-transcribe-stream/main.c is tracked.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
TCPP="$VENDOR/transcribe.cpp"
SHIM_DIR="$VENDOR/jack-transcribe-stream"
INSTALL_DIR="$HOME/Library/Application Support/Jack/bin"

if [ ! -d "$TCPP" ]; then
  git clone --depth 1 https://github.com/handy-computer/transcribe.cpp "$TCPP"
fi

cmake -S "$TCPP" -B "$TCPP/build" -DCMAKE_BUILD_TYPE=Release \
  -DTRANSCRIBE_BUILD_TESTS=OFF -DTRANSCRIBE_BUILD_EXAMPLES=ON
cmake --build "$TCPP/build" -j8

cc -O2 -arch arm64 -I "$TCPP/include" "$SHIM_DIR/main.c" -o "$SHIM_DIR/jack-transcribe-stream" \
  "$TCPP/build/src/libtranscribe.a" \
  "$TCPP/build/ggml/src/libggml.a" \
  "$TCPP/build/ggml/src/libggml-cpu.a" \
  "$TCPP/build/ggml/src/ggml-metal/libggml-metal.a" \
  "$TCPP/build/ggml/src/libggml-base.a" \
  -lm -lc++ -framework Foundation -framework Metal -framework MetalKit -framework Accelerate

mkdir -p "$INSTALL_DIR"
cp "$SHIM_DIR/jack-transcribe-stream" "$INSTALL_DIR/"
echo "Installed $INSTALL_DIR/jack-transcribe-stream"
