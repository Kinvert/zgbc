# zgbc

Pure Zig Game Boy emulator core. Built for speed.

## Performance

Pokemon Red benchmark (Intel i9-13980HX):

```
Threads |    FPS    | Per-thread |  Scaling
--------|-----------|------------|----------
      1 |     26989 |      26989 |    1.00x
      2 |     53010 |      26505 |    1.96x
      4 |     99335 |      24834 |    3.68x
      8 |    154173 |      19272 |    5.71x
     16 |    227343 |      14209 |    8.42x
     32 |    324293 |      10134 |   12.01x
```

**324,293 FPS** — 5,405x realtime.

Single-threaded: **450x realtime** (26,989 FPS vs 60 FPS native).

## Features

- **All Blargg CPU tests pass** — Correct LR35902 implementation
- **MBC1/MBC3 support** — Pokemon Red/Blue/Yellow compatible
- **Headless by design** — No PPU rendering, no audio, maximum throughput
- **RAM observations** — Direct memory access for RL agents
- **Zero dependencies** — Pure Zig, no libc required
- **~1,600 lines** — Auditable, hackable

## Use Cases

- Reinforcement learning environments
- Automated testing / fuzzing
- ROM analysis
- High-speed batch processing

Not intended for playing games (no graphics/audio).

## Building

```bash
zig build -Doptimize=ReleaseFast

# Run tests
zig build test

# Run Blargg CPU tests
zig build test-blargg

# Run benchmark
zig build bench
```

## Usage

```zig
const zgbc = @import("zgbc");

var gb = zgbc.GB{};
try gb.loadRom(rom_data);
gb.skipBootRom();

// Run one frame (~70224 cycles)
gb.frame();

// Set joypad input (directly set state, active low)
gb.mmu.joypad_state = ~@as(u8, 0x09); // A + Start

// Read RAM for observations
const player_x = gb.mmu.read(0xD362);
const player_y = gb.mmu.read(0xD361);
const badges = gb.mmu.read(0xD356);
```

## Pokemon Red RAM Map

| Address | Description |
|---------|-------------|
| 0xD356 | Badges |
| 0xD359 | Game state |
| 0xD35E | Map ID |
| 0xD361 | Player Y |
| 0xD362 | Player X |
| 0xD16B | Party count |

Full map: [pokered RAM](https://datacrystal.romhacking.net/wiki/Pok%C3%A9mon_Red/Blue:RAM_map)

## Tests

All Blargg CPU instruction tests pass:

```
01-special         PASS
02-interrupts      PASS
03-op sp,hl        PASS
04-op r,imm        PASS
05-op rp           PASS
06-ld r,r          PASS
07-jr,jp,call,ret  PASS
08-misc instrs     PASS
09-op r,r          PASS
10-bit ops         PASS
11-op a,(hl)       PASS
cpu_instrs         PASS
```

## Architecture

```
src/
├── cpu.zig    # LR35902 CPU, comptime opcode tables
├── mmu.zig    # Memory mapping, I/O registers
├── mbc.zig    # MBC1/MBC3 cartridge banking
├── timer.zig  # DIV/TIMA timer
├── gb.zig     # Top-level Game Boy state
└── root.zig   # Public API
```

## License

MIT
