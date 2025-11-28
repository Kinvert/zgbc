# zgbc

High-performance Game Boy emulator in pure Zig. Full graphics, audio, and a 137KB WASM build for browsers.

## Performance

Pokemon Red benchmark (AMD Ryzen 9):

```
Single-thread performance:
  Full (PPU+APU):     4,601 FPS (77x realtime)
  Headless:          22,354 FPS (372x realtime)

Headless multi-threaded scaling:
Threads |    FPS    | Per-thread |  Scaling
--------|-----------|------------|----------
      1 |    22,930 |     22,930 |    1.03x
      2 |    44,926 |     22,463 |    2.01x
      4 |    84,007 |     21,002 |    3.76x
      8 |   150,032 |     18,754 |    6.71x
     16 |   188,180 |     11,761 |    8.42x
     32 |   256,691 |      8,022 |   11.48x
```

**256,691 FPS headless** at 32 threads — 4,278x realtime.

## Features

- **Full PPU** — Background, window, sprites, all 4 colors
- **Full APU** — 2 pulse channels, wave channel, noise channel
- **WASM build** — 137KB, runs in browser at 60 FPS with audio
- **Headless mode** — Disable rendering for 5x speedup in training
- **All Blargg CPU tests pass** — Correct LR35902 implementation
- **MBC1/MBC3 support** — Pokemon Red/Blue/Yellow compatible
- **Zero dependencies** — Pure Zig, no libc required
- **~3,000 lines** — Auditable, hackable

## Building

```bash
# Native build
zig build -Doptimize=ReleaseFast

# WASM build (outputs to zig-out/bin/zgbc.wasm)
zig build wasm

# Run tests
zig build test
zig build test-blargg

# Run benchmark
zig build bench
```

## Usage

### Native (Zig)

```zig
const zgbc = @import("zgbc");

var gb = zgbc.GB{};
try gb.loadRom(rom_data);
gb.skipBootRom();

// Headless mode for training (5x faster)
gb.render_graphics = false;
gb.render_audio = false;

// Run one frame (~70224 cycles)
gb.frame();

// Set joypad input
gb.mmu.joypad_state = ~@as(u8, 0x09); // A + Start

// Read RAM for observations
const player_x = gb.mmu.read(0xD362);

// Get frame buffer (160x144, 2-bit color indices)
const pixels = gb.getFrameBuffer();

// Get audio samples (stereo i16, 44100 Hz)
var audio: [2048]i16 = undefined;
const count = gb.getAudioSamples(&audio);
```

### WASM (Browser)

```javascript
const { instance } = await WebAssembly.instantiate(wasmBytes, {});
const wasm = instance.exports;

wasm.init();

// Load ROM
const romPtr = wasm.getRomBuffer();
new Uint8Array(wasm.memory.buffer).set(romData, romPtr);
wasm.loadRom(romData.length);

// Headless mode (optional)
wasm.setRenderGraphics(false);
wasm.setRenderAudio(false);

// Game loop
function frame() {
    wasm.setInput(buttonState);  // bits: A,B,Sel,Start,R,L,U,D
    wasm.frame();

    // Get pixels (160x144 RGBA)
    const framePtr = wasm.getFrame();
    const pixels = new Uint32Array(wasm.memory.buffer, framePtr, 160*144);

    // Get audio
    const audioCount = wasm.getAudioSamples();
    const audioPtr = wasm.getAudioBuffer();
    const samples = new Int16Array(wasm.memory.buffer, audioPtr, audioCount);
}
```

See `web/index.html` for a complete browser demo.

## Web Demo

```bash
zig build wasm
cd web
python -m http.server 8000
# Open http://localhost:8000
```

Controls: Arrow keys (D-pad), Z (A), X (B), Enter (Start), Shift (Select)

## Tests

All 12 Blargg CPU instruction tests pass:

```
01-special         PASS    07-jr,jp,call,ret  PASS
02-interrupts      PASS    08-misc instrs     PASS
03-op sp,hl        PASS    09-op r,r          PASS
04-op r,imm        PASS    10-bit ops         PASS
05-op rp           PASS    11-op a,(hl)       PASS
06-ld r,r          PASS    cpu_instrs         PASS
```

## Architecture

```
src/
├── cpu.zig       # LR35902 CPU, comptime opcode tables
├── mmu.zig       # Memory mapping, I/O registers
├── mbc.zig       # MBC1/MBC3 cartridge banking
├── timer.zig     # DIV/TIMA timer
├── ppu.zig       # Pixel Processing Unit, scanline renderer
├── apu.zig       # Audio Processing Unit, 4 channels
├── gb.zig        # Top-level Game Boy state
├── wasm.zig      # WASM bindings
├── bench.zig     # Performance benchmark
└── root.zig      # Public API

web/
├── index.html    # Browser demo
└── zgbc.wasm     # 137KB WASM binary
```

## Pokemon Red RAM Map

| Address | Description |
|---------|-------------|
| 0xD356  | Badges      |
| 0xD359  | Game state  |
| 0xD35E  | Map ID      |
| 0xD361  | Player Y    |
| 0xD362  | Player X    |
| 0xD16B  | Party count |

Full map: [pokered RAM](https://datacrystal.romhacking.net/wiki/Pok%C3%A9mon_Red/Blue:RAM_map)

## License

MIT
