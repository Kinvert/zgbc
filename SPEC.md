```markdown
# zgbc - Zig Game Boy Emulator Core

## Overview

zgbc is a minimal, high-performance Game Boy emulator core written in Zig. It is designed for headless execution—reinforcement learning, fuzzing, automated testing—where pixel-perfect graphics and audio are not required.

**Goals:**
- Maximum simulation throughput (target: 5M+ frames/sec single-threaded)
- RAM-based observations (no PPU rendering)
- Correctness for game logic (timers, interrupts, memory banking)
- Clean, auditable Zig code (<1500 lines total)

**Non-Goals:**
- Pixel-perfect PPU emulation
- Audio emulation
- Link cable / serial
- Game Boy Color extended features (initially)
- Debugger UI

---

## Target Hardware: DMG (Game Boy)

### LR35902 CPU

The LR35902 is a Sharp SM83 core, often misdescribed as "Z80-like." It is **not** a Z80. Key differences from Z80:
- No IX/IY index registers
- No alternate register set
- No I/O port instructions
- Different flag behavior on some ops
- Unique STOP and SWAP instructions

#### Registers

```
8-bit:  A, F, B, C, D, E, H, L
16-bit: AF, BC, DE, HL, SP, PC

F (flags): Z N H C - - - -
           │ │ │ └── Carry
           │ │ └──── Half-carry (BCD)
           │ └────── Subtract (BCD)
           └──────── Zero
```

Lower 4 bits of F are always 0.

#### Instruction Set

- 256 base opcodes
- 256 CB-prefixed opcodes (bit operations)
- ~500 total instruction variants

Instruction encoding is semi-regular:

```
Bits:    7 6 | 5 4 3 | 2 1 0
         x   |   y   |   z

x=0: Misc, loads, relative jumps, 16-bit ops
x=1: LD r, r' (64 combinations, HALT at 0x76)
x=2: ALU A, r (8 ops × 8 registers)
x=3: Misc, returns, jumps, calls, RST, CB prefix
```

CB-prefixed instructions:
```
Bits:    7 6 | 5 4 3 | 2 1 0
         x   |   y   |   z

x=0: Rotate/shift (RLC, RRC, RL, RR, SLA, SRA, SWAP, SRL)
x=1: BIT y, r
x=2: RES y, r  
x=3: SET y, r
```

#### Timing

All timings in T-cycles (4 T-cycles = 1 M-cycle):

| Category | Cycles |
|----------|--------|
| Most 8-bit ops | 4 |
| 16-bit arithmetic | 8 |
| Memory read/write | 4 per access |
| Conditional branch (taken) | +4 |
| CB-prefix | +4 |

---

### Memory Map

```
0000-3FFF: ROM Bank 0 (16KB, fixed)
4000-7FFF: ROM Bank 1-N (16KB, switchable)
8000-9FFF: VRAM (8KB) - NOT EMULATED
A000-BFFF: External RAM (8KB, switchable)
C000-CFFF: WRAM Bank 0 (4KB)
D000-DFFF: WRAM Bank 1 (4KB)
E000-FDFF: Echo RAM (mirror of C000-DDFF)
FE00-FE9F: OAM (160B) - NOT EMULATED
FEA0-FEFF: Unusable
FF00-FF7F: I/O Registers
FF80-FFFE: HRAM (127B)
FFFF:      IE (Interrupt Enable)
```

#### I/O Registers (Relevant Subset)

| Addr | Name | Purpose |
|------|------|---------|
| FF00 | P1/JOYP | Joypad input |
| FF04 | DIV | Divider (increments at 16384 Hz) |
| FF05 | TIMA | Timer counter |
| FF06 | TMA | Timer modulo (reload value) |
| FF07 | TAC | Timer control |
| FF0F | IF | Interrupt flags |
| FFFF | IE | Interrupt enable |

Registers FF40-FF4B (LCD) are **not emulated** but reads/writes must not crash.

---

### Memory Bank Controllers

Pokemon Red/Blue use MBC3. Support MBC1 and MBC3 initially.

#### MBC1

- Up to 2MB ROM (128 banks)
- Up to 32KB RAM (4 banks)
- Bank 0 always at 0000-3FFF
- Banking modes: 16Mbit ROM / 8KB RAM or 4Mbit ROM / 32KB RAM

#### MBC3

- Up to 2MB ROM (128 banks)  
- Up to 32KB RAM (4 banks)
- Real-Time Clock (RTC) - can stub for training
- Same banking as MBC1 but simpler mode handling

---

### Timer

The timer system increments TIMA at a rate determined by TAC:

| TAC & 0x03 | Frequency | Cycles per increment |
|------------|-----------|---------------------|
| 0 | 4096 Hz | 1024 |
| 1 | 262144 Hz | 16 |
| 2 | 65536 Hz | 64 |
| 3 | 16384 Hz | 256 |

When TIMA overflows:
1. TIMA reloads from TMA
2. IF bit 2 is set (timer interrupt)

DIV increments every 256 cycles regardless of TAC.

---

### Interrupts

| Bit | Vector | Source |
|-----|--------|--------|
| 0 | 0x0040 | VBlank |
| 1 | 0x0048 | LCD STAT |
| 2 | 0x0050 | Timer |
| 3 | 0x0058 | Serial |
| 4 | 0x0060 | Joypad |

Interrupt handling:
1. Check `IE & IF & 0x1F`
2. If any set and IME=1:
   - Disable IME
   - Push PC to stack
   - Jump to vector of highest-priority (lowest bit) interrupt
   - Clear corresponding IF bit
3. Takes 20 cycles

HALT behavior:
- If IME=1: Wait for interrupt, then service it
- If IME=0 and IE&IF=0: Wait for interrupt, don't service
- If IME=0 and IE&IF≠0: HALT bug (PC not incremented on next instruction)

---

### Joypad (FF00)

```
Bit 5: Select action buttons (active low)
Bit 4: Select direction buttons (active low)
Bits 3-0: Input (active low)

When bit 5 low: 3=Start, 2=Select, 1=B, 0=A
When bit 4 low: 3=Down, 2=Up, 1=Left, 0=Right
```

For RL: Accept 8-bit action input, map to button state.

---

## Architecture

### Project Structure

```
zgbc/
├── src/
│   ├── main.zig          # CLI / test harness
│   ├── gb.zig            # Top-level Game Boy state
│   ├── cpu.zig           # LR35902 CPU
│   ├── mmu.zig           # Memory management unit
│   ├── mbc.zig           # Memory bank controllers
│   ├── timer.zig         # Timer / DIV
│   └── opcodes.zig       # Instruction implementations
├── test/
│   ├── blargg/           # Blargg test ROMs
│   └── cpu_test.zig      # Unit tests
└── build.zig
```

### Core Types

```zig
// src/gb.zig
pub const GB = struct {
    cpu: CPU,
    mmu: MMU,
    timer: Timer,
    
    cycles: u64,           // Total cycles elapsed
    
    pub fn step(self: *GB) u8;           // Execute one instruction, return cycles
    pub fn frame(self: *GB) void;        // Execute one frame (~70224 cycles)
    pub fn setInput(self: *GB, buttons: u8) void;
    pub fn getRam(self: *GB) []const u8; // For observations
    pub fn loadRom(self: *GB, rom: []const u8) !void;
};
```

```zig
// src/cpu.zig
pub const CPU = struct {
    // Registers
    a: u8,
    f: Flags,
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,
    sp: u16,
    pc: u16,
    
    // State
    ime: bool,             // Interrupt master enable
    halted: bool,
    halt_bug: bool,
    ime_scheduled: bool,   // EI enables IME after next instruction
    
    pub fn step(self: *CPU, mmu: *MMU) u8;
};

pub const Flags = packed struct(u8) {
    _: u4 = 0,
    c: bool = false,       // Carry
    h: bool = false,       // Half-carry
    n: bool = false,       // Subtract
    z: bool = false,       // Zero
};
```

```zig
// src/mmu.zig
pub const MMU = struct {
    rom: []const u8,
    wram: [8192]u8,        // C000-DFFF
    hram: [127]u8,         // FF80-FFFE
    eram: [32768]u8,       // External RAM (max 32KB)
    
    ie: u8,                // FFFF
    if_: u8,               // FF0F
    joypad: u8,            // FF00
    joypad_state: u8,      // Current button state
    
    mbc: MBC,
    
    pub fn read(self: *MMU, addr: u16) u8;
    pub fn write(self: *MMU, addr: u16, val: u8) void;
};
```

```zig
// src/mbc.zig
pub const MBC = union(enum) {
    none: void,
    mbc1: MBC1,
    mbc3: MBC3,
    
    pub fn read(self: *MBC, rom: []const u8, eram: []u8, addr: u16) u8;
    pub fn write(self: *MBC, eram: []u8, addr: u16, val: u8) void;
};

pub const MBC1 = struct {
    rom_bank: u8,
    ram_bank: u8,
    ram_enabled: bool,
    mode: bool,
};

pub const MBC3 = struct {
    rom_bank: u8,
    ram_bank: u8,
    ram_enabled: bool,
    // RTC registers (can stub)
};
```

```zig
// src/timer.zig
pub const Timer = struct {
    div: u16,              // Internal 16-bit counter (upper 8 bits = DIV register)
    tima: u8,
    tma: u8,
    tac: u8,
    
    pub fn tick(self: *Timer, cycles: u8, if_: *u8) void;
};
```

---

## Implementation Notes

### Comptime Opcode Table

Use comptime to generate the opcode dispatch table:

```zig
const Handler = *const fn (*CPU, *MMU) u8;

const opcodes: [256]Handler = comptime init: {
    var table: [256]Handler = @splat(&undefined_opcode);
    
    table[0x00] = &nop;
    table[0x01] = &ld_bc_d16;
    // ...
    
    // Use patterns for regular encodings
    for (0..8) |d| {
        for (0..8) |s| {
            if (d == 6 and s == 6) {
                table[0x40 + d * 8 + s] = &halt;
            } else {
                table[0x40 + d * 8 + s] = genLdRR(d, s);
            }
        }
    }
    
    break :init table;
};

const cb_opcodes: [256]Handler = comptime init: {
    // Similar for CB-prefixed
};
```

### Register Accessors

Use comptime to generate register accessors from 3-bit indices:

```zig
fn getReg(cpu: *CPU, mmu: *MMU, comptime idx: u3) u8 {
    return switch (idx) {
        0 => cpu.b,
        1 => cpu.c,
        2 => cpu.d,
        3 => cpu.e,
        4 => cpu.h,
        5 => cpu.l,
        6 => mmu.read(cpu.getHL()),  // (HL)
        7 => cpu.a,
    };
}

fn setReg(cpu: *CPU, mmu: *MMU, comptime idx: u3, val: u8) void {
    switch (idx) {
        0 => cpu.b = val,
        1 => cpu.c = val,
        2 => cpu.d = val,
        3 => cpu.e = val,
        4 => cpu.h = val,
        5 => cpu.l = val,
        6 => mmu.write(cpu.getHL(), val),
        7 => cpu.a = val,
    }
}
```

### Instruction Pattern Generation

Many instructions follow patterns. Generate them:

```zig
fn genLdRR(comptime d: u3, comptime s: u3) Handler {
    return struct {
        fn handler(cpu: *CPU, mmu: *MMU) u8 {
            const val = getReg(cpu, mmu, s);
            setReg(cpu, mmu, d, val);
            return if (d == 6 or s == 6) 8 else 4;
        }
    }.handler;
}

fn genAluA(comptime op: u3, comptime src: u3) Handler {
    return struct {
        fn handler(cpu: *CPU, mmu: *MMU) u8 {
            const val = getReg(cpu, mmu, src);
            switch (op) {
                0 => cpu.add(val),
                1 => cpu.adc(val),
                2 => cpu.sub(val),
                3 => cpu.sbc(val),
                4 => cpu.and_(val),
                5 => cpu.xor(val),
                6 => cpu.or_(val),
                7 => cpu.cp(val),
            }
            return if (src == 6) 8 else 4;
        }
    }.handler;
}
```

---

## Validation

### Blargg Test ROMs

Minimum required passes for correctness:

1. `cpu_instrs.gb` - All CPU instructions
2. `instr_timing.gb` - Instruction cycle counts  
3. `mem_timing.gb` - Memory access timing
4. `halt_bug.gb` - HALT instruction edge case

Download: https://github.com/retrio/gb-test-roms

### Test Harness

```zig
test "blargg cpu_instrs" {
    var gb = try GB.init();
    try gb.loadRom(@embedFile("test/blargg/cpu_instrs.gb"));
    
    // Run until serial output contains "Passed" or "Failed"
    var output: [1024]u8 = undefined;
    var len: usize = 0;
    
    while (len < 1024) {
        gb.frame();
        
        // Check serial output (0xFF01)
        if (gb.mmu.serial_pending) {
            output[len] = gb.mmu.serial_data;
            len += 1;
            gb.mmu.serial_pending = false;
            
            if (std.mem.indexOf(u8, output[0..len], "Passed")) |_| break;
            if (std.mem.indexOf(u8, output[0..len], "Failed")) |_| {
                return error.TestFailed;
            }
        }
    }
}
```

---

## API

### C ABI Export

```zig
// For FFI integration
export fn zgbc_create() ?*GB {
    return allocator.create(GB) catch null;
}

export fn zgbc_destroy(gb: *GB) void {
    allocator.destroy(gb);
}

export fn zgbc_load_rom(gb: *GB, data: [*]const u8, len: usize) bool {
    gb.loadRom(data[0..len]) catch return false;
    return true;
}

export fn zgbc_step(gb: *GB) u8 {
    return gb.step();
}

export fn zgbc_frame(gb: *GB) void {
    gb.frame();
}

export fn zgbc_set_input(gb: *GB, buttons: u8) void {
    gb.setInput(buttons);
}

export fn zgbc_get_ram(gb: *GB) [*]const u8 {
    return gb.getRam().ptr;
}

export fn zgbc_get_ram_size(gb: *GB) usize {
    return gb.getRam().len;
}
```

### Button Mapping

```zig
pub const Buttons = packed struct(u8) {
    a: bool,
    b: bool,
    select: bool,
    start: bool,
    right: bool,
    left: bool,
    up: bool,
    down: bool,
};
```

---

## Performance Targets

| Metric | Target |
|--------|--------|
| Single instance | >5M frames/sec |
| Blargg cpu_instrs | Pass |
| Blargg instr_timing | Pass |
| Pokemon Red boot | <100ms |
| Memory footprint | <64KB per instance |

---

## References

- [Pan Docs](https://gbdev.io/pandocs/) - Canonical Game Boy documentation
- [RGBDS CPU Reference](https://rgbds.gbdev.io/docs/gbz80.7) - Instruction details
- [Blargg Test ROMs](https://github.com/retrio/gb-test-roms)
- [Mooneye Test Suite](https://github.com/Gekkio/mooneye-test-suite) - Stricter tests
- [Game Boy CPU Manual](http://marc.rawer.de/Gameboy/Docs/GBCPUman.pdf)

---

## Milestones

1. **M1: CPU Core** - All opcodes implemented, Blargg cpu_instrs passes
2. **M2: Timing** - Blargg instr_timing passes
3. **M3: Timer + Interrupts** - Timer interrupt works, HALT correct
4. **M4: MBC3** - Pokemon Red boots to title screen
5. **M5: Optimization** - Hit 5M frames/sec target
6. **M6: API** - C ABI exports, clean Zig interface
```
