# Building atari800 to WebAssembly

This fork adds `build-wasm.sh` — a one-command emscripten build that produces
a browser-runnable `atari800.js` + `atari800.wasm` (plus an emcc default shell
`atari800.html` for quick testing).

## Quick start

```sh
git clone https://github.com/Retro-Jack/atari800.git
cd atari800
./build-wasm.sh
```

Output lands in `src/`:

| File | Size | Purpose |
|------|------|---------|
| `atari800.wasm` | ~1.7 MB | Emulator core |
| `atari800.js`   | ~186 KB | emcc loader |
| `atari800.html` | ~20 KB  | Default emcc shell (canvas + console panel) — replace with your own page for production |

Serve from any HTTP origin (the wasm + SDL2 audio init need `http://`, not `file://`):

```sh
python3 -m http.server 8765 --bind 127.0.0.1
xdg-open http://127.0.0.1:8765/src/atari800.html
```

You should see the **AltirraOS-XL** boot screen — atari800 falls back to it
when no real ROM is available, because `--enable-altirra_bios` bakes
Avery Lee's freely-redistributable replacement OS into the WASM.

## Prerequisites

| Tool | Notes |
|------|-------|
| `emsdk` | Install per [emscripten.org](https://emscripten.org/docs/getting_started/downloads.html). The script sources `/tmp/emsdk/emsdk_env.sh` by default — override with `EMSDK_ENV=/path/to/emsdk_env.sh ./build-wasm.sh`. |
| `autoconf`, `automake` | Needed for `./autogen.sh`. |
| `python3` (optional) | For serving the build locally. |

## What the script does

1. Sources your emsdk env so `emcc` / `emconfigure` / `emmake` are on `PATH`.
2. Writes a temporary `sdl2-config` stub. Emscripten's SDL2 port is enabled by
   `-sUSE_SDL=2` but ships no `sdl2-config`; atari800's autoconf macro insists
   on calling one, so the stub satisfies it without producing real flags.
3. Runs `./autogen.sh` if `configure` isn't already generated.
4. Runs `emconfigure ./configure` with the flags below, then `emmake make`.
5. Re-links the object files with browser-targeted emcc flags. The default
   `make` produces a Node-runnable script — we relink so the output works in
   a browser via `<script>`.

## Configure / link flags, briefly

| Flag | Why |
|------|-----|
| `--with-video=sdl2 --with-sound=sdl2` | Use the SDL2 build path; emscripten provides SDL2 via `-sUSE_SDL=2`. |
| `--without-opengl` | atari800's SDL+GL path tries `eglCreateContext` which fails in emscripten and leaves the canvas black. The software renderer works fine. |
| `--disable-netsio` | FujiNet network device needs `clock_gettime`; meaningless in the browser. |
| `--disable-riodevice / --disable-rserial / --disable-rnetwork` | Need host TTY / serial port; not portable to wasm. |
| `--disable-audiorecording / --disable-videorecording` | Strips codecs we don't need. |
| `--enable-altirra_bios` | Bakes in AltirraOS-XL 3.41 so the build works out-of-the-box with no copyrighted ROMs. |
| `-sUSE_SDL=2` | Pulls emscripten's SDL2 port (canvas + keyboard + WebAudio). |
| `-sASYNCIFY` | atari800's main loop in `sdl/main.c` is a `for(;;)` that would freeze the browser; ASYNCIFY suspends/resumes at `SDL_Delay` so the browser can paint. |
| `-sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=64MB` | Comfortable headroom. |

## Loading a game from JS

The build accepts the same positional/option args as native atari800. Pass them
via `Module.arguments` before the script tag runs, and use `Module.preRun` to
write the ROM into the in-WASM virtual FS:

```js
window.Module = {
  canvas: document.getElementById('canvas'),
  arguments: ['/game.atr'],                       // disk image
  // arguments: ['-cart-type', '1', '-cart', '/game.rom'],  // 8K cart
  preRun: [function () {
    Module.FS.createPreloadedFile('/', 'game.atr', 'roms/mule.atr', true, false);
  }],
};
```

Then inject `atari800.js`. The wasm reads the args when `callMain` runs (after
`preRun` finishes), so the ROM will already be in the FS.

## Why this fork exists

Built to integrate Atari 800XL into [GenX-DOS](https://github.com/Retro-Jack/GenX-DOS)
(a browser DOS prompt that boots emulators from numbered menus). Three
off-the-shelf options were ruled out first:

- **jsA8E** — no LICENSE in [AnimaInCorpore/A8E](https://github.com/AnimaInCorpore/A8E), so it can't legally be redistributed.
- **EmulatorJS** — ships an Atari 5200 core but no atari800 / 800XL core.
- **RetroArch web nightly** — atari800 is not in the ~90 cores in the official emscripten build.

So we build from source. This fork only adds `build-wasm.sh` and this file;
the upstream source is untouched.
