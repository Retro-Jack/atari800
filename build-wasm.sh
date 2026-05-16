#!/usr/bin/env bash
# Build atari800 to WebAssembly using emscripten.
# See BUILDING-WASM.md for the why.
set -euo pipefail

: "${EMSDK_ENV:=/tmp/emsdk/emsdk_env.sh}"
if [ ! -f "$EMSDK_ENV" ]; then
  echo "emsdk env script not found at: $EMSDK_ENV" >&2
  echo "Install emsdk first, or set EMSDK_ENV to its emsdk_env.sh path." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$EMSDK_ENV"

# emscripten's SDL2 port is enabled by -sUSE_SDL=2 but doesn't ship an
# sdl2-config script. Atari800's autoconf macro calls one — stub it.
SDL2_CONFIG_STUB="$(mktemp)"
trap 'rm -f "$SDL2_CONFIG_STUB"' EXIT
cat > "$SDL2_CONFIG_STUB" <<'EOF'
#!/bin/sh
case "$1" in
  --cflags|--cflags-only-I|--libs|--libs-only-l|--static-libs|--prefix) echo "" ;;
  --version) echo "2.30.0" ;;
esac
EOF
chmod +x "$SDL2_CONFIG_STUB"

[ -f configure ] || ./autogen.sh

SDL2_CONFIG="$SDL2_CONFIG_STUB" emconfigure ./configure \
  --target=default \
  --with-video=sdl2 --with-sound=sdl2 \
  --without-opengl \
  --disable-netsio \
  --disable-riodevice --disable-rserial --disable-rnetwork \
  --disable-audiorecording --disable-videorecording \
  --enable-altirra_bios \
  CFLAGS="-O2 -sUSE_SDL=2" LIBS="-sUSE_SDL=2"

emmake make -j"$(nproc)"

# `make` produces a Node-style executable. Relink for the browser.
pushd src >/dev/null
OBJS=$(ls atari800-*.o sdl/atari800-*.o roms/atari800-*.o \
          codecs/atari800-*.o atari_ntsc/atari800-*.o 2>/dev/null \
       | grep -v video_gl)
emcc -O2 -sUSE_SDL=2 -sASYNCIFY -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=64MB \
     -sEXPORTED_RUNTIME_METHODS=ccall,cwrap,FS -sEXIT_RUNTIME=0 \
     -o atari800.html $OBJS -lm
popd >/dev/null

echo
echo "Built:"
ls -lh src/atari800.{js,wasm}
echo
echo "Try it:  python3 -m http.server 8765 --bind 127.0.0.1"
echo "         http://127.0.0.1:8765/src/atari800.html"
