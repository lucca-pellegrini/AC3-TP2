const std = @import("std");

const c_sources = &.{
    "src/tomasulo.c",
    "src/parser.c",
    "src/display.c",
    "src/main.c",
};

const c_lib_sources = &.{
    "src/tomasulo.c",
    "src/parser.c",
    "src/display.c",
};

const c_flags = &.{
    "-std=c23",
    "-Wall",
    "-Wextra",
    "-Wpedantic",
    "-D_GNU_SOURCE",
};

pub fn build(b: *std.Build) void {
    // ── Target & Optimization ───────────────────────────────────────
    //
    // Default target is x86_64-linux-musl for fully static binaries,
    // but can be overridden via `zig build -Dtarget=...`
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .musl,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    // ── Main Executable ─────────────────────────────────────────────

    const exe_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe_mod.addCSourceFiles(.{
        .files = c_sources,
        .flags = c_flags,
    });

    exe_mod.addIncludePath(b.path("src"));

    const exe = b.addExecutable(.{
        .name = "tomasulo",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    // ── Run step ────────────────────────────────────────────────────

    const run_step = b.step("run", "Run the Tomasulo simulator");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    // ── Tests (Zig test harness calling C code) ─────────────────────

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    test_mod.addIncludePath(b.path("src"));
    test_mod.addCSourceFiles(.{
        .files = c_lib_sources,
        .flags = c_flags,
    });

    const tests = b.addTest(.{
        .root_module = test_mod,
        .test_runner = .{
            .path = b.path("src/test_runner.zig"),
            .mode = .simple,
        },
    });

    const run_tests = b.addRunArtifact(tests);
    // Force stdio inheritance so our custom runner's output reaches the user.
    run_tests.stdio = .inherit;
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
