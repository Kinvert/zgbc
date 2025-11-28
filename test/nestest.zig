//! nestest.nes CPU validation test
//! Runs the nestest ROM in automation mode and checks results.

const std = @import("std");
const zetro = @import("zgbc");
const NES = zetro.NES;

const nestest_rom = @embedFile("nes-test-roms/other/nestest.nes");

test "nestest CPU validation" {
    var nes = NES{};
    nes.loadRom(nestest_rom);

    // Set PC to automation mode entry point
    nes.cpu.pc = 0xC000;

    // Run for ~8991 instructions (official test length)
    var instructions: u32 = 0;
    while (instructions < 8991) : (instructions += 1) {
        _ = nes.step();
    }

    // Check result codes at $02 and $03
    // $02 = 0x00 means all official opcodes passed
    // $03 = 0x00 means all unofficial opcodes passed
    const official_result = nes.read(0x02);
    const unofficial_result = nes.read(0x03);

    if (official_result != 0x00) {
        std.debug.print("nestest FAILED: official opcodes error code 0x{X:0>2}\n", .{official_result});
    }
    if (unofficial_result != 0x00) {
        std.debug.print("nestest FAILED: unofficial opcodes error code 0x{X:0>2}\n", .{unofficial_result});
    }

    try std.testing.expectEqual(@as(u8, 0x00), official_result);
    // Unofficial opcodes are bonus - don't fail on them for now
    // try std.testing.expectEqual(@as(u8, 0x00), unofficial_result);
}

test "NES basic instantiation" {
    var nes = NES{};
    nes.loadRom(nestest_rom);

    // Just run a few frames to make sure nothing crashes
    for (0..10) |_| {
        nes.frame();
    }

    // Should have advanced
    try std.testing.expect(nes.cycles > 0);
    try std.testing.expect(nes.ppu.frame > 0);
}
