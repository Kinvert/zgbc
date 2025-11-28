# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

zgbc is a minimal, high-performance Game Boy (DMG) emulator core written in Zig 0.16. Designed for headless execution (reinforcement learning, fuzzing, automated testing) rather than pixel-perfect graphics or audio.

**Goals:** 5M+ frames/sec single-threaded, RAM-based observations, <1500 lines total
**Non-Goals:** PPU rendering, audio, link cable, GBC extended features, debugger UI

## Build Commands

```bash
zig build              # Build the executable (output: zig-out/bin/zgbc)
zig build run          # Build and run
zig build run -- args  # Build and run with arguments
zig build test         # Run unit tests (both module and executable tests)
zig build test-blargg  # Run Blargg CPU instruction test ROMs
zig build test --fuzz  # Run tests with fuzzing enabled
```

## Architecture

The codebase follows a split module pattern:
- `src/root.zig` - Library module (exposed as "zgbc" to consumers)
- `src/main.zig` - CLI executable that imports the zgbc module

### Planned Structure (from SPEC.md)

```
src/
├── main.zig      # CLI / test harness
├── gb.zig        # Top-level Game Boy state
├── cpu.zig       # LR35902 CPU (SM83 core, NOT Z80)
├── mmu.zig       # Memory management unit
├── mbc.zig       # Memory bank controllers (MBC1, MBC3)
├── timer.zig     # Timer / DIV
└── opcodes.zig   # Instruction implementations
```

## Zig 0.16 Specifics

This project requires Zig 0.16+. Key syntax differences from older Zig:

- **I/O requires explicit buffers:** `var buf: [1024]u8 = undefined; var writer = file.writer(&buf);`
- **Cast builtins are single-argument:** Use `@as(T, @intCast(val))` not `@intCast(T, val)`
- **ArrayList is unmanaged by default:** Pass allocator to each operation: `list.append(allocator, item)`
- **Build system uses root_module:** See build.zig for the modern pattern
- **No usingnamespace:** Use explicit declarations or conditionals

See `zig-0.16-llm-context.md` for comprehensive Zig 0.16 migration details.

## Hardware Reference

The LR35902 CPU is a Sharp SM83 core, commonly misdescribed as "Z80-like" but significantly different:
- No IX/IY index registers, no alternate register set, no I/O port instructions
- 256 base opcodes + 256 CB-prefixed opcodes
- All timings in T-cycles (4 T = 1 M-cycle)

Memory map regions VRAM (0x8000-0x9FFF) and OAM (0xFE00-0xFE9F) are not emulated but must handle reads/writes without crashing.

See `SPEC.md` for complete hardware documentation including instruction encoding patterns, timer frequencies, interrupt vectors, and MBC specifications.
