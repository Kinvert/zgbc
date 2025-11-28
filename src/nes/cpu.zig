//! MOS 6502 CPU (Ricoh 2A03 variant)
//! The NES CPU is a 6502 without decimal mode.

const std = @import("std");
const MMU = @import("mmu.zig").MMU;

pub const CPU = struct {
    // Registers
    a: u8 = 0,
    x: u8 = 0,
    y: u8 = 0,
    sp: u8 = 0xFD,
    pc: u16 = 0,

    // Status register (NV_BDIZC)
    status: Status = .{},

    // Interrupt state
    nmi_pending: bool = false,
    irq_pending: bool = false,

    // Cycle tracking
    cycles: u64 = 0,
    stall: u16 = 0, // Cycles to stall (for DMA)

    pub const Status = packed struct(u8) {
        c: bool = false, // Carry
        z: bool = false, // Zero
        i: bool = true, // Interrupt disable
        d: bool = false, // Decimal (ignored on NES)
        b: bool = false, // Break
        _: bool = true, // Unused (always 1)
        v: bool = false, // Overflow
        n: bool = false, // Negative
    };

    // Addressing modes
    const Mode = enum {
        imp, // Implied
        acc, // Accumulator
        imm, // Immediate
        zp, // Zero Page
        zpx, // Zero Page,X
        zpy, // Zero Page,Y
        abs, // Absolute
        abx, // Absolute,X
        aby, // Absolute,Y
        ind, // Indirect (JMP only)
        izx, // Indexed Indirect (X)
        izy, // Indirect Indexed (Y)
        rel, // Relative (branches)
    };

    // Mnemonics
    const Mnem = enum {
        // Load/Store
        lda,
        ldx,
        ldy,
        sta,
        stx,
        sty,
        // Transfer
        tax,
        tay,
        txa,
        tya,
        tsx,
        txs,
        // Stack
        pha,
        php,
        pla,
        plp,
        // Arithmetic
        adc,
        sbc,
        // Compare
        cmp,
        cpx,
        cpy,
        // Increment/Decrement
        inc,
        inx,
        iny,
        dec,
        dex,
        dey,
        // Shift
        asl,
        lsr,
        rol,
        ror,
        // Logic
        @"and",
        eor,
        ora,
        bit,
        // Branch
        bcc,
        bcs,
        beq,
        bmi,
        bne,
        bpl,
        bvc,
        bvs,
        // Jump
        jmp,
        jsr,
        rts,
        rti,
        // Flags
        clc,
        cld,
        cli,
        clv,
        sec,
        sed,
        sei,
        // System
        brk,
        nop,
        // Illegal (commonly used)
        lax,
        sax,
        dcp,
        isb,
        slo,
        rla,
        sre,
        rra,
        xxx, // Invalid/undefined
    };

    const Opcode = struct {
        mnem: Mnem,
        mode: Mode,
        cycles: u8,
        page_cross: bool = false, // +1 cycle on page cross
    };

    // Full 6502 opcode table
    const opcodes: [256]Opcode = init: {
        var table: [256]Opcode = [_]Opcode{.{ .mnem = .xxx, .mode = .imp, .cycles = 2 }} ** 256;

        // LDA
        table[0xA9] = .{ .mnem = .lda, .mode = .imm, .cycles = 2 };
        table[0xA5] = .{ .mnem = .lda, .mode = .zp, .cycles = 3 };
        table[0xB5] = .{ .mnem = .lda, .mode = .zpx, .cycles = 4 };
        table[0xAD] = .{ .mnem = .lda, .mode = .abs, .cycles = 4 };
        table[0xBD] = .{ .mnem = .lda, .mode = .abx, .cycles = 4, .page_cross = true };
        table[0xB9] = .{ .mnem = .lda, .mode = .aby, .cycles = 4, .page_cross = true };
        table[0xA1] = .{ .mnem = .lda, .mode = .izx, .cycles = 6 };
        table[0xB1] = .{ .mnem = .lda, .mode = .izy, .cycles = 5, .page_cross = true };

        // LDX
        table[0xA2] = .{ .mnem = .ldx, .mode = .imm, .cycles = 2 };
        table[0xA6] = .{ .mnem = .ldx, .mode = .zp, .cycles = 3 };
        table[0xB6] = .{ .mnem = .ldx, .mode = .zpy, .cycles = 4 };
        table[0xAE] = .{ .mnem = .ldx, .mode = .abs, .cycles = 4 };
        table[0xBE] = .{ .mnem = .ldx, .mode = .aby, .cycles = 4, .page_cross = true };

        // LDY
        table[0xA0] = .{ .mnem = .ldy, .mode = .imm, .cycles = 2 };
        table[0xA4] = .{ .mnem = .ldy, .mode = .zp, .cycles = 3 };
        table[0xB4] = .{ .mnem = .ldy, .mode = .zpx, .cycles = 4 };
        table[0xAC] = .{ .mnem = .ldy, .mode = .abs, .cycles = 4 };
        table[0xBC] = .{ .mnem = .ldy, .mode = .abx, .cycles = 4, .page_cross = true };

        // STA
        table[0x85] = .{ .mnem = .sta, .mode = .zp, .cycles = 3 };
        table[0x95] = .{ .mnem = .sta, .mode = .zpx, .cycles = 4 };
        table[0x8D] = .{ .mnem = .sta, .mode = .abs, .cycles = 4 };
        table[0x9D] = .{ .mnem = .sta, .mode = .abx, .cycles = 5 };
        table[0x99] = .{ .mnem = .sta, .mode = .aby, .cycles = 5 };
        table[0x81] = .{ .mnem = .sta, .mode = .izx, .cycles = 6 };
        table[0x91] = .{ .mnem = .sta, .mode = .izy, .cycles = 6 };

        // STX
        table[0x86] = .{ .mnem = .stx, .mode = .zp, .cycles = 3 };
        table[0x96] = .{ .mnem = .stx, .mode = .zpy, .cycles = 4 };
        table[0x8E] = .{ .mnem = .stx, .mode = .abs, .cycles = 4 };

        // STY
        table[0x84] = .{ .mnem = .sty, .mode = .zp, .cycles = 3 };
        table[0x94] = .{ .mnem = .sty, .mode = .zpx, .cycles = 4 };
        table[0x8C] = .{ .mnem = .sty, .mode = .abs, .cycles = 4 };

        // Transfer
        table[0xAA] = .{ .mnem = .tax, .mode = .imp, .cycles = 2 };
        table[0xA8] = .{ .mnem = .tay, .mode = .imp, .cycles = 2 };
        table[0x8A] = .{ .mnem = .txa, .mode = .imp, .cycles = 2 };
        table[0x98] = .{ .mnem = .tya, .mode = .imp, .cycles = 2 };
        table[0xBA] = .{ .mnem = .tsx, .mode = .imp, .cycles = 2 };
        table[0x9A] = .{ .mnem = .txs, .mode = .imp, .cycles = 2 };

        // Stack
        table[0x48] = .{ .mnem = .pha, .mode = .imp, .cycles = 3 };
        table[0x08] = .{ .mnem = .php, .mode = .imp, .cycles = 3 };
        table[0x68] = .{ .mnem = .pla, .mode = .imp, .cycles = 4 };
        table[0x28] = .{ .mnem = .plp, .mode = .imp, .cycles = 4 };

        // ADC
        table[0x69] = .{ .mnem = .adc, .mode = .imm, .cycles = 2 };
        table[0x65] = .{ .mnem = .adc, .mode = .zp, .cycles = 3 };
        table[0x75] = .{ .mnem = .adc, .mode = .zpx, .cycles = 4 };
        table[0x6D] = .{ .mnem = .adc, .mode = .abs, .cycles = 4 };
        table[0x7D] = .{ .mnem = .adc, .mode = .abx, .cycles = 4, .page_cross = true };
        table[0x79] = .{ .mnem = .adc, .mode = .aby, .cycles = 4, .page_cross = true };
        table[0x61] = .{ .mnem = .adc, .mode = .izx, .cycles = 6 };
        table[0x71] = .{ .mnem = .adc, .mode = .izy, .cycles = 5, .page_cross = true };

        // SBC
        table[0xE9] = .{ .mnem = .sbc, .mode = .imm, .cycles = 2 };
        table[0xE5] = .{ .mnem = .sbc, .mode = .zp, .cycles = 3 };
        table[0xF5] = .{ .mnem = .sbc, .mode = .zpx, .cycles = 4 };
        table[0xED] = .{ .mnem = .sbc, .mode = .abs, .cycles = 4 };
        table[0xFD] = .{ .mnem = .sbc, .mode = .abx, .cycles = 4, .page_cross = true };
        table[0xF9] = .{ .mnem = .sbc, .mode = .aby, .cycles = 4, .page_cross = true };
        table[0xE1] = .{ .mnem = .sbc, .mode = .izx, .cycles = 6 };
        table[0xF1] = .{ .mnem = .sbc, .mode = .izy, .cycles = 5, .page_cross = true };

        // CMP
        table[0xC9] = .{ .mnem = .cmp, .mode = .imm, .cycles = 2 };
        table[0xC5] = .{ .mnem = .cmp, .mode = .zp, .cycles = 3 };
        table[0xD5] = .{ .mnem = .cmp, .mode = .zpx, .cycles = 4 };
        table[0xCD] = .{ .mnem = .cmp, .mode = .abs, .cycles = 4 };
        table[0xDD] = .{ .mnem = .cmp, .mode = .abx, .cycles = 4, .page_cross = true };
        table[0xD9] = .{ .mnem = .cmp, .mode = .aby, .cycles = 4, .page_cross = true };
        table[0xC1] = .{ .mnem = .cmp, .mode = .izx, .cycles = 6 };
        table[0xD1] = .{ .mnem = .cmp, .mode = .izy, .cycles = 5, .page_cross = true };

        // CPX
        table[0xE0] = .{ .mnem = .cpx, .mode = .imm, .cycles = 2 };
        table[0xE4] = .{ .mnem = .cpx, .mode = .zp, .cycles = 3 };
        table[0xEC] = .{ .mnem = .cpx, .mode = .abs, .cycles = 4 };

        // CPY
        table[0xC0] = .{ .mnem = .cpy, .mode = .imm, .cycles = 2 };
        table[0xC4] = .{ .mnem = .cpy, .mode = .zp, .cycles = 3 };
        table[0xCC] = .{ .mnem = .cpy, .mode = .abs, .cycles = 4 };

        // INC
        table[0xE6] = .{ .mnem = .inc, .mode = .zp, .cycles = 5 };
        table[0xF6] = .{ .mnem = .inc, .mode = .zpx, .cycles = 6 };
        table[0xEE] = .{ .mnem = .inc, .mode = .abs, .cycles = 6 };
        table[0xFE] = .{ .mnem = .inc, .mode = .abx, .cycles = 7 };

        // INX, INY
        table[0xE8] = .{ .mnem = .inx, .mode = .imp, .cycles = 2 };
        table[0xC8] = .{ .mnem = .iny, .mode = .imp, .cycles = 2 };

        // DEC
        table[0xC6] = .{ .mnem = .dec, .mode = .zp, .cycles = 5 };
        table[0xD6] = .{ .mnem = .dec, .mode = .zpx, .cycles = 6 };
        table[0xCE] = .{ .mnem = .dec, .mode = .abs, .cycles = 6 };
        table[0xDE] = .{ .mnem = .dec, .mode = .abx, .cycles = 7 };

        // DEX, DEY
        table[0xCA] = .{ .mnem = .dex, .mode = .imp, .cycles = 2 };
        table[0x88] = .{ .mnem = .dey, .mode = .imp, .cycles = 2 };

        // ASL
        table[0x0A] = .{ .mnem = .asl, .mode = .acc, .cycles = 2 };
        table[0x06] = .{ .mnem = .asl, .mode = .zp, .cycles = 5 };
        table[0x16] = .{ .mnem = .asl, .mode = .zpx, .cycles = 6 };
        table[0x0E] = .{ .mnem = .asl, .mode = .abs, .cycles = 6 };
        table[0x1E] = .{ .mnem = .asl, .mode = .abx, .cycles = 7 };

        // LSR
        table[0x4A] = .{ .mnem = .lsr, .mode = .acc, .cycles = 2 };
        table[0x46] = .{ .mnem = .lsr, .mode = .zp, .cycles = 5 };
        table[0x56] = .{ .mnem = .lsr, .mode = .zpx, .cycles = 6 };
        table[0x4E] = .{ .mnem = .lsr, .mode = .abs, .cycles = 6 };
        table[0x5E] = .{ .mnem = .lsr, .mode = .abx, .cycles = 7 };

        // ROL
        table[0x2A] = .{ .mnem = .rol, .mode = .acc, .cycles = 2 };
        table[0x26] = .{ .mnem = .rol, .mode = .zp, .cycles = 5 };
        table[0x36] = .{ .mnem = .rol, .mode = .zpx, .cycles = 6 };
        table[0x2E] = .{ .mnem = .rol, .mode = .abs, .cycles = 6 };
        table[0x3E] = .{ .mnem = .rol, .mode = .abx, .cycles = 7 };

        // ROR
        table[0x6A] = .{ .mnem = .ror, .mode = .acc, .cycles = 2 };
        table[0x66] = .{ .mnem = .ror, .mode = .zp, .cycles = 5 };
        table[0x76] = .{ .mnem = .ror, .mode = .zpx, .cycles = 6 };
        table[0x6E] = .{ .mnem = .ror, .mode = .abs, .cycles = 6 };
        table[0x7E] = .{ .mnem = .ror, .mode = .abx, .cycles = 7 };

        // AND
        table[0x29] = .{ .mnem = .@"and", .mode = .imm, .cycles = 2 };
        table[0x25] = .{ .mnem = .@"and", .mode = .zp, .cycles = 3 };
        table[0x35] = .{ .mnem = .@"and", .mode = .zpx, .cycles = 4 };
        table[0x2D] = .{ .mnem = .@"and", .mode = .abs, .cycles = 4 };
        table[0x3D] = .{ .mnem = .@"and", .mode = .abx, .cycles = 4, .page_cross = true };
        table[0x39] = .{ .mnem = .@"and", .mode = .aby, .cycles = 4, .page_cross = true };
        table[0x21] = .{ .mnem = .@"and", .mode = .izx, .cycles = 6 };
        table[0x31] = .{ .mnem = .@"and", .mode = .izy, .cycles = 5, .page_cross = true };

        // EOR
        table[0x49] = .{ .mnem = .eor, .mode = .imm, .cycles = 2 };
        table[0x45] = .{ .mnem = .eor, .mode = .zp, .cycles = 3 };
        table[0x55] = .{ .mnem = .eor, .mode = .zpx, .cycles = 4 };
        table[0x4D] = .{ .mnem = .eor, .mode = .abs, .cycles = 4 };
        table[0x5D] = .{ .mnem = .eor, .mode = .abx, .cycles = 4, .page_cross = true };
        table[0x59] = .{ .mnem = .eor, .mode = .aby, .cycles = 4, .page_cross = true };
        table[0x41] = .{ .mnem = .eor, .mode = .izx, .cycles = 6 };
        table[0x51] = .{ .mnem = .eor, .mode = .izy, .cycles = 5, .page_cross = true };

        // ORA
        table[0x09] = .{ .mnem = .ora, .mode = .imm, .cycles = 2 };
        table[0x05] = .{ .mnem = .ora, .mode = .zp, .cycles = 3 };
        table[0x15] = .{ .mnem = .ora, .mode = .zpx, .cycles = 4 };
        table[0x0D] = .{ .mnem = .ora, .mode = .abs, .cycles = 4 };
        table[0x1D] = .{ .mnem = .ora, .mode = .abx, .cycles = 4, .page_cross = true };
        table[0x19] = .{ .mnem = .ora, .mode = .aby, .cycles = 4, .page_cross = true };
        table[0x01] = .{ .mnem = .ora, .mode = .izx, .cycles = 6 };
        table[0x11] = .{ .mnem = .ora, .mode = .izy, .cycles = 5, .page_cross = true };

        // BIT
        table[0x24] = .{ .mnem = .bit, .mode = .zp, .cycles = 3 };
        table[0x2C] = .{ .mnem = .bit, .mode = .abs, .cycles = 4 };

        // Branches
        table[0x90] = .{ .mnem = .bcc, .mode = .rel, .cycles = 2 };
        table[0xB0] = .{ .mnem = .bcs, .mode = .rel, .cycles = 2 };
        table[0xF0] = .{ .mnem = .beq, .mode = .rel, .cycles = 2 };
        table[0x30] = .{ .mnem = .bmi, .mode = .rel, .cycles = 2 };
        table[0xD0] = .{ .mnem = .bne, .mode = .rel, .cycles = 2 };
        table[0x10] = .{ .mnem = .bpl, .mode = .rel, .cycles = 2 };
        table[0x50] = .{ .mnem = .bvc, .mode = .rel, .cycles = 2 };
        table[0x70] = .{ .mnem = .bvs, .mode = .rel, .cycles = 2 };

        // Jump
        table[0x4C] = .{ .mnem = .jmp, .mode = .abs, .cycles = 3 };
        table[0x6C] = .{ .mnem = .jmp, .mode = .ind, .cycles = 5 };
        table[0x20] = .{ .mnem = .jsr, .mode = .abs, .cycles = 6 };
        table[0x60] = .{ .mnem = .rts, .mode = .imp, .cycles = 6 };
        table[0x40] = .{ .mnem = .rti, .mode = .imp, .cycles = 6 };

        // Flags
        table[0x18] = .{ .mnem = .clc, .mode = .imp, .cycles = 2 };
        table[0xD8] = .{ .mnem = .cld, .mode = .imp, .cycles = 2 };
        table[0x58] = .{ .mnem = .cli, .mode = .imp, .cycles = 2 };
        table[0xB8] = .{ .mnem = .clv, .mode = .imp, .cycles = 2 };
        table[0x38] = .{ .mnem = .sec, .mode = .imp, .cycles = 2 };
        table[0xF8] = .{ .mnem = .sed, .mode = .imp, .cycles = 2 };
        table[0x78] = .{ .mnem = .sei, .mode = .imp, .cycles = 2 };

        // System
        table[0x00] = .{ .mnem = .brk, .mode = .imp, .cycles = 7 };
        table[0xEA] = .{ .mnem = .nop, .mode = .imp, .cycles = 2 };

        // Unofficial NOPs (various addressing modes)
        table[0x1A] = .{ .mnem = .nop, .mode = .imp, .cycles = 2 };
        table[0x3A] = .{ .mnem = .nop, .mode = .imp, .cycles = 2 };
        table[0x5A] = .{ .mnem = .nop, .mode = .imp, .cycles = 2 };
        table[0x7A] = .{ .mnem = .nop, .mode = .imp, .cycles = 2 };
        table[0xDA] = .{ .mnem = .nop, .mode = .imp, .cycles = 2 };
        table[0xFA] = .{ .mnem = .nop, .mode = .imp, .cycles = 2 };
        table[0x04] = .{ .mnem = .nop, .mode = .zp, .cycles = 3 };
        table[0x44] = .{ .mnem = .nop, .mode = .zp, .cycles = 3 };
        table[0x64] = .{ .mnem = .nop, .mode = .zp, .cycles = 3 };
        table[0x0C] = .{ .mnem = .nop, .mode = .abs, .cycles = 4 };
        table[0x14] = .{ .mnem = .nop, .mode = .zpx, .cycles = 4 };
        table[0x34] = .{ .mnem = .nop, .mode = .zpx, .cycles = 4 };
        table[0x54] = .{ .mnem = .nop, .mode = .zpx, .cycles = 4 };
        table[0x74] = .{ .mnem = .nop, .mode = .zpx, .cycles = 4 };
        table[0xD4] = .{ .mnem = .nop, .mode = .zpx, .cycles = 4 };
        table[0xF4] = .{ .mnem = .nop, .mode = .zpx, .cycles = 4 };
        table[0x1C] = .{ .mnem = .nop, .mode = .abx, .cycles = 4, .page_cross = true };
        table[0x3C] = .{ .mnem = .nop, .mode = .abx, .cycles = 4, .page_cross = true };
        table[0x5C] = .{ .mnem = .nop, .mode = .abx, .cycles = 4, .page_cross = true };
        table[0x7C] = .{ .mnem = .nop, .mode = .abx, .cycles = 4, .page_cross = true };
        table[0xDC] = .{ .mnem = .nop, .mode = .abx, .cycles = 4, .page_cross = true };
        table[0xFC] = .{ .mnem = .nop, .mode = .abx, .cycles = 4, .page_cross = true };
        table[0x80] = .{ .mnem = .nop, .mode = .imm, .cycles = 2 };
        table[0x82] = .{ .mnem = .nop, .mode = .imm, .cycles = 2 };
        table[0x89] = .{ .mnem = .nop, .mode = .imm, .cycles = 2 };
        table[0xC2] = .{ .mnem = .nop, .mode = .imm, .cycles = 2 };
        table[0xE2] = .{ .mnem = .nop, .mode = .imm, .cycles = 2 };

        // Unofficial but commonly used
        // LAX (LDA + LDX)
        table[0xA7] = .{ .mnem = .lax, .mode = .zp, .cycles = 3 };
        table[0xB7] = .{ .mnem = .lax, .mode = .zpy, .cycles = 4 };
        table[0xAF] = .{ .mnem = .lax, .mode = .abs, .cycles = 4 };
        table[0xBF] = .{ .mnem = .lax, .mode = .aby, .cycles = 4, .page_cross = true };
        table[0xA3] = .{ .mnem = .lax, .mode = .izx, .cycles = 6 };
        table[0xB3] = .{ .mnem = .lax, .mode = .izy, .cycles = 5, .page_cross = true };

        // SAX (Store A AND X)
        table[0x87] = .{ .mnem = .sax, .mode = .zp, .cycles = 3 };
        table[0x97] = .{ .mnem = .sax, .mode = .zpy, .cycles = 4 };
        table[0x8F] = .{ .mnem = .sax, .mode = .abs, .cycles = 4 };
        table[0x83] = .{ .mnem = .sax, .mode = .izx, .cycles = 6 };

        // DCP (DEC + CMP)
        table[0xC7] = .{ .mnem = .dcp, .mode = .zp, .cycles = 5 };
        table[0xD7] = .{ .mnem = .dcp, .mode = .zpx, .cycles = 6 };
        table[0xCF] = .{ .mnem = .dcp, .mode = .abs, .cycles = 6 };
        table[0xDF] = .{ .mnem = .dcp, .mode = .abx, .cycles = 7 };
        table[0xDB] = .{ .mnem = .dcp, .mode = .aby, .cycles = 7 };
        table[0xC3] = .{ .mnem = .dcp, .mode = .izx, .cycles = 8 };
        table[0xD3] = .{ .mnem = .dcp, .mode = .izy, .cycles = 8 };

        // ISB/ISC (INC + SBC)
        table[0xE7] = .{ .mnem = .isb, .mode = .zp, .cycles = 5 };
        table[0xF7] = .{ .mnem = .isb, .mode = .zpx, .cycles = 6 };
        table[0xEF] = .{ .mnem = .isb, .mode = .abs, .cycles = 6 };
        table[0xFF] = .{ .mnem = .isb, .mode = .abx, .cycles = 7 };
        table[0xFB] = .{ .mnem = .isb, .mode = .aby, .cycles = 7 };
        table[0xE3] = .{ .mnem = .isb, .mode = .izx, .cycles = 8 };
        table[0xF3] = .{ .mnem = .isb, .mode = .izy, .cycles = 8 };

        // SLO (ASL + ORA)
        table[0x07] = .{ .mnem = .slo, .mode = .zp, .cycles = 5 };
        table[0x17] = .{ .mnem = .slo, .mode = .zpx, .cycles = 6 };
        table[0x0F] = .{ .mnem = .slo, .mode = .abs, .cycles = 6 };
        table[0x1F] = .{ .mnem = .slo, .mode = .abx, .cycles = 7 };
        table[0x1B] = .{ .mnem = .slo, .mode = .aby, .cycles = 7 };
        table[0x03] = .{ .mnem = .slo, .mode = .izx, .cycles = 8 };
        table[0x13] = .{ .mnem = .slo, .mode = .izy, .cycles = 8 };

        // RLA (ROL + AND)
        table[0x27] = .{ .mnem = .rla, .mode = .zp, .cycles = 5 };
        table[0x37] = .{ .mnem = .rla, .mode = .zpx, .cycles = 6 };
        table[0x2F] = .{ .mnem = .rla, .mode = .abs, .cycles = 6 };
        table[0x3F] = .{ .mnem = .rla, .mode = .abx, .cycles = 7 };
        table[0x3B] = .{ .mnem = .rla, .mode = .aby, .cycles = 7 };
        table[0x23] = .{ .mnem = .rla, .mode = .izx, .cycles = 8 };
        table[0x33] = .{ .mnem = .rla, .mode = .izy, .cycles = 8 };

        // SRE (LSR + EOR)
        table[0x47] = .{ .mnem = .sre, .mode = .zp, .cycles = 5 };
        table[0x57] = .{ .mnem = .sre, .mode = .zpx, .cycles = 6 };
        table[0x4F] = .{ .mnem = .sre, .mode = .abs, .cycles = 6 };
        table[0x5F] = .{ .mnem = .sre, .mode = .abx, .cycles = 7 };
        table[0x5B] = .{ .mnem = .sre, .mode = .aby, .cycles = 7 };
        table[0x43] = .{ .mnem = .sre, .mode = .izx, .cycles = 8 };
        table[0x53] = .{ .mnem = .sre, .mode = .izy, .cycles = 8 };

        // RRA (ROR + ADC)
        table[0x67] = .{ .mnem = .rra, .mode = .zp, .cycles = 5 };
        table[0x77] = .{ .mnem = .rra, .mode = .zpx, .cycles = 6 };
        table[0x6F] = .{ .mnem = .rra, .mode = .abs, .cycles = 6 };
        table[0x7F] = .{ .mnem = .rra, .mode = .abx, .cycles = 7 };
        table[0x7B] = .{ .mnem = .rra, .mode = .aby, .cycles = 7 };
        table[0x63] = .{ .mnem = .rra, .mode = .izx, .cycles = 8 };
        table[0x73] = .{ .mnem = .rra, .mode = .izy, .cycles = 8 };

        // Unofficial SBC
        table[0xEB] = .{ .mnem = .sbc, .mode = .imm, .cycles = 2 };

        break :init table;
    };

    /// Execute one instruction, return cycles consumed
    pub fn step(self: *CPU, mmu: *MMU) u8 {
        // Handle stall cycles (from DMA)
        if (self.stall > 0) {
            self.stall -= 1;
            return 1;
        }

        // Handle NMI
        if (self.nmi_pending) {
            self.nmi_pending = false;
            return self.handleNmi(mmu);
        }

        // Handle IRQ
        if (self.irq_pending and !self.status.i) {
            return self.handleIrq(mmu);
        }

        const opcode = mmu.read(self.pc);
        self.pc +%= 1;

        const op = opcodes[opcode];
        var cycles = op.cycles;
        var page_crossed = false;

        const addr = self.resolveAddress(mmu, op.mode, &page_crossed);

        if (op.page_cross and page_crossed) {
            cycles += 1;
        }

        self.execute(mmu, op.mnem, op.mode, addr, &cycles);

        self.cycles += cycles;
        return cycles;
    }

    fn resolveAddress(self: *CPU, mmu: *MMU, mode: Mode, page_crossed: *bool) u16 {
        return switch (mode) {
            .imp, .acc => 0,
            .imm => blk: {
                const addr = self.pc;
                self.pc +%= 1;
                break :blk addr;
            },
            .zp => blk: {
                const addr = mmu.read(self.pc);
                self.pc +%= 1;
                break :blk addr;
            },
            .zpx => blk: {
                const base = mmu.read(self.pc);
                self.pc +%= 1;
                break :blk (base +% self.x) & 0xFF;
            },
            .zpy => blk: {
                const base = mmu.read(self.pc);
                self.pc +%= 1;
                break :blk (base +% self.y) & 0xFF;
            },
            .abs => self.fetchWord(mmu),
            .abx => blk: {
                const base = self.fetchWord(mmu);
                const addr = base +% self.x;
                page_crossed.* = (base & 0xFF00) != (addr & 0xFF00);
                break :blk addr;
            },
            .aby => blk: {
                const base = self.fetchWord(mmu);
                const addr = base +% self.y;
                page_crossed.* = (base & 0xFF00) != (addr & 0xFF00);
                break :blk addr;
            },
            .ind => blk: {
                const ptr = self.fetchWord(mmu);
                // 6502 bug: JMP ($xxFF) wraps within page
                const lo = mmu.read(ptr);
                const hi = mmu.read((ptr & 0xFF00) | ((ptr + 1) & 0xFF));
                break :blk (@as(u16, hi) << 8) | lo;
            },
            .izx => blk: {
                const base = mmu.read(self.pc);
                self.pc +%= 1;
                const ptr: u8 = base +% self.x;
                const lo = mmu.read(ptr);
                const hi = mmu.read(ptr +% 1);
                break :blk (@as(u16, hi) << 8) | lo;
            },
            .izy => blk: {
                const ptr = mmu.read(self.pc);
                self.pc +%= 1;
                const lo = mmu.read(ptr);
                const hi = mmu.read((ptr +% 1) & 0xFF);
                const base = (@as(u16, hi) << 8) | lo;
                const addr = base +% self.y;
                page_crossed.* = (base & 0xFF00) != (addr & 0xFF00);
                break :blk addr;
            },
            .rel => blk: {
                const offset: i8 = @bitCast(mmu.read(self.pc));
                self.pc +%= 1;
                const addr = @as(u16, @bitCast(@as(i16, @bitCast(self.pc)) +% offset));
                page_crossed.* = (self.pc & 0xFF00) != (addr & 0xFF00);
                break :blk addr;
            },
        };
    }

    fn fetchWord(self: *CPU, mmu: *MMU) u16 {
        const lo = mmu.read(self.pc);
        const hi = mmu.read(self.pc +% 1);
        self.pc +%= 2;
        return (@as(u16, hi) << 8) | lo;
    }

    fn execute(self: *CPU, mmu: *MMU, mnem: Mnem, mode: Mode, addr: u16, cycles: *u8) void {
        switch (mnem) {
            // Load
            .lda => {
                self.a = mmu.read(addr);
                self.setZN(self.a);
            },
            .ldx => {
                self.x = mmu.read(addr);
                self.setZN(self.x);
            },
            .ldy => {
                self.y = mmu.read(addr);
                self.setZN(self.y);
            },

            // Store
            .sta => mmu.write(addr, self.a),
            .stx => mmu.write(addr, self.x),
            .sty => mmu.write(addr, self.y),

            // Transfer
            .tax => {
                self.x = self.a;
                self.setZN(self.x);
            },
            .tay => {
                self.y = self.a;
                self.setZN(self.y);
            },
            .txa => {
                self.a = self.x;
                self.setZN(self.a);
            },
            .tya => {
                self.a = self.y;
                self.setZN(self.a);
            },
            .tsx => {
                self.x = self.sp;
                self.setZN(self.x);
            },
            .txs => self.sp = self.x,

            // Stack
            .pha => self.push(mmu, self.a),
            .php => self.push(mmu, @as(u8, @bitCast(self.status)) | 0x30), // B and unused set
            .pla => {
                self.a = self.pull(mmu);
                self.setZN(self.a);
            },
            .plp => {
                var s: Status = @bitCast(self.pull(mmu));
                s.b = false;
                s._ = true;
                self.status = s;
            },

            // Arithmetic
            .adc => self.adc(mmu.read(addr)),
            .sbc => self.sbc(mmu.read(addr)),

            // Compare
            .cmp => self.compare(self.a, mmu.read(addr)),
            .cpx => self.compare(self.x, mmu.read(addr)),
            .cpy => self.compare(self.y, mmu.read(addr)),

            // Increment/Decrement
            .inc => {
                const val = mmu.read(addr) +% 1;
                mmu.write(addr, val);
                self.setZN(val);
            },
            .inx => {
                self.x +%= 1;
                self.setZN(self.x);
            },
            .iny => {
                self.y +%= 1;
                self.setZN(self.y);
            },
            .dec => {
                const val = mmu.read(addr) -% 1;
                mmu.write(addr, val);
                self.setZN(val);
            },
            .dex => {
                self.x -%= 1;
                self.setZN(self.x);
            },
            .dey => {
                self.y -%= 1;
                self.setZN(self.y);
            },

            // Shift
            .asl => {
                if (mode == .acc) {
                    self.status.c = self.a & 0x80 != 0;
                    self.a <<= 1;
                    self.setZN(self.a);
                } else {
                    var val = mmu.read(addr);
                    self.status.c = val & 0x80 != 0;
                    val <<= 1;
                    mmu.write(addr, val);
                    self.setZN(val);
                }
            },
            .lsr => {
                if (mode == .acc) {
                    self.status.c = self.a & 1 != 0;
                    self.a >>= 1;
                    self.setZN(self.a);
                } else {
                    var val = mmu.read(addr);
                    self.status.c = val & 1 != 0;
                    val >>= 1;
                    mmu.write(addr, val);
                    self.setZN(val);
                }
            },
            .rol => {
                const carry: u8 = if (self.status.c) 1 else 0;
                if (mode == .acc) {
                    self.status.c = self.a & 0x80 != 0;
                    self.a = (self.a << 1) | carry;
                    self.setZN(self.a);
                } else {
                    var val = mmu.read(addr);
                    self.status.c = val & 0x80 != 0;
                    val = (val << 1) | carry;
                    mmu.write(addr, val);
                    self.setZN(val);
                }
            },
            .ror => {
                const carry: u8 = if (self.status.c) 0x80 else 0;
                if (mode == .acc) {
                    self.status.c = self.a & 1 != 0;
                    self.a = (self.a >> 1) | carry;
                    self.setZN(self.a);
                } else {
                    var val = mmu.read(addr);
                    self.status.c = val & 1 != 0;
                    val = (val >> 1) | carry;
                    mmu.write(addr, val);
                    self.setZN(val);
                }
            },

            // Logic
            .@"and" => {
                self.a &= mmu.read(addr);
                self.setZN(self.a);
            },
            .eor => {
                self.a ^= mmu.read(addr);
                self.setZN(self.a);
            },
            .ora => {
                self.a |= mmu.read(addr);
                self.setZN(self.a);
            },
            .bit => {
                const val = mmu.read(addr);
                self.status.z = (self.a & val) == 0;
                self.status.v = val & 0x40 != 0;
                self.status.n = val & 0x80 != 0;
            },

            // Branch
            .bcc => self.branch(!self.status.c, addr, cycles),
            .bcs => self.branch(self.status.c, addr, cycles),
            .beq => self.branch(self.status.z, addr, cycles),
            .bmi => self.branch(self.status.n, addr, cycles),
            .bne => self.branch(!self.status.z, addr, cycles),
            .bpl => self.branch(!self.status.n, addr, cycles),
            .bvc => self.branch(!self.status.v, addr, cycles),
            .bvs => self.branch(self.status.v, addr, cycles),

            // Jump
            .jmp => self.pc = addr,
            .jsr => {
                self.pushWord(mmu, self.pc -% 1);
                self.pc = addr;
            },
            .rts => self.pc = self.pullWord(mmu) +% 1,
            .rti => {
                var s: Status = @bitCast(self.pull(mmu));
                s.b = false;
                s._ = true;
                self.status = s;
                self.pc = self.pullWord(mmu);
            },

            // Flags
            .clc => self.status.c = false,
            .cld => self.status.d = false,
            .cli => self.status.i = false,
            .clv => self.status.v = false,
            .sec => self.status.c = true,
            .sed => self.status.d = true,
            .sei => self.status.i = true,

            // System
            .brk => {
                self.pc +%= 1;
                self.pushWord(mmu, self.pc);
                self.push(mmu, @as(u8, @bitCast(self.status)) | 0x30);
                self.status.i = true;
                self.pc = self.readWord(mmu, 0xFFFE);
            },
            .nop => {},

            // Illegal opcodes
            .lax => {
                self.a = mmu.read(addr);
                self.x = self.a;
                self.setZN(self.a);
            },
            .sax => mmu.write(addr, self.a & self.x),
            .dcp => {
                const val = mmu.read(addr) -% 1;
                mmu.write(addr, val);
                self.compare(self.a, val);
            },
            .isb => {
                const val = mmu.read(addr) +% 1;
                mmu.write(addr, val);
                self.sbc(val);
            },
            .slo => {
                var val = mmu.read(addr);
                self.status.c = val & 0x80 != 0;
                val <<= 1;
                mmu.write(addr, val);
                self.a |= val;
                self.setZN(self.a);
            },
            .rla => {
                const carry: u8 = if (self.status.c) 1 else 0;
                var val = mmu.read(addr);
                self.status.c = val & 0x80 != 0;
                val = (val << 1) | carry;
                mmu.write(addr, val);
                self.a &= val;
                self.setZN(self.a);
            },
            .sre => {
                var val = mmu.read(addr);
                self.status.c = val & 1 != 0;
                val >>= 1;
                mmu.write(addr, val);
                self.a ^= val;
                self.setZN(self.a);
            },
            .rra => {
                const carry: u8 = if (self.status.c) 0x80 else 0;
                var val = mmu.read(addr);
                self.status.c = val & 1 != 0;
                val = (val >> 1) | carry;
                mmu.write(addr, val);
                self.adc(val);
            },
            .xxx => {},
        }
    }

    // Helpers
    fn setZN(self: *CPU, val: u8) void {
        self.status.z = val == 0;
        self.status.n = val & 0x80 != 0;
    }

    fn adc(self: *CPU, val: u8) void {
        const carry: u8 = if (self.status.c) 1 else 0;
        const sum: u16 = @as(u16, self.a) + val + carry;
        const result: u8 = @truncate(sum);

        self.status.c = sum > 0xFF;
        self.status.v = ((self.a ^ result) & (val ^ result) & 0x80) != 0;
        self.a = result;
        self.setZN(self.a);
    }

    fn sbc(self: *CPU, val: u8) void {
        self.adc(~val);
    }

    fn compare(self: *CPU, reg: u8, val: u8) void {
        const result = reg -% val;
        self.status.c = reg >= val;
        self.setZN(result);
    }

    fn branch(self: *CPU, cond: bool, addr: u16, cycles: *u8) void {
        if (cond) {
            cycles.* += 1;
            if ((self.pc & 0xFF00) != (addr & 0xFF00)) {
                cycles.* += 1;
            }
            self.pc = addr;
        }
    }

    fn push(self: *CPU, mmu: *MMU, val: u8) void {
        mmu.write(0x0100 | @as(u16, self.sp), val);
        self.sp -%= 1;
    }

    fn pull(self: *CPU, mmu: *MMU) u8 {
        self.sp +%= 1;
        return mmu.read(0x0100 | @as(u16, self.sp));
    }

    fn pushWord(self: *CPU, mmu: *MMU, val: u16) void {
        self.push(mmu, @truncate(val >> 8));
        self.push(mmu, @truncate(val));
    }

    fn pullWord(self: *CPU, mmu: *MMU) u16 {
        const lo = self.pull(mmu);
        const hi = self.pull(mmu);
        return (@as(u16, hi) << 8) | lo;
    }

    fn readWord(self: *CPU, mmu: *MMU, addr: u16) u16 {
        _ = self;
        const lo = mmu.read(addr);
        const hi = mmu.read(addr +% 1);
        return (@as(u16, hi) << 8) | lo;
    }

    fn handleNmi(self: *CPU, mmu: *MMU) u8 {
        self.pushWord(mmu, self.pc);
        self.push(mmu, @as(u8, @bitCast(self.status)) & 0xEF); // Clear B
        self.status.i = true;
        self.pc = self.readWord(mmu, 0xFFFA);
        return 7;
    }

    fn handleIrq(self: *CPU, mmu: *MMU) u8 {
        self.pushWord(mmu, self.pc);
        self.push(mmu, @as(u8, @bitCast(self.status)) & 0xEF); // Clear B
        self.status.i = true;
        self.pc = self.readWord(mmu, 0xFFFE);
        return 7;
    }

    /// Reset the CPU
    pub fn reset(self: *CPU, mmu: *MMU) void {
        self.a = 0;
        self.x = 0;
        self.y = 0;
        self.sp = 0xFD;
        self.status = .{};
        self.pc = self.readWord(mmu, 0xFFFC);
        self.cycles = 0;
        self.stall = 0;
        self.nmi_pending = false;
        self.irq_pending = false;
    }
};
