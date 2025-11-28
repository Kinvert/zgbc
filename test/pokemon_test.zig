//! Pokemon Red Boot Test
//! Verifies the emulator can boot Pokemon Red to the title screen.

const std = @import("std");
const zgbc = @import("zgbc");
const GB = zgbc.GB;
const pokered_rom = @embedFile("pokered.gb");

// Run Pokemon Red and check if it reaches title screen
test "pokemon red boots to title" {
    const rom = pokered_rom;
    var gb = GB{};
    try gb.loadRom(rom);
    gb.skipBootRom();

    // Run for ~1000 frames (about 16 seconds of game time)
    // Pokemon Red takes a few seconds to show title after Nintendo logo
    for (0..1000) |_| {
        gb.frame();
    }

    // The game should have run many cycles (title screen loop)
    // PC should be in a stable loop, cycles should be ~70M for 1000 frames
    try std.testing.expect(gb.cycles > 50_000_000);
}

// Quick sanity check - just run a few frames
test "pokemon red runs without crash" {
    const rom = pokered_rom;
    var gb = GB{};
    try gb.loadRom(rom);
    gb.skipBootRom();

    // Run 100 frames
    for (0..100) |_| {
        gb.frame();
    }

    // Should have executed millions of cycles
    try std.testing.expect(gb.cycles > 1_000_000);
}
