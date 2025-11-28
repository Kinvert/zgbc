const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ============================================================
    // Library module - exposed to consumers via @import("zgbc")
    // ============================================================
    const zgbc_mod = b.addModule("zgbc", .{
        .root_source_file = b.path("src/root.zig"),
        // Don't set target/optimize here - let consumers decide
    });

    // ============================================================
    // Executables (CLI, benchmark)
    // ============================================================
    const exe = b.addExecutable(.{
        .name = "zgbc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zgbc", .module = zgbc_mod }},
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the emulator");
    run_step.dependOn(&run_cmd.step);

    // Benchmark
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    const bench_step = b.step("bench", "Run performance benchmark");
    bench_step.dependOn(&b.addRunArtifact(bench).step);

    // ============================================================
    // C libraries (libzgbc)
    // ============================================================
    const c_api_mod = b.createModule(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Shared library
    const shared_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zgbc",
        .root_module = c_api_mod,
    });
    shared_lib.linkLibC();

    // Static library
    const static_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zgbc",
        .root_module = c_api_mod,
    });

    const lib_step = b.step("lib", "Build C libraries (libzgbc.so + libzgbc.a)");
    lib_step.dependOn(&b.addInstallArtifact(shared_lib, .{}).step);
    lib_step.dependOn(&b.addInstallArtifact(static_lib, .{}).step);
    lib_step.dependOn(&b.addInstallHeaderFile(b.path("include/zgbc.h"), "zgbc.h").step);

    // ============================================================
    // WASM build
    // ============================================================
    const wasm = b.addExecutable(.{
        .name = "zgbc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
            }),
            .optimize = .ReleaseSmall,
        }),
    });
    wasm.rdynamic = true;
    wasm.entry = .disabled;

    const wasm_step = b.step("wasm", "Build WASM module for browser");
    wasm_step.dependOn(&b.addInstallArtifact(wasm, .{}).step);

    // ============================================================
    // Tests
    // ============================================================

    // Library tests
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Blargg CPU instruction tests
    const blargg_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/blargg_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zgbc", .module = zgbc_mod }},
        }),
    });

    // Pokemon Red boot test
    const pokemon_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/pokemon_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zgbc", .module = zgbc_mod }},
        }),
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);

    const blargg_step = b.step("test-blargg", "Run Blargg CPU instruction tests");
    blargg_step.dependOn(&b.addRunArtifact(blargg_tests).step);

    const pokemon_step = b.step("test-pokemon", "Run Pokemon Red boot test");
    pokemon_step.dependOn(&b.addRunArtifact(pokemon_tests).step);
}
