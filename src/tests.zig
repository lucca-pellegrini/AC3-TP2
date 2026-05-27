// SPDX-License-Identifier: MIT
// Zig test harness for the Tomasulo C simulator
const std = @import("std");
const testing = std.testing;

const c = @cImport({
    @cInclude("tomasulo.h");
    @cInclude("parser.h");
});

// ── Helpers ─────────────────────────────────────────────────────────────────

fn initDefaultSim() c.Simulator {
    var cfg = c.config_default();
    var sim: c.Simulator = undefined;
    c.sim_init(&sim, &cfg);
    return sim;
}

fn makeArithInst(op: c.Opcode, dest: i32, src1: i32, src2: i32) c.Instruction {
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

// ── Unit Tests ──────────────────────────────────────────────────────────────

test "opcode_from_str round-trip" {
    const cases = [_]struct { name: [*:0]const u8, expected: c.Opcode }{
        .{ .name = "ADDD", .expected = c.OP_ADDD },
        .{ .name = "ADD.D", .expected = c.OP_ADDD },
        .{ .name = "SUBD", .expected = c.OP_SUBD },
        .{ .name = "SUB.D", .expected = c.OP_SUBD },
        .{ .name = "MULTD", .expected = c.OP_MULTD },
        .{ .name = "MUL.D", .expected = c.OP_MULTD },
        .{ .name = "DIVD", .expected = c.OP_DIVD },
        .{ .name = "DIV.D", .expected = c.OP_DIVD },
        .{ .name = "LD", .expected = c.OP_LD },
        .{ .name = "L.D", .expected = c.OP_LD },
        .{ .name = "SD", .expected = c.OP_SD },
        .{ .name = "S.D", .expected = c.OP_SD },
    };
    for (cases) |tc| {
        try testing.expectEqual(tc.expected, c.opcode_from_str(tc.name));
    }
}

test "opcode_from_str invalid returns OP_COUNT" {
    try testing.expectEqual(@as(c_uint, c.OP_COUNT), c.opcode_from_str("NOPE"));
    try testing.expectEqual(@as(c_uint, c.OP_COUNT), c.opcode_from_str(""));
}

test "parse_register valid" {
    try testing.expectEqual(@as(c_int, 0), c.parse_register("F0"));
    try testing.expectEqual(@as(c_int, 6), c.parse_register("F6"));
    try testing.expectEqual(@as(c_int, 31), c.parse_register("F31"));
    try testing.expectEqual(@as(c_int, 2), c.parse_register("R2"));
}

test "parse_register invalid" {
    try testing.expectEqual(@as(c_int, -1), c.parse_register("X5"));
    try testing.expectEqual(@as(c_int, -1), c.parse_register(""));
    try testing.expectEqual(@as(c_int, -1), c.parse_register("F99"));
}

test "sim_init creates correct number of RS" {
    var cfg = c.config_default();
    cfg.num_rs[c.RS_ADD] = 3;
    cfg.num_rs[c.RS_MULT] = 2;
    cfg.num_rs[c.RS_LOAD] = 3;
    cfg.num_rs[c.RS_STORE] = 3;

    var sim: c.Simulator = undefined;
    c.sim_init(&sim, &cfg);

    try testing.expectEqual(@as(c_int, 11), sim.num_rs);
}

test "sim_add_instruction works" {
    var sim = initDefaultSim();
    const inst = makeArithInst(c.OP_ADDD, 8, 4, 6);
    try testing.expect(c.sim_add_instruction(&sim, inst));
    try testing.expectEqual(@as(c_int, 1), sim.num_instructions);
}

test "simple ADD.D simulation" {
    // F8 = F4 + F6, where F4=2.0, F6=10.0 => F8 should be 12.0
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 4, 2.0);
    c.sim_set_reg(&sim, 6, 10.0);

    _ = c.sim_add_instruction(&sim, makeArithInst(c.OP_ADDD, 8, 4, 6));

    const cycles = c.sim_run(&sim, 100);
    try testing.expect(cycles > 0);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(12.0, sim.fp_regs[8], 0.001);
}

test "RAW dependency chain: ADD then MUL" {
    // F8 = F4 + F6 (2+10=12), then F10 = F8 * F8 (12*12=144)
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 4, 2.0);
    c.sim_set_reg(&sim, 6, 10.0);

    _ = c.sim_add_instruction(&sim, makeArithInst(c.OP_ADDD, 8, 4, 6));
    _ = c.sim_add_instruction(&sim, makeArithInst(c.OP_MULTD, 10, 8, 8));

    _ = c.sim_run(&sim, 200);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(12.0, sim.fp_regs[8], 0.001);
    try testing.expectApproxEqAbs(144.0, sim.fp_regs[10], 0.001);
}

test "three-instruction chain with SUB" {
    // F8 = F4 + F6 (2+10=12)
    // F10 = F8 * F8 (144)
    // F12 = F10 - F4 (142)
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 4, 2.0);
    c.sim_set_reg(&sim, 6, 10.0);

    _ = c.sim_add_instruction(&sim, makeArithInst(c.OP_ADDD, 8, 4, 6));
    _ = c.sim_add_instruction(&sim, makeArithInst(c.OP_MULTD, 10, 8, 8));
    _ = c.sim_add_instruction(&sim, makeArithInst(c.OP_SUBD, 12, 10, 4));

    _ = c.sim_run(&sim, 200);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(12.0, sim.fp_regs[8], 0.001);
    try testing.expectApproxEqAbs(144.0, sim.fp_regs[10], 0.001);
    try testing.expectApproxEqAbs(142.0, sim.fp_regs[12], 0.001);
}

test "independent instructions run in parallel" {
    // Two independent ADD.D instructions with 2 Add RS should overlap
    var cfg = c.config_default();
    cfg.num_rs[c.RS_ADD] = 2;
    cfg.latency[c.OP_ADDD] = 2;

    var sim: c.Simulator = undefined;
    c.sim_init(&sim, &cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 5, 3.0);
    c.sim_set_reg(&sim, 6, 4.0);

    // F1 = F2 + F3 (independent)
    // F4 = F5 + F6 (independent)
    _ = c.sim_add_instruction(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = c.sim_add_instruction(&sim, makeArithInst(c.OP_ADDD, 4, 5, 6));

    _ = c.sim_run(&sim, 100);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(7.0, sim.fp_regs[4], 0.001);
}

test "DIV.D computes correctly" {
    // F1 = F2 / F3 where F2=10, F3=4 => 2.5
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 10.0);
    c.sim_set_reg(&sim, 3, 4.0);

    _ = c.sim_add_instruction(&sim, makeArithInst(c.OP_DIVD, 1, 2, 3));

    _ = c.sim_run(&sim, 200);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(2.5, sim.fp_regs[1], 0.001);
}
