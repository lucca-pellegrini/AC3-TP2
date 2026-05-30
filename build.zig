// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>

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
    "-pedantic",
    "-D_GNU_SOURCE",
};

// Generated flex/bison sources tend to trip strict warnings
const gen_c_flags = &.{
    "-std=c23",
    "-D_GNU_SOURCE",
    "-Wno-unused-function",
    "-Wno-unused-but-set-variable",
};

// Run bison on `parser.y`, producing parser.tab.c and parser.tab.h.
const BisonOutputs = struct {
    c: std.Build.LazyPath,
    h: std.Build.LazyPath,
    step: *std.Build.Step,
};

fn runBison(b: *std.Build) BisonOutputs {
    const tool = b.findProgram(&.{ "bison", "yacc" }, &.{}) catch {
        std.debug.panic("bison/yacc not found in PATH", .{});
    };
    const run = b.addSystemCommand(&.{tool});
    run.addArg("-d");
    run.addArg("-o");
    const tab_c = run.addOutputFileArg("build/gen/parser.tab.c");
    run.addFileArg(b.path("src/parser.y"));
    const tab_h = tab_c.dirname().path(b, "parser.tab.h");
    return .{ .c = tab_c, .h = tab_h, .step = &run.step };
}

// Run flex on `parser.l`, producing the scanner .c file.
fn runFlex(b: *std.Build, bison_h: std.Build.LazyPath) std.Build.LazyPath {
    const tool = b.findProgram(&.{ "flex", "lex" }, &.{}) catch {
        std.debug.panic("flex/lex not found in PATH", .{});
    };
    const run = b.addSystemCommand(&.{tool});
    run.addArg("-o");
    const out = run.addOutputFileArg("build/gen/lex.parser.c");
    run.addFileArg(b.path("src/parser.l"));
    _ = bison_h; // Make sure parser.tab.h exists before flex runs.
    return out;
}

// Attach the generated parser/scanner sources to a module.
fn addGeneratedParser(b: *std.Build, mod: *std.Build.Module) void {
    const bison = runBison(b);
    const lex_c = runFlex(b, bison.h);

    mod.addCSourceFile(.{
        .file = bison.c,
        .flags = gen_c_flags,
    });
    mod.addCSourceFile(.{
        .file = lex_c,
        .flags = gen_c_flags,
    });
    mod.addIncludePath(bison.c.dirname()); // Header in the same dir.
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .musl,
        },
    });
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });

    // Main executable

    const exe_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // .strip = true,
    });

    exe_mod.addCSourceFiles(.{
        .files = c_sources,
        .flags = c_flags,
    });

    exe_mod.addIncludePath(b.path("include"));
    addGeneratedParser(b, exe_mod);

    const exe = b.addExecutable(.{
        .name = "tomasulo",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    // Run the program

    const run_step = b.step("run", "Run the Tomasulo simulator");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    // Call the test harness

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    test_mod.addIncludePath(b.path("include"));
    test_mod.addCSourceFiles(.{
        .files = c_lib_sources,
        .flags = c_flags,
    });
    addGeneratedParser(b, test_mod);

    const tests = b.addTest(.{
        .root_module = test_mod,
        .test_runner = .{
            .path = b.path("src/test_runner.zig"),
            .mode = .simple,
        },
    });

    const run_tests = b.addRunArtifact(tests);
    run_tests.stdio = .inherit; // Ensure output reaches user.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Clean outputs

    const clean_step = b.step("clean", "Clean build artifacts");
    const rm_rf = b.addSystemCommand(&.{ "rm", "-rf", "zig-out", ".zig-cache", "build" });
    clean_step.dependOn(&rm_rf.step);
}
