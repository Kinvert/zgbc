//! Blargg Test ROM Harness
//! Runs test ROMs and checks for pass/fail via serial output.

const std = @import("std");
const zgbc = @import("zgbc");
const GB = zgbc.GB;

/// Maximum cycles to run before timing out (about 30 seconds of emulated time)
const MAX_CYCLES: u64 = 30 * 4_194_304;

/// Extended timeout for combined test suite (about 5 minutes)
const MAX_CYCLES_EXTENDED: u64 = 300 * 4_194_304;

/// Maximum serial output buffer size
const MAX_OUTPUT: usize = 4096;

pub const TestResult = struct {
    output: []const u8,
    passed: bool,
    timed_out: bool,
};

/// Run a test ROM and return the result
pub fn runTestRom(rom: []const u8, output_buf: []u8, max_cycles: u64) TestResult {
    var gb = GB{};
    gb.loadRom(rom) catch return .{ .output = "Failed to load ROM", .passed = false, .timed_out = false };
    gb.skipBootRom();

    var len: usize = 0;

    while (gb.cycles < max_cycles) {
        _ = gb.step();

        // Check for serial output
        if (gb.mmu.serial_pending) {
            if (len < output_buf.len) {
                output_buf[len] = gb.mmu.serial_data;
                len += 1;
            }
            gb.mmu.serial_pending = false;
            gb.mmu.serial_control &= 0x7F; // Clear transfer bit

            // Check for test completion
            const current = output_buf[0..len];
            if (std.mem.indexOf(u8, current, "Passed") != null) {
                return .{ .output = current, .passed = true, .timed_out = false };
            }
            if (std.mem.indexOf(u8, current, "Failed") != null) {
                return .{ .output = current, .passed = false, .timed_out = false };
            }
        }
    }

    return .{ .output = output_buf[0..len], .passed = false, .timed_out = true };
}

// =============================================================================
// Individual CPU instruction tests
// These will fail until opcodes are implemented - that's the point of TDD!
// =============================================================================

fn runAndCheckWithTimeout(comptime rom_path: []const u8, max_cycles: u64) !void {
    const rom = @embedFile(rom_path);
    var output_buf: [MAX_OUTPUT]u8 = undefined;
    const result = runTestRom(rom, &output_buf, max_cycles);

    if (result.timed_out) {
        return error.TimedOut;
    }

    if (!result.passed) {
        return error.TestFailed;
    }
}

fn runAndCheck(comptime rom_path: []const u8) !void {
    return runAndCheckWithTimeout(rom_path, MAX_CYCLES);
}

test "blargg 01-special" {
    try runAndCheck("gb-test-roms/cpu_instrs/individual/01-special.gb");
}

test "blargg 02-interrupts" {
    try runAndCheck("gb-test-roms/cpu_instrs/individual/02-interrupts.gb");
}

test "blargg 03-op sp,hl" {
    try runAndCheck("gb-test-roms/cpu_instrs/individual/03-op sp,hl.gb");
}

test "blargg 04-op r,imm" {
    try runAndCheck("gb-test-roms/cpu_instrs/individual/04-op r,imm.gb");
}

test "blargg 05-op rp" {
    try runAndCheck("gb-test-roms/cpu_instrs/individual/05-op rp.gb");
}

test "blargg 06-ld r,r" {
    try runAndCheck("gb-test-roms/cpu_instrs/individual/06-ld r,r.gb");
}

test "blargg 07-jr,jp,call,ret,rst" {
    try runAndCheck("gb-test-roms/cpu_instrs/individual/07-jr,jp,call,ret,rst.gb");
}

test "blargg 08-misc instrs" {
    try runAndCheck("gb-test-roms/cpu_instrs/individual/08-misc instrs.gb");
}

test "blargg 09-op r,r" {
    try runAndCheck("gb-test-roms/cpu_instrs/individual/09-op r,r.gb");
}

test "blargg 10-bit ops" {
    try runAndCheck("gb-test-roms/cpu_instrs/individual/10-bit ops.gb");
}

test "blargg 11-op a,(hl)" {
    try runAndCheck("gb-test-roms/cpu_instrs/individual/11-op a,(hl).gb");
}

// =============================================================================
// Full test suite
// =============================================================================

test "blargg cpu_instrs" {
    try runAndCheckWithTimeout("gb-test-roms/cpu_instrs/cpu_instrs.gb", MAX_CYCLES_EXTENDED);
}
