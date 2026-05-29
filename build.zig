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

// Generated flex/bison sources tend to trip strict warnings; relax just
// for them.
const gen_c_flags = &.{
    "-std=c23",
    "-D_GNU_SOURCE",
    "-Wno-unused-function",
    "-Wno-unused-but-set-variable",
};

// Run bison on `parser.y`, producing parser.tab.c and parser.tab.h.
// Returns LazyPaths for the generated .c and .h files plus the run step.
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
    // Bison writes parser.tab.h alongside parser.tab.c, so derive the
    // header path from the same generated directory.
    const tab_h = tab_c.dirname().path(b, "parser.tab.h");
    return .{ .c = tab_c, .h = tab_h, .step = &run.step };
}

// Run flex on `parser.l`, producing the scanner .c file.  Depends on
// the bison output to ensure parser.tab.h exists when flex runs.
fn runFlex(b: *std.Build, bison_h: std.Build.LazyPath) std.Build.LazyPath {
    const tool = b.findProgram(&.{ "flex", "lex" }, &.{}) catch {
        std.debug.panic("flex/lex not found in PATH", .{});
    };
    const run = b.addSystemCommand(&.{tool});
    run.addArg("-o");
    const out = run.addOutputFileArg("build/gen/lex.parser.c");
    run.addFileArg(b.path("src/parser.l"));
    // Make sure parser.tab.h exists before flex runs, since parser.l
    // %includes it.
    _ = bison_h;
    return out;
}

// Attach the generated parser+scanner sources to a module.  The
// generated parser.tab.h is added as an include path so parser.c (and
// the rest of the module) can find it.
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
    // The generated header is in the same directory as parser.tab.c.
    mod.addIncludePath(bison.c.dirname());
}

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

    exe_mod.addIncludePath(b.path("include"));
    addGeneratedParser(b, exe_mod);

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
    // Force stdio inheritance so our custom runner's output reaches the user.
    run_tests.stdio = .inherit;
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // ── Clean step ────────────────────────────────────────────────────
    const clean_step = b.step("clean", "Clean build artifacts");
    const rm = b.addSystemCommand(&.{ "rm", "-f", "tomasulo" });
    const rm_objs = b.addSystemCommand(&.{ "rm", "-f", "src/tomasulo.o", "src/parser.o", "src/display.o", "src/main.o", "src/parser.tab.o", "src/lex.parser.o" });
    const rm_gen = b.addSystemCommand(&.{ "rm", "-f", "src/parser.tab.c", "src/lex.parser.c", "src/parser.tab.h" });
    const rm_rf = b.addSystemCommand(&.{ "rm", "-rf", "zig-out", ".zig-cache" });
    clean_step.dependOn(&rm.step);
    clean_step.dependOn(&rm_objs.step);
    clean_step.dependOn(&rm_gen.step);
    clean_step.dependOn(&rm_rf.step);
}
