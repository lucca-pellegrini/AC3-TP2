// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! Common imports and helper functions for all test modules.

pub const std = @import("std");
pub const testing = std.testing;

pub const c = @cImport({
    @cInclude("tomasulo.h");
    @cInclude("parser.h");
    @cInclude("display.h");
    @cInclude("stdio.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
});

// ═══════════════════════════════════════════════════════════════════════════
// Simulator helpers
// ═══════════════════════════════════════════════════════════════════════════

pub fn initSim(cfg: *c.TomasuloConfig) c.Simulator {
    var sim: c.Simulator = undefined;
    c.sim_init(&sim, cfg);
    return sim;
}

pub fn initDefaultSim() c.Simulator {
    var cfg = c.config_default();
    return initSim(&cfg);
}

pub fn initSimWith(
    add_rs: c_int,
    mult_rs: c_int,
    load_rs: c_int,
    store_rs: c_int,
) c.Simulator {
    var cfg = c.config_default();
    cfg.num_rs[c.RS_ADD] = add_rs;
    cfg.num_rs[c.RS_MULT] = mult_rs;
    cfg.num_rs[c.RS_LOAD] = load_rs;
    cfg.num_rs[c.RS_STORE] = store_rs;
    return initSim(&cfg);
}

pub fn makeArithInst(op: c.Opcode, dest: c_int, src1: c_int, src2: c_int) c.Instruction {
    return c.Instruction{
        .op = op,
        .dest = dest,
        .src1 = src1,
        .src2 = src2,
        .imm = 0,
        .issue_cycle = 0,
        .exec_start = 0,
        .exec_end = 0,
        .write_cycle = 0,
    };
}

pub fn makeMemInst(op: c.Opcode, dest: c_int, imm: c_int, base: c_int) c.Instruction {
    return c.Instruction{
        .op = op,
        .dest = dest,
        .src1 = base,
        .src2 = -1,
        .imm = imm,
        .issue_cycle = 0,
        .exec_start = 0,
        .exec_end = 0,
        .write_cycle = 0,
    };
}

pub fn addInst(sim: *c.Simulator, inst: c.Instruction) void {
    _ = c.sim_add_instruction(sim, inst);
}

pub fn runToCompletion(sim: *c.Simulator) c_int {
    return c.sim_run(sim, 500);
}

pub fn getInst(sim: *const c.Simulator, idx: usize) c.Instruction {
    return sim.instructions[idx];
}

// ═══════════════════════════════════════════════════════════════════════════
// Parser test helpers (using libc for temp files)
// ═══════════════════════════════════════════════════════════════════════════

// c_io is now the same as c (unified import)
pub const c_io = c;

/// Write `text` to a freshly-created temp file via libc and return its
/// NUL-terminated path.  Caller frees with `freeTmpPath()`.
pub fn makeTmpFile(text: []const u8) ![:0]u8 {
    var template_buf: [64]u8 = undefined;
    const template = std.fmt.bufPrintZ(
        &template_buf,
        "/tmp/tomasulo_parser_test_XXXXXX",
        .{},
    ) catch unreachable;
    const fd = c_io.mkstemp(template.ptr);
    if (fd < 0) return error.MkstempFailed;
    const written = c_io.write(fd, text.ptr, text.len);
    _ = c_io.close(fd);
    if (written < 0 or @as(usize, @intCast(written)) != text.len)
        return error.WriteFailed;
    return testing.allocator.dupeZ(u8, template);
}

pub fn freeTmpPath(path: [:0]u8) void {
    _ = c_io.unlink(path.ptr);
    testing.allocator.free(path);
}

/// Write `text`, parse it, return cfg+sim+path.  Asserts parse succeeds.
pub fn parseSource(text: []const u8) !struct {
    cfg: c.TomasuloConfig,
    sim: c.Simulator,
    path: [:0]u8,
} {
    const path = try makeTmpFile(text);
    var cfg: c.TomasuloConfig = undefined;
    var sim: c.Simulator = undefined;
    const rc = c.parse_input(path.ptr, &cfg, &sim);
    if (rc != 0) {
        freeTmpPath(path);
        return error.ParseFailed;
    }
    return .{ .cfg = cfg, .sim = sim, .path = path };
}

pub fn freeParse(p: anytype) void {
    freeTmpPath(p.path);
}

/// Parse and expect a parse error.  Suppresses the parser's stderr
/// chatter so test output stays clean.
pub fn parseExpectFail(text: []const u8) !void {
    const path = try makeTmpFile(text);
    defer freeTmpPath(path);

    // Redirect stderr to /dev/null while parse_input runs.
    const saved = c_io.dup(2);
    const dn = c_io.open("/dev/null", c_io.O_WRONLY);
    if (dn >= 0) {
        _ = c_io.dup2(dn, 2);
        _ = c_io.close(dn);
    }
    defer {
        if (saved >= 0) {
            _ = c_io.dup2(saved, 2);
            _ = c_io.close(saved);
        }
    }

    var cfg: c.TomasuloConfig = undefined;
    var sim: c.Simulator = undefined;
    const rc = c.parse_input(path.ptr, &cfg, &sim);
    try testing.expect(rc != 0);
}
