//! zgbc Benchmark
//! Measures raw emulation performance.

const std = @import("std");
const GB = @import("gb.zig").GB;

const NUM_THREADS = 16;
const BENCH_FRAMES = 10_000;

fn runFrames(gb: *GB, frames: usize) void {
    for (0..frames) |_| {
        gb.frame();
    }
}

pub fn main() !void {
    // Load ROM from file using posix read
    const file = try std.fs.cwd().openFile("roms/pokered.gb", .{});
    defer file.close();
    const stat = try file.stat();
    const rom = try std.heap.page_allocator.alloc(u8, stat.size);
    defer std.heap.page_allocator.free(rom);

    // Read using preadAll
    const bytes_read = try std.posix.pread(file.handle, rom, 0);
    if (bytes_read != rom.len) return error.IncompleteRead;

    // Single instance benchmark
    {
        var gb = GB{};
        try gb.loadRom(rom);
        gb.skipBootRom();

        // Warmup - get to title screen
        for (0..1000) |_| {
            gb.frame();
        }

        // Benchmark
        var timer = try std.time.Timer.start();

        for (0..BENCH_FRAMES) |_| {
            gb.frame();
        }

        const elapsed_ns = timer.read();
        const elapsed_s: f64 = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        const fps: f64 = @as(f64, BENCH_FRAMES) / elapsed_s;

        std.debug.print("\n=== zgbc Benchmark (single instance) ===\n", .{});
        std.debug.print("Frames: {d}\n", .{BENCH_FRAMES});
        std.debug.print("Time: {d:.3}s\n", .{elapsed_s});
        std.debug.print("FPS: {d:.0}\n", .{fps});
        std.debug.print("vs realtime (60fps): {d:.0}x\n", .{fps / 60.0});
    }

    // 16 instances sequential (cache behavior test)
    {
        var gbs: [NUM_THREADS]GB = undefined;
        for (&gbs) |*gb| {
            gb.* = GB{};
            try gb.loadRom(rom);
            gb.skipBootRom();
        }

        // Warmup
        for (0..1000) |_| {
            for (&gbs) |*gb| {
                gb.frame();
            }
        }

        // Benchmark
        var timer = try std.time.Timer.start();

        for (0..BENCH_FRAMES) |_| {
            for (&gbs) |*gb| {
                gb.frame();
            }
        }

        const elapsed_ns = timer.read();
        const elapsed_s: f64 = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        const total_frames = BENCH_FRAMES * NUM_THREADS;
        const fps: f64 = @as(f64, total_frames) / elapsed_s;

        std.debug.print("\n=== zgbc Benchmark ({d} instances sequential) ===\n", .{NUM_THREADS});
        std.debug.print("Frames per instance: {d}\n", .{BENCH_FRAMES});
        std.debug.print("Total frames: {d}\n", .{total_frames});
        std.debug.print("Time: {d:.3}s\n", .{elapsed_s});
        std.debug.print("FPS (total): {d:.0}\n", .{fps});
        std.debug.print("FPS (per instance): {d:.0}\n", .{fps / NUM_THREADS});
        std.debug.print("vs realtime (60fps): {d:.0}x per instance\n", .{fps / NUM_THREADS / 60.0});
    }

    // 16 instances parallel (true threading)
    {
        var gbs: [NUM_THREADS]GB = undefined;
        for (&gbs) |*gb| {
            gb.* = GB{};
            try gb.loadRom(rom);
            gb.skipBootRom();
        }

        // Warmup
        for (&gbs) |*gb| {
            for (0..1000) |_| {
                gb.frame();
            }
        }

        // Benchmark with actual threads
        var timer = try std.time.Timer.start();

        var threads: [NUM_THREADS]std.Thread = undefined;
        for (&threads, &gbs) |*t, *gb| {
            t.* = try std.Thread.spawn(.{}, runFrames, .{ gb, BENCH_FRAMES });
        }
        for (&threads) |*t| {
            t.join();
        }

        const elapsed_ns = timer.read();
        const elapsed_s: f64 = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        const total_frames = BENCH_FRAMES * NUM_THREADS;
        const fps: f64 = @as(f64, total_frames) / elapsed_s;

        std.debug.print("\n=== zgbc Benchmark ({d} instances PARALLEL) ===\n", .{NUM_THREADS});
        std.debug.print("Frames per instance: {d}\n", .{BENCH_FRAMES});
        std.debug.print("Total frames: {d}\n", .{total_frames});
        std.debug.print("Time: {d:.3}s\n", .{elapsed_s});
        std.debug.print("FPS (total): {d:.0}\n", .{fps});
        std.debug.print("FPS (per instance): {d:.0}\n", .{fps / NUM_THREADS});
        std.debug.print("vs realtime (60fps): {d:.0}x per instance\n", .{fps / NUM_THREADS / 60.0});
        std.debug.print("\n", .{});
    }
}
