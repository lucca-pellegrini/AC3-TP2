// SPDX-License-Identifier: MIT
// Zig test harness for the Tomasulo C simulator
const std = @import("std");
const testing = std.testing;

const c = @cImport({
    @cInclude("tomasulo.h");
    @cInclude("parser.h");
});

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

fn initSim(cfg: *c.TomasuloConfig) c.Simulator {
    var sim: c.Simulator = undefined;
    c.sim_init(&sim, cfg);
    return sim;
}

fn initDefaultSim() c.Simulator {
    var cfg = c.config_default();
    return initSim(&cfg);
}

fn initSimWith(
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

fn makeArithInst(op: c.Opcode, dest: c_int, src1: c_int, src2: c_int) c.Instruction {
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

fn makeMemInst(op: c.Opcode, dest: c_int, imm: c_int, base: c_int) c.Instruction {
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

fn addInst(sim: *c.Simulator, inst: c.Instruction) void {
    _ = c.sim_add_instruction(sim, inst);
}

fn runToCompletion(sim: *c.Simulator) c_int {
    return c.sim_run(sim, 500);
}

fn getInst(sim: *const c.Simulator, idx: usize) c.Instruction {
    return sim.instructions[idx];
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper function tests
// ═══════════════════════════════════════════════════════════════════════════

test "opcode_name returns correct strings" {
    try testing.expectEqualStrings("ADD.D", std.mem.span(c.opcode_name(c.OP_ADDD)));
    try testing.expectEqualStrings("SUB.D", std.mem.span(c.opcode_name(c.OP_SUBD)));
    try testing.expectEqualStrings("MUL.D", std.mem.span(c.opcode_name(c.OP_MULTD)));
    try testing.expectEqualStrings("DIV.D", std.mem.span(c.opcode_name(c.OP_DIVD)));
    try testing.expectEqualStrings("L.D", std.mem.span(c.opcode_name(c.OP_LD)));
    try testing.expectEqualStrings("S.D", std.mem.span(c.opcode_name(c.OP_SD)));
}

test "opcode_name returns ??? for invalid" {
    try testing.expectEqualStrings("???", std.mem.span(c.opcode_name(c.OP_COUNT)));
    try testing.expectEqualStrings("???", std.mem.span(c.opcode_name(99)));
}

test "opcode_from_str round-trip all variants" {
    const cases = [_]struct { name: [*:0]const u8, expected: c.Opcode }{
        .{ .name = "ADDD", .expected = c.OP_ADDD },
        .{ .name = "ADD.D", .expected = c.OP_ADDD },
        .{ .name = "addd", .expected = c.OP_ADDD }, // case-insensitive
        .{ .name = "add.d", .expected = c.OP_ADDD },
        .{ .name = "SUBD", .expected = c.OP_SUBD },
        .{ .name = "SUB.D", .expected = c.OP_SUBD },
        .{ .name = "MULTD", .expected = c.OP_MULTD },
        .{ .name = "MUL.D", .expected = c.OP_MULTD },
        .{ .name = "Multd", .expected = c.OP_MULTD }, // mixed case
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
    try testing.expectEqual(@as(c_uint, c.OP_COUNT), c.opcode_from_str("ADD"));
    try testing.expectEqual(@as(c_uint, c.OP_COUNT), c.opcode_from_str("MULTIPLY"));
    try testing.expectEqual(@as(c_uint, c.OP_COUNT), c.opcode_from_str("123"));
}

test "rob_state_name returns correct strings" {
    try testing.expectEqualStrings("Issue", std.mem.span(c.rob_state_name(c.ROB_ISSUE)));
    try testing.expectEqualStrings("Executing", std.mem.span(c.rob_state_name(c.ROB_EXECUTING)));
    try testing.expectEqualStrings("Write", std.mem.span(c.rob_state_name(c.ROB_WRITE_RESULT)));
    try testing.expectEqualStrings("Commit", std.mem.span(c.rob_state_name(c.ROB_COMMIT)));
}

test "rs_type_prefix returns correct strings" {
    try testing.expectEqualStrings("Add", std.mem.span(c.rs_type_prefix(c.RS_ADD)));
    try testing.expectEqualStrings("Mul", std.mem.span(c.rs_type_prefix(c.RS_MULT)));
    try testing.expectEqualStrings("Ld", std.mem.span(c.rs_type_prefix(c.RS_LOAD)));
    try testing.expectEqualStrings("St", std.mem.span(c.rs_type_prefix(c.RS_STORE)));
}

test "rs_clear preserves type and unit_id" {
    var rs: c.ReservationStation = undefined;
    rs.type = c.RS_MULT;
    rs.unit_id = 3;
    rs.busy = true;
    rs.Vj = 42.0;
    rs.Qj = 5;
    c.rs_clear(&rs);
    try testing.expectEqual(false, rs.busy);
    try testing.expectApproxEqAbs(0.0, rs.Vj, 0.001);
    try testing.expectEqual(@as(c_int, 0), rs.Qj);
    try testing.expectEqual(@as(c_uint, c.RS_MULT), rs.type);
    try testing.expectEqual(@as(c_int, 3), rs.unit_id);
}

test "config_default has reasonable values" {
    const cfg = c.config_default();
    try testing.expectEqual(@as(c_int, 2), cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 2), cfg.latency[c.OP_SUBD]);
    try testing.expectEqual(@as(c_int, 10), cfg.latency[c.OP_MULTD]);
    try testing.expectEqual(@as(c_int, 40), cfg.latency[c.OP_DIVD]);
    try testing.expectEqual(@as(c_int, 2), cfg.latency[c.OP_LD]);
    try testing.expectEqual(@as(c_int, 2), cfg.latency[c.OP_SD]);
    try testing.expectEqual(@as(c_int, 3), cfg.num_rs[c.RS_ADD]);
    try testing.expectEqual(@as(c_int, 2), cfg.num_rs[c.RS_MULT]);
    try testing.expectEqual(@as(c_int, 3), cfg.num_rs[c.RS_LOAD]);
    try testing.expectEqual(@as(c_int, 3), cfg.num_rs[c.RS_STORE]);
}

// ═══════════════════════════════════════════════════════════════════════════
// parse_register tests
// ═══════════════════════════════════════════════════════════════════════════

test "parse_register valid F registers" {
    try testing.expectEqual(@as(c_int, 0), c.parse_register("F0"));
    try testing.expectEqual(@as(c_int, 6), c.parse_register("F6"));
    try testing.expectEqual(@as(c_int, 31), c.parse_register("F31"));
    try testing.expectEqual(@as(c_int, 10), c.parse_register("F10"));
    try testing.expectEqual(@as(c_int, 0), c.parse_register("f0")); // lowercase
}

test "parse_register valid R registers" {
    try testing.expectEqual(@as(c_int, 0), c.parse_register("R0"));
    try testing.expectEqual(@as(c_int, 2), c.parse_register("R2"));
    try testing.expectEqual(@as(c_int, 31), c.parse_register("R31"));
    try testing.expectEqual(@as(c_int, 15), c.parse_register("r15")); // lowercase
}

test "parse_register invalid inputs" {
    try testing.expectEqual(@as(c_int, -1), c.parse_register("X5"));
    try testing.expectEqual(@as(c_int, -1), c.parse_register(""));
    try testing.expectEqual(@as(c_int, -1), c.parse_register("F99")); // out of range
    try testing.expectEqual(@as(c_int, -1), c.parse_register("F-1")); // negative
    try testing.expectEqual(@as(c_int, -1), c.parse_register("F")); // no number
    try testing.expectEqual(@as(c_int, -1), c.parse_register("123")); // no prefix
    try testing.expectEqual(@as(c_int, -1), c.parse_register("Fabc")); // non-numeric
}

// ═══════════════════════════════════════════════════════════════════════════
// sim_init tests
// ═══════════════════════════════════════════════════════════════════════════

test "sim_init creates correct number of RS with defaults" {
    var cfg = c.config_default();
    var sim: c.Simulator = undefined;
    c.sim_init(&sim, &cfg);
    // default: 3 Add + 2 Mult + 3 Load + 3 Store = 11
    try testing.expectEqual(@as(c_int, 11), sim.num_rs);
}

test "sim_init creates RS with custom counts" {
    const sim = initSimWith(1, 1, 0, 0);
    try testing.expectEqual(@as(c_int, 2), sim.num_rs);
    // First RS should be Add type, second should be Mult type
    try testing.expectEqual(@as(c_uint, c.RS_ADD), sim.rs[0].type);
    try testing.expectEqual(@as(c_uint, c.RS_MULT), sim.rs[1].type);
}

test "sim_init with only add RS" {
    const sim = initSimWith(5, 0, 0, 0);
    try testing.expectEqual(@as(c_int, 5), sim.num_rs);
    for (0..5) |i| {
        try testing.expectEqual(@as(c_uint, c.RS_ADD), sim.rs[i].type);
        try testing.expectEqual(@as(c_int, @intCast(i + 1)), sim.rs[i].unit_id);
    }
}

test "sim_init zeroes registers and RAT" {
    const sim = initDefaultSim();
    for (0..c.MAX_FP_REGISTERS) |i| {
        try testing.expectApproxEqAbs(0.0, sim.fp_regs[i], 0.001);
        try testing.expectEqual(@as(c_int, 0), sim.rat.Qi[i]);
    }
}

test "sim_init zeroes cycle and commit counters" {
    const sim = initDefaultSim();
    try testing.expectEqual(@as(c_int, 0), sim.cycle);
    try testing.expectEqual(@as(c_int, 0), sim.committed);
    try testing.expectEqual(@as(c_int, 0), sim.next_issue);
    try testing.expectEqual(@as(c_int, 0), sim.num_instructions);
}

// ═══════════════════════════════════════════════════════════════════════════
// sim_add_instruction and sim_set_reg tests
// ═══════════════════════════════════════════════════════════════════════════

test "sim_add_instruction increments count" {
    var sim = initDefaultSim();
    try testing.expectEqual(@as(c_int, 0), sim.num_instructions);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    try testing.expectEqual(@as(c_int, 1), sim.num_instructions);
    addInst(&sim, makeArithInst(c.OP_SUBD, 4, 5, 6));
    try testing.expectEqual(@as(c_int, 2), sim.num_instructions);
}

test "sim_add_instruction preserves fields" {
    var sim = initDefaultSim();
    addInst(&sim, makeArithInst(c.OP_MULTD, 10, 4, 6));
    const inst = getInst(&sim, 0);
    try testing.expectEqual(@as(c_uint, c.OP_MULTD), inst.op);
    try testing.expectEqual(@as(c_int, 10), inst.dest);
    try testing.expectEqual(@as(c_int, 4), inst.src1);
    try testing.expectEqual(@as(c_int, 6), inst.src2);
    // Timing fields should be zeroed
    try testing.expectEqual(@as(c_int, 0), inst.issue_cycle);
    try testing.expectEqual(@as(c_int, 0), inst.exec_start);
    try testing.expectEqual(@as(c_int, 0), inst.exec_end);
    try testing.expectEqual(@as(c_int, 0), inst.write_cycle);
}

test "sim_add_instruction returns false when full" {
    var sim = initDefaultSim();
    for (0..c.MAX_INSTRUCTIONS) |_| {
        try testing.expect(c.sim_add_instruction(&sim, makeArithInst(c.OP_ADDD, 0, 0, 0)));
    }
    // Now should fail
    try testing.expect(!c.sim_add_instruction(&sim, makeArithInst(c.OP_ADDD, 0, 0, 0)));
}

test "sim_set_reg sets and reads back" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 0, 1.5);
    c.sim_set_reg(&sim, 15, -3.14);
    c.sim_set_reg(&sim, 31, 999.0);
    try testing.expectApproxEqAbs(1.5, sim.fp_regs[0], 0.001);
    try testing.expectApproxEqAbs(-3.14, sim.fp_regs[15], 0.001);
    try testing.expectApproxEqAbs(999.0, sim.fp_regs[31], 0.001);
}

test "sim_set_reg ignores out-of-range indices" {
    var sim = initDefaultSim();
    // These should not crash
    c.sim_set_reg(&sim, -1, 100.0);
    c.sim_set_reg(&sim, 32, 100.0);
    c.sim_set_reg(&sim, 999, 100.0);
    // All registers should still be zero
    for (0..c.MAX_FP_REGISTERS) |i| {
        try testing.expectApproxEqAbs(0.0, sim.fp_regs[i], 0.001);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// sim_done and sim_step lifecycle tests
// ═══════════════════════════════════════════════════════════════════════════

test "sim_done is true with no instructions" {
    var sim = initDefaultSim();
    try testing.expect(c.sim_done(&sim));
}

test "sim_done is false with pending instructions" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    try testing.expect(!c.sim_done(&sim));
}

test "sim_step returns false when already done" {
    var sim = initDefaultSim();
    try testing.expect(!c.sim_step(&sim));
}

test "sim_step advances cycle counter" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = c.sim_step(&sim);
    try testing.expectEqual(@as(c_int, 1), sim.cycle);
    _ = c.sim_step(&sim);
    try testing.expectEqual(@as(c_int, 2), sim.cycle);
}

test "sim_run returns total cycles" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    const cycles = runToCompletion(&sim);
    try testing.expect(cycles > 0);
    try testing.expect(c.sim_done(&sim));
}

// ═══════════════════════════════════════════════════════════════════════════
// Single-instruction correctness (each opcode)
// ═══════════════════════════════════════════════════════════════════════════

test "single ADD.D" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 4, 2.0);
    c.sim_set_reg(&sim, 6, 10.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 8, 4, 6));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(12.0, sim.fp_regs[8], 0.001);
}

test "single SUB.D" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 4, 10.0);
    c.sim_set_reg(&sim, 6, 3.0);
    addInst(&sim, makeArithInst(c.OP_SUBD, 8, 4, 6));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(7.0, sim.fp_regs[8], 0.001);
}

test "single MUL.D" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 4, 3.0);
    c.sim_set_reg(&sim, 6, 7.0);
    addInst(&sim, makeArithInst(c.OP_MULTD, 8, 4, 6));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(21.0, sim.fp_regs[8], 0.001);
}

test "single DIV.D" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 10.0);
    c.sim_set_reg(&sim, 3, 4.0);
    addInst(&sim, makeArithInst(c.OP_DIVD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(2.5, sim.fp_regs[1], 0.001);
}

test "single L.D" {
    // L.D F6, 34(R2) where R2=100 => F6 = 34+100 = 134 (simulated)
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 100.0);
    addInst(&sim, makeMemInst(c.OP_LD, 6, 34, 2));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(134.0, sim.fp_regs[6], 0.001);
}

test "single S.D completes without deadlock" {
    // S.D F6, 0(R2) -- stores don't write registers
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 6, 42.0);
    c.sim_set_reg(&sim, 2, 100.0);
    addInst(&sim, makeMemInst(c.OP_SD, 6, 0, 2));
    const cycles = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expect(cycles < 20);
    // F6 should remain unchanged (SD doesn't modify registers)
    try testing.expectApproxEqAbs(42.0, sim.fp_regs[6], 0.001);
}

// ═══════════════════════════════════════════════════════════════════════════
// Pipeline timing correctness
// ═══════════════════════════════════════════════════════════════════════════

test "single ADD.D timing: issue=1, exec=2-3, write=4" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = runToCompletion(&sim);
    const inst = getInst(&sim, 0);
    try testing.expectEqual(@as(c_int, 1), inst.issue_cycle);
    try testing.expectEqual(@as(c_int, 2), inst.exec_start);
    try testing.expectEqual(@as(c_int, 3), inst.exec_end);
    try testing.expectEqual(@as(c_int, 4), inst.write_cycle);
}

test "single MUL.D timing with latency 4: issue=1, exec=2-5, write=6" {
    var cfg = c.config_default();
    cfg.latency[c.OP_MULTD] = 4;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_MULTD, 1, 2, 3));
    _ = runToCompletion(&sim);
    const inst = getInst(&sim, 0);
    try testing.expectEqual(@as(c_int, 1), inst.issue_cycle);
    try testing.expectEqual(@as(c_int, 2), inst.exec_start);
    try testing.expectEqual(@as(c_int, 5), inst.exec_end);
    try testing.expectEqual(@as(c_int, 6), inst.write_cycle);
}

test "single DIV.D timing with latency 40" {
    var cfg = c.config_default();
    cfg.latency[c.OP_DIVD] = 40;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 10.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_DIVD, 1, 2, 3));
    _ = runToCompletion(&sim);
    const inst = getInst(&sim, 0);
    try testing.expectEqual(@as(c_int, 1), inst.issue_cycle);
    try testing.expectEqual(@as(c_int, 2), inst.exec_start);
    try testing.expectEqual(@as(c_int, 41), inst.exec_end);
    try testing.expectEqual(@as(c_int, 42), inst.write_cycle);
}

test "two independent ADDs issue on consecutive cycles" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 5, 3.0);
    c.sim_set_reg(&sim, 6, 4.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 4, 5, 6));
    _ = runToCompletion(&sim);
    // Instruction 1: issue=1, exec=2-3, write=4
    try testing.expectEqual(@as(c_int, 1), getInst(&sim, 0).issue_cycle);
    // Instruction 2: issue=2, exec=3-4, write=5
    try testing.expectEqual(@as(c_int, 2), getInst(&sim, 1).issue_cycle);
    try testing.expectEqual(@as(c_int, 3), getInst(&sim, 1).exec_start);
    try testing.expectEqual(@as(c_int, 4), getInst(&sim, 1).exec_end);
}

test "single L.D timing: issue=1, exec=2-3, write=4" {
    var cfg = c.config_default();
    cfg.latency[c.OP_LD] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 100.0);
    addInst(&sim, makeMemInst(c.OP_LD, 6, 34, 2));
    _ = runToCompletion(&sim);
    const inst = getInst(&sim, 0);
    try testing.expectEqual(@as(c_int, 1), inst.issue_cycle);
    try testing.expectEqual(@as(c_int, 2), inst.exec_start);
    try testing.expectEqual(@as(c_int, 3), inst.exec_end);
    try testing.expectEqual(@as(c_int, 4), inst.write_cycle);
}

// ═══════════════════════════════════════════════════════════════════════════
// RAW hazard tests (Read-After-Write / true dependencies)
// ═══════════════════════════════════════════════════════════════════════════

test "RAW: ADD then MUL depending on ADD result" {
    // F8 = F4 + F6 (2+10=12), then F10 = F8 * F8 (12*12=144)
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 4, 2.0);
    c.sim_set_reg(&sim, 6, 10.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 8, 4, 6));
    addInst(&sim, makeArithInst(c.OP_MULTD, 10, 8, 8));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(12.0, sim.fp_regs[8], 0.001);
    try testing.expectApproxEqAbs(144.0, sim.fp_regs[10], 0.001);
}

test "RAW: three-instruction chain ADD->MUL->SUB" {
    // F8 = F4 + F6 (2+10=12)
    // F10 = F8 * F8 (144)
    // F12 = F10 - F4 (142)
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_SUBD] = 2;
    cfg.latency[c.OP_MULTD] = 4;
    cfg.num_rs[c.RS_ADD] = 1;
    cfg.num_rs[c.RS_MULT] = 1;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 4, 2.0);
    c.sim_set_reg(&sim, 6, 10.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 8, 4, 6));
    addInst(&sim, makeArithInst(c.OP_MULTD, 10, 8, 8));
    addInst(&sim, makeArithInst(c.OP_SUBD, 12, 10, 4));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(12.0, sim.fp_regs[8], 0.001);
    try testing.expectApproxEqAbs(144.0, sim.fp_regs[10], 0.001);
    try testing.expectApproxEqAbs(142.0, sim.fp_regs[12], 0.001);
}

test "RAW: four-instruction deep chain" {
    // F1 = F2 + F3 (1+2=3)
    // F4 = F1 * F5 (3*3=9)
    // F6 = F4 + F7 (9+4=13)
    // F8 = F6 * F9 (13*5=65)
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_MULTD] = 4;
    cfg.num_rs[c.RS_ADD] = 1;
    cfg.num_rs[c.RS_MULT] = 1;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 5, 3.0);
    c.sim_set_reg(&sim, 7, 4.0);
    c.sim_set_reg(&sim, 9, 5.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_MULTD, 4, 1, 5));
    addInst(&sim, makeArithInst(c.OP_ADDD, 6, 4, 7));
    addInst(&sim, makeArithInst(c.OP_MULTD, 8, 6, 9));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(9.0, sim.fp_regs[4], 0.001);
    try testing.expectApproxEqAbs(13.0, sim.fp_regs[6], 0.001);
    try testing.expectApproxEqAbs(65.0, sim.fp_regs[8], 0.001);
}

test "RAW: MUL waits for ADD result, does not execute early" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_MULTD] = 4;
    cfg.num_rs[c.RS_ADD] = 2;
    cfg.num_rs[c.RS_MULT] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 5.0);
    c.sim_set_reg(&sim, 3, 3.0);
    // F1 = F2 + F3 = 8
    // F4 = F1 * F2 = 40 (must wait for F1)
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_MULTD, 4, 1, 2));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(8.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(40.0, sim.fp_regs[4], 0.001);
    // MUL should start executing after ADD writes: ADD writes at cycle 4,
    // so MUL exec_start should be cycle 4 or later (gets value from CDB)
    try testing.expect(getInst(&sim, 1).exec_start >= 4);
}

test "RAW: both operands depend on different producers" {
    // F1 = F2 + F3 = 3
    // F4 = F5 + F6 = 9
    // F7 = F1 * F4 (must wait for both)
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_MULTD] = 4;
    cfg.num_rs[c.RS_ADD] = 2;
    cfg.num_rs[c.RS_MULT] = 1;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 5, 4.0);
    c.sim_set_reg(&sim, 6, 5.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 4, 5, 6));
    addInst(&sim, makeArithInst(c.OP_MULTD, 7, 1, 4));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(9.0, sim.fp_regs[4], 0.001);
    try testing.expectApproxEqAbs(27.0, sim.fp_regs[7], 0.001);
}

// ═══════════════════════════════════════════════════════════════════════════
// WAW hazard tests (Write-After-Write / output dependencies)
// ═══════════════════════════════════════════════════════════════════════════

test "WAW: two instructions write same register, last wins" {
    // F1 = F2 + F3 = 3
    // F1 = F4 + F5 = 9  (overwrites F1)
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 4, 4.0);
    c.sim_set_reg(&sim, 5, 5.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 4, 5));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    // The second write should prevail
    try testing.expectApproxEqAbs(9.0, sim.fp_regs[1], 0.001);
}

test "WAW: later slow instruction overwrites earlier fast instruction" {
    // F1 = F2 + F3 = 3 (ADD, 2 cycles)
    // F1 = F4 * F5 = 20 (MUL, 10 cycles -- finishes later)
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_MULTD] = 10;
    cfg.num_rs[c.RS_ADD] = 1;
    cfg.num_rs[c.RS_MULT] = 1;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 4, 4.0);
    c.sim_set_reg(&sim, 5, 5.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_MULTD, 1, 4, 5));
    _ = runToCompletion(&sim);
    // MUL commits last, so F1 = 20
    try testing.expectApproxEqAbs(20.0, sim.fp_regs[1], 0.001);
}

test "WAW: third instruction reads correct value from chain" {
    // F1 = F2 + F3 = 3
    // F1 = F4 + F5 = 9 (overwrites F1)
    // F6 = F1 + F7 should use the SECOND F1 = 9
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 3;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 4, 4.0);
    c.sim_set_reg(&sim, 5, 5.0);
    c.sim_set_reg(&sim, 7, 1.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 4, 5));
    addInst(&sim, makeArithInst(c.OP_ADDD, 6, 1, 7));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(9.0, sim.fp_regs[1], 0.001);
    // F6 should be 9 + 1 = 10 (using the second F1)
    try testing.expectApproxEqAbs(10.0, sim.fp_regs[6], 0.001);
}

// ═══════════════════════════════════════════════════════════════════════════
// Structural hazard tests (RS exhaustion)
// ═══════════════════════════════════════════════════════════════════════════

test "structural: 1 Add RS, 3 ADDs must serialize" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 1;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 1, 1.0);
    c.sim_set_reg(&sim, 2, 2.0);
    c.sim_set_reg(&sim, 3, 3.0);
    c.sim_set_reg(&sim, 5, 5.0);
    c.sim_set_reg(&sim, 7, 7.0);
    c.sim_set_reg(&sim, 9, 9.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 10, 1, 2));
    addInst(&sim, makeArithInst(c.OP_ADDD, 11, 3, 5));
    addInst(&sim, makeArithInst(c.OP_ADDD, 12, 7, 9));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[10], 0.001);
    try testing.expectApproxEqAbs(8.0, sim.fp_regs[11], 0.001);
    try testing.expectApproxEqAbs(16.0, sim.fp_regs[12], 0.001);
    // With 1 RS, each must fully complete before the next can issue
    // inst1: issue=1, write=4
    // inst2: issue=4, write=7 (earliest -- RS freed at cycle 4)
    // inst3: issue=7, write=10
    try testing.expectEqual(@as(c_int, 1), getInst(&sim, 0).issue_cycle);
    try testing.expectEqual(@as(c_int, 4), getInst(&sim, 1).issue_cycle);
    try testing.expectEqual(@as(c_int, 7), getInst(&sim, 2).issue_cycle);
}

test "structural: 2 Add RS, 2 ADDs can overlap" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 5, 3.0);
    c.sim_set_reg(&sim, 6, 4.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 4, 5, 6));
    _ = runToCompletion(&sim);
    // Both issue without stall
    try testing.expectEqual(@as(c_int, 1), getInst(&sim, 0).issue_cycle);
    try testing.expectEqual(@as(c_int, 2), getInst(&sim, 1).issue_cycle);
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(7.0, sim.fp_regs[4], 0.001);
}

test "structural: ADD and MUL use different RS types, no conflict" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_MULTD] = 4;
    cfg.num_rs[c.RS_ADD] = 1;
    cfg.num_rs[c.RS_MULT] = 1;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 5, 3.0);
    c.sim_set_reg(&sim, 6, 4.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_MULTD, 4, 5, 6));
    _ = runToCompletion(&sim);
    // Both should issue without stall (different RS types)
    try testing.expectEqual(@as(c_int, 1), getInst(&sim, 0).issue_cycle);
    try testing.expectEqual(@as(c_int, 2), getInst(&sim, 1).issue_cycle);
}

// ═══════════════════════════════════════════════════════════════════════════
// CDB contention tests (single bus)
// ═══════════════════════════════════════════════════════════════════════════

test "CDB: two instructions finish same cycle, only one writes per cycle" {
    // Two ADDs with 2 RS, both finish execution at the same time
    // Only one can write per cycle due to single CDB
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 5, 3.0);
    c.sim_set_reg(&sim, 6, 4.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 4, 5, 6));
    _ = runToCompletion(&sim);
    // inst1 exec_end=3, inst2 exec_end=4
    // inst1 writes cycle 4, inst2 writes cycle 5
    // Their write_cycles should differ by 1
    const w1 = getInst(&sim, 0).write_cycle;
    const w2 = getInst(&sim, 1).write_cycle;
    try testing.expect(w1 != w2);
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(7.0, sim.fp_regs[4], 0.001);
}

test "CDB: MUL and ADD finish at different times, no contention" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_MULTD] = 10;
    cfg.num_rs[c.RS_ADD] = 1;
    cfg.num_rs[c.RS_MULT] = 1;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 3.0);
    c.sim_set_reg(&sim, 3, 4.0);
    c.sim_set_reg(&sim, 5, 5.0);
    c.sim_set_reg(&sim, 6, 6.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_MULTD, 4, 5, 6));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(7.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(30.0, sim.fp_regs[4], 0.001);
    // ADD writes well before MUL, no contention
    try testing.expect(getInst(&sim, 0).write_cycle < getInst(&sim, 1).write_cycle);
}

// ═══════════════════════════════════════════════════════════════════════════
// Parallel execution tests
// ═══════════════════════════════════════════════════════════════════════════

test "parallel: independent ADD and MUL execute simultaneously" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_MULTD] = 4;
    cfg.num_rs[c.RS_ADD] = 1;
    cfg.num_rs[c.RS_MULT] = 1;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 2.0);
    c.sim_set_reg(&sim, 3, 3.0);
    c.sim_set_reg(&sim, 5, 5.0);
    c.sim_set_reg(&sim, 6, 6.0);
    // F1 = F2 + F3 (independent)
    // F4 = F5 * F6 (independent)
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_MULTD, 4, 5, 6));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(5.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(30.0, sim.fp_regs[4], 0.001);
    // Both should start executing without waiting
    try testing.expectEqual(@as(c_int, 2), getInst(&sim, 0).exec_start);
    try testing.expectEqual(@as(c_int, 3), getInst(&sim, 1).exec_start);
}

test "parallel: 4 independent ADDs with 3 RS, one stalls" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 3;
    var sim = initSim(&cfg);
    for (0..10) |i| {
        c.sim_set_reg(&sim, @intCast(i), @floatFromInt(i + 1));
    }
    addInst(&sim, makeArithInst(c.OP_ADDD, 10, 0, 1)); // F10 = F0 + F1
    addInst(&sim, makeArithInst(c.OP_ADDD, 11, 2, 3)); // F11 = F2 + F3
    addInst(&sim, makeArithInst(c.OP_ADDD, 12, 4, 5)); // F12 = F4 + F5
    addInst(&sim, makeArithInst(c.OP_ADDD, 13, 6, 7)); // F13 = F6 + F7 (stalls)
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[10], 0.001); // 1+2
    try testing.expectApproxEqAbs(7.0, sim.fp_regs[11], 0.001); // 3+4
    try testing.expectApproxEqAbs(11.0, sim.fp_regs[12], 0.001); // 5+6
    try testing.expectApproxEqAbs(15.0, sim.fp_regs[13], 0.001); // 7+8
    // First 3 issue on cycles 1,2,3; 4th must wait
    try testing.expectEqual(@as(c_int, 1), getInst(&sim, 0).issue_cycle);
    try testing.expectEqual(@as(c_int, 2), getInst(&sim, 1).issue_cycle);
    try testing.expectEqual(@as(c_int, 3), getInst(&sim, 2).issue_cycle);
    try testing.expect(getInst(&sim, 3).issue_cycle >= 4);
}

// ═══════════════════════════════════════════════════════════════════════════
// ROB ordering and in-order commit tests
// ═══════════════════════════════════════════════════════════════════════════

test "in-order commit: fast instruction after slow still commits in order" {
    // MUL.D (slow) then ADD.D (fast) -- ADD finishes first but must
    // wait for MUL to commit first
    var cfg = c.config_default();
    cfg.latency[c.OP_MULTD] = 10;
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 1;
    cfg.num_rs[c.RS_MULT] = 1;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 2.0);
    c.sim_set_reg(&sim, 3, 3.0);
    c.sim_set_reg(&sim, 5, 5.0);
    c.sim_set_reg(&sim, 6, 6.0);
    addInst(&sim, makeArithInst(c.OP_MULTD, 1, 2, 3)); // slow
    addInst(&sim, makeArithInst(c.OP_ADDD, 4, 5, 6)); // fast
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(6.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(11.0, sim.fp_regs[4], 0.001);
    // ADD writes before MUL
    try testing.expect(getInst(&sim, 1).write_cycle < getInst(&sim, 0).write_cycle);
}

// ═══════════════════════════════════════════════════════════════════════════
// Load/Store tests
// ═══════════════════════════════════════════════════════════════════════════

test "LD then ADD uses loaded value" {
    // L.D F6, 34(R2) where R2=100 => F6=134
    // ADD.D F1, F6, F3 where F3=10 => F1=144
    var cfg = c.config_default();
    cfg.latency[c.OP_LD] = 2;
    cfg.latency[c.OP_ADDD] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 100.0);
    c.sim_set_reg(&sim, 3, 10.0);
    addInst(&sim, makeMemInst(c.OP_LD, 6, 34, 2));
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 6, 3));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(134.0, sim.fp_regs[6], 0.001);
    try testing.expectApproxEqAbs(144.0, sim.fp_regs[1], 0.001);
}

test "multiple LDs in parallel with 3 load buffers" {
    var cfg = c.config_default();
    cfg.latency[c.OP_LD] = 2;
    cfg.num_rs[c.RS_LOAD] = 3;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 0, 0.0);
    addInst(&sim, makeMemInst(c.OP_LD, 1, 10, 0));
    addInst(&sim, makeMemInst(c.OP_LD, 2, 20, 0));
    addInst(&sim, makeMemInst(c.OP_LD, 3, 30, 0));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(10.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(20.0, sim.fp_regs[2], 0.001);
    try testing.expectApproxEqAbs(30.0, sim.fp_regs[3], 0.001);
}

test "SD after LD completes without deadlock" {
    // L.D F1, 0(R0) => F1 = 0+0 = 0
    // S.D F1, 0(R0) => store
    var cfg = c.config_default();
    cfg.latency[c.OP_LD] = 2;
    cfg.latency[c.OP_SD] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 0, 100.0);
    c.sim_set_reg(&sim, 1, 42.0);
    addInst(&sim, makeMemInst(c.OP_LD, 1, 10, 0));
    addInst(&sim, makeMemInst(c.OP_SD, 1, 20, 0));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
}

test "LD with zero offset" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 50.0);
    addInst(&sim, makeMemInst(c.OP_LD, 1, 0, 2));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(50.0, sim.fp_regs[1], 0.001);
}

// ═══════════════════════════════════════════════════════════════════════════
// Hennessy & Patterson textbook example
// ═══════════════════════════════════════════════════════════════════════════

test "Hennessy classic: L.D L.D MUL.D SUB.D DIV.D ADD.D" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_SUBD] = 2;
    cfg.latency[c.OP_MULTD] = 10;
    cfg.latency[c.OP_DIVD] = 40;
    cfg.latency[c.OP_LD] = 2;
    cfg.num_rs[c.RS_ADD] = 3;
    cfg.num_rs[c.RS_MULT] = 2;
    cfg.num_rs[c.RS_LOAD] = 3;
    cfg.num_rs[c.RS_STORE] = 3;
    var sim = initSim(&cfg);

    // Initial register values
    c.sim_set_reg(&sim, 0, 0.0);
    c.sim_set_reg(&sim, 2, 10.0);
    c.sim_set_reg(&sim, 4, 5.0);
    // R2=100, R3=200 (using FP regs for simulation)
    // Actually src1 for LD is base register
    // We use index 20 for "R2" and 21 for "R3" to avoid collision
    // But our register space is F0-F31, so let's use F20=100, F21=200

    // Actually the Hennessy example uses integer base registers.
    // In our simulator, R2/R3 map to indices 2,3 in the same register file.
    // To avoid collision with F2 (which gets overwritten by L.D F2),
    // we'll set things up carefully.

    // Set base registers (will be read before F2 gets renamed)
    c.sim_set_reg(&sim, 2, 100.0); // "R2" base
    c.sim_set_reg(&sim, 3, 200.0); // "R3" base
    c.sim_set_reg(&sim, 4, 5.0);

    // L.D F6, 34(R2)  => F6 = 34 + 100 = 134
    addInst(&sim, makeMemInst(c.OP_LD, 6, 34, 2));
    // L.D F2, 45(R3)  => F2 = 45 + 200 = 245
    addInst(&sim, makeMemInst(c.OP_LD, 2, 45, 3));
    // MUL.D F0, F2, F4 => F0 = 245 * 5 = 1225
    addInst(&sim, makeArithInst(c.OP_MULTD, 0, 2, 4));
    // SUB.D F8, F6, F2 => F8 = 134 - 245 = -111
    addInst(&sim, makeArithInst(c.OP_SUBD, 8, 6, 2));
    // DIV.D F10, F0, F6 => F10 = 1225 / 134 = ~9.1418
    addInst(&sim, makeArithInst(c.OP_DIVD, 10, 0, 6));
    // ADD.D F6, F8, F2 => F6 = -111 + 245 = 134
    addInst(&sim, makeArithInst(c.OP_ADDD, 6, 8, 2));

    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));

    try testing.expectApproxEqAbs(1225.0, sim.fp_regs[0], 0.01);
    try testing.expectApproxEqAbs(245.0, sim.fp_regs[2], 0.01);
    try testing.expectApproxEqAbs(134.0, sim.fp_regs[6], 0.01); // overwritten by ADD.D
    try testing.expectApproxEqAbs(-111.0, sim.fp_regs[8], 0.01);
    try testing.expectApproxEqAbs(1225.0 / 134.0, sim.fp_regs[10], 0.01);
}

// ═══════════════════════════════════════════════════════════════════════════
// Edge case tests
// ═══════════════════════════════════════════════════════════════════════════

test "divide by zero returns 0" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 10.0);
    c.sim_set_reg(&sim, 3, 0.0);
    addInst(&sim, makeArithInst(c.OP_DIVD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(0.0, sim.fp_regs[1], 0.001);
}

test "negative operands" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, -5.0);
    c.sim_set_reg(&sim, 3, 3.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(-2.0, sim.fp_regs[1], 0.001);
}

test "SUB.D with negative result" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 3.0);
    c.sim_set_reg(&sim, 3, 10.0);
    addInst(&sim, makeArithInst(c.OP_SUBD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(-7.0, sim.fp_regs[1], 0.001);
}

test "MUL.D with zero" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 0.0);
    c.sim_set_reg(&sim, 3, 999.0);
    addInst(&sim, makeArithInst(c.OP_MULTD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(0.0, sim.fp_regs[1], 0.001);
}

test "ADD.D with zero operands" {
    var sim = initDefaultSim();
    // Both regs are 0 by default
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(0.0, sim.fp_regs[1], 0.001);
}

test "self-referencing: F1 = F1 + F1" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 1, 5.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 1, 1));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(10.0, sim.fp_regs[1], 0.001);
}

test "large number of independent instructions" {
    // 16 independent ADDs: F(i+16) = Fi + F(i+1)
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 3;
    var sim = initSim(&cfg);
    for (0..16) |i| {
        c.sim_set_reg(&sim, @intCast(i), @as(f64, @floatFromInt(i + 1)));
    }
    for (0..8) |i| {
        const dest: c_int = @intCast(i + 16);
        const src1: c_int = @intCast(i * 2);
        const src2: c_int = @intCast(i * 2 + 1);
        addInst(&sim, makeArithInst(c.OP_ADDD, dest, src1, src2));
    }
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    // F16 = F0+F1 = 1+2 = 3
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[16], 0.001);
    // F17 = F2+F3 = 3+4 = 7
    try testing.expectApproxEqAbs(7.0, sim.fp_regs[17], 0.001);
    // F18 = F4+F5 = 5+6 = 11
    try testing.expectApproxEqAbs(11.0, sim.fp_regs[18], 0.001);
}

test "sim_run respects max_cycles limit" {
    var cfg = c.config_default();
    cfg.latency[c.OP_DIVD] = 40;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 10.0);
    c.sim_set_reg(&sim, 3, 3.0);
    addInst(&sim, makeArithInst(c.OP_DIVD, 1, 2, 3));
    const cycles = c.sim_run(&sim, 5);
    try testing.expectEqual(@as(c_int, 5), cycles);
    try testing.expect(!c.sim_done(&sim));
}

test "floating point precision with small values" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 0.1);
    c.sim_set_reg(&sim, 3, 0.2);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(0.3, sim.fp_regs[1], 0.0001);
}

test "mixed operations: ADD, SUB, MUL, DIV all in one program" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_SUBD] = 2;
    cfg.latency[c.OP_MULTD] = 4;
    cfg.latency[c.OP_DIVD] = 10;
    cfg.num_rs[c.RS_ADD] = 2;
    cfg.num_rs[c.RS_MULT] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 0, 10.0);
    c.sim_set_reg(&sim, 1, 3.0);
    c.sim_set_reg(&sim, 2, 5.0);
    c.sim_set_reg(&sim, 3, 2.0);
    // F4 = F0 + F1 = 13
    addInst(&sim, makeArithInst(c.OP_ADDD, 4, 0, 1));
    // F5 = F0 - F2 = 5
    addInst(&sim, makeArithInst(c.OP_SUBD, 5, 0, 2));
    // F6 = F4 * F5 = 65 (depends on F4, F5)
    addInst(&sim, makeArithInst(c.OP_MULTD, 6, 4, 5));
    // F7 = F6 / F3 = 32.5 (depends on F6)
    addInst(&sim, makeArithInst(c.OP_DIVD, 7, 6, 3));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(13.0, sim.fp_regs[4], 0.001);
    try testing.expectApproxEqAbs(5.0, sim.fp_regs[5], 0.001);
    try testing.expectApproxEqAbs(65.0, sim.fp_regs[6], 0.001);
    try testing.expectApproxEqAbs(32.5, sim.fp_regs[7], 0.001);
}

test "custom latencies: latency 1 for ADD" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 1;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 3.0);
    c.sim_set_reg(&sim, 3, 4.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = runToCompletion(&sim);
    const inst = getInst(&sim, 0);
    try testing.expectEqual(@as(c_int, 1), inst.issue_cycle);
    try testing.expectEqual(@as(c_int, 2), inst.exec_start);
    try testing.expectEqual(@as(c_int, 2), inst.exec_end); // 1 cycle execution
    try testing.expectEqual(@as(c_int, 3), inst.write_cycle);
    try testing.expectApproxEqAbs(7.0, sim.fp_regs[1], 0.001);
}

// ═══════════════════════════════════════════════════════════════════════════
// File parser integration tests
// ═══════════════════════════════════════════════════════════════════════════

test "parse_input loads basic test file" {
    var cfg: c.TomasuloConfig = undefined;
    var sim: c.Simulator = undefined;
    const result = c.parse_input("tests/input_basic.tom", &cfg, &sim);
    try testing.expectEqual(@as(c_int, 0), result);
    try testing.expectEqual(@as(c_int, 3), sim.num_instructions);
    // Check config was parsed
    try testing.expectEqual(@as(c_int, 2), cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 4), cfg.latency[c.OP_MULTD]);
    // Check register init
    try testing.expectApproxEqAbs(2.0, sim.fp_regs[4], 0.001);
    try testing.expectApproxEqAbs(10.0, sim.fp_regs[6], 0.001);
    // Run and verify results
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(12.0, sim.fp_regs[8], 0.001);
    try testing.expectApproxEqAbs(144.0, sim.fp_regs[10], 0.001);
    try testing.expectApproxEqAbs(142.0, sim.fp_regs[12], 0.001);
}

test "parse_input loads chain test file" {
    var cfg: c.TomasuloConfig = undefined;
    var sim: c.Simulator = undefined;
    const result = c.parse_input("tests/input_chain.tom", &cfg, &sim);
    try testing.expectEqual(@as(c_int, 0), result);
    try testing.expectEqual(@as(c_int, 4), sim.num_instructions);
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(9.0, sim.fp_regs[4], 0.001);
    try testing.expectApproxEqAbs(13.0, sim.fp_regs[6], 0.001);
    try testing.expectApproxEqAbs(65.0, sim.fp_regs[8], 0.001);
}

test "parse_input loads parallel test file" {
    var cfg: c.TomasuloConfig = undefined;
    var sim: c.Simulator = undefined;
    const result = c.parse_input("tests/input_parallel.tom", &cfg, &sim);
    try testing.expectEqual(@as(c_int, 0), result);
    try testing.expectEqual(@as(c_int, 4), sim.num_instructions);
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(7.0, sim.fp_regs[4], 0.001);
    try testing.expectApproxEqAbs(21.0, sim.fp_regs[7], 0.001);
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[8], 0.001);
}

test "parse_input loads Hennessy test file" {
    var cfg: c.TomasuloConfig = undefined;
    var sim: c.Simulator = undefined;
    const result = c.parse_input("tests/input_hennessy.tom", &cfg, &sim);
    try testing.expectEqual(@as(c_int, 0), result);
    try testing.expectEqual(@as(c_int, 6), sim.num_instructions);
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(1225.0, sim.fp_regs[0], 0.01);
    try testing.expectApproxEqAbs(-111.0, sim.fp_regs[8], 0.01);
}

test "parse_input loads structural hazard test file" {
    var cfg: c.TomasuloConfig = undefined;
    var sim: c.Simulator = undefined;
    const result = c.parse_input("tests/input_structural.tom", &cfg, &sim);
    try testing.expectEqual(@as(c_int, 0), result);
    try testing.expectEqual(@as(c_int, 3), sim.num_instructions);
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[10], 0.001);
    try testing.expectApproxEqAbs(8.0, sim.fp_regs[11], 0.001);
    try testing.expectApproxEqAbs(16.0, sim.fp_regs[12], 0.001);
}

test "parse_input returns error for nonexistent file" {
    var cfg: c.TomasuloConfig = undefined;
    var sim: c.Simulator = undefined;
    // Temporarily redirect stderr (fd 2) to /dev/null so the parser's
    // expected error message doesn't pollute test output.
    const c_stdio = @cImport({
        @cInclude("stdio.h");
        @cInclude("unistd.h");
        @cInclude("fcntl.h");
    });
    const saved_stderr = c_stdio.dup(2);
    const devnull = c_stdio.open("/dev/null", c_stdio.O_WRONLY);
    if (devnull >= 0) {
        _ = c_stdio.dup2(devnull, 2);
        _ = c_stdio.close(devnull);
    }
    defer {
        if (saved_stderr >= 0) {
            _ = c_stdio.dup2(saved_stderr, 2);
            _ = c_stdio.close(saved_stderr);
        }
    }
    const result = c.parse_input("nonexistent_file.tom", &cfg, &sim);
    try testing.expect(result != 0);
}

// ═══════════════════════════════════════════════════════════════════════════
// Complex scenario tests
// ═══════════════════════════════════════════════════════════════════════════

test "WAR: write-after-read does not cause incorrect results" {
    // F1 = F2 + F3 (reads F2)
    // F2 = F4 + F5 (writes F2 -- WAR hazard with inst 1)
    // F6 = F2 + F3 (should read the NEW F2)
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 3;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 10.0);
    c.sim_set_reg(&sim, 3, 5.0);
    c.sim_set_reg(&sim, 4, 20.0);
    c.sim_set_reg(&sim, 5, 30.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3)); // F1 = 10+5 = 15
    addInst(&sim, makeArithInst(c.OP_ADDD, 2, 4, 5)); // F2 = 20+30 = 50
    addInst(&sim, makeArithInst(c.OP_ADDD, 6, 2, 3)); // F6 = 50+5 = 55
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(15.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(50.0, sim.fp_regs[2], 0.001);
    try testing.expectApproxEqAbs(55.0, sim.fp_regs[6], 0.001);
}

test "LD feeds MUL feeds ADD chain" {
    // L.D F1, 10(R0) => F1 = 10 + base
    // MUL.D F2, F1, F3 => F2 = F1 * F3
    // ADD.D F4, F2, F5 => F4 = F2 + F5
    var cfg = c.config_default();
    cfg.latency[c.OP_LD] = 2;
    cfg.latency[c.OP_MULTD] = 4;
    cfg.latency[c.OP_ADDD] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 0, 100.0); // base
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 5, 10.0);
    addInst(&sim, makeMemInst(c.OP_LD, 1, 10, 0)); // F1 = 10+100 = 110
    addInst(&sim, makeArithInst(c.OP_MULTD, 2, 1, 3)); // F2 = 110*2 = 220
    addInst(&sim, makeArithInst(c.OP_ADDD, 4, 2, 5)); // F4 = 220+10 = 230
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(110.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(220.0, sim.fp_regs[2], 0.001);
    try testing.expectApproxEqAbs(230.0, sim.fp_regs[4], 0.001);
}

test "register F0 can be used as source and destination" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 0, 7.0);
    c.sim_set_reg(&sim, 1, 3.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 0, 0, 1)); // F0 = F0 + F1 = 10
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(10.0, sim.fp_regs[0], 0.001);
}

test "multiple writes to same register in sequence produce correct final value" {
    // F1 = F2 + F3 = 5
    // F1 = F4 + F5 = 11
    // F1 = F6 + F7 = 17
    // Final F1 should be 17
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 3;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 2.0);
    c.sim_set_reg(&sim, 3, 3.0);
    c.sim_set_reg(&sim, 4, 5.0);
    c.sim_set_reg(&sim, 5, 6.0);
    c.sim_set_reg(&sim, 6, 8.0);
    c.sim_set_reg(&sim, 7, 9.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 4, 5));
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 6, 7));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(17.0, sim.fp_regs[1], 0.001);
}

test "back-to-back dependent ADDs with minimal latency" {
    // F1 = F0 + F0 = 2
    // F2 = F1 + F0 = 3
    // F3 = F2 + F0 = 4
    // F4 = F3 + F0 = 5
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 1;
    cfg.num_rs[c.RS_ADD] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 0, 1.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 0, 0));
    addInst(&sim, makeArithInst(c.OP_ADDD, 2, 1, 0));
    addInst(&sim, makeArithInst(c.OP_ADDD, 3, 2, 0));
    addInst(&sim, makeArithInst(c.OP_ADDD, 4, 3, 0));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(2.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[2], 0.001);
    try testing.expectApproxEqAbs(4.0, sim.fp_regs[3], 0.001);
    try testing.expectApproxEqAbs(5.0, sim.fp_regs[4], 0.001);
}

// ═══════════════════════════════════════════════════════════════════════════
// Parser syntax tests
//
// These exercise the flex/bison front-end directly by writing tiny
// input fragments to a tmp file and feeding them to parse_input().
// They cover the surface area of the new C-like grammar: block
// keywords, brace/comma/semicolon separators, '=' assignments,
// comment styles, opcode/key spelling normalisation (case, '.', '_'),
// memory operand forms, and a handful of error cases.
// ═══════════════════════════════════════════════════════════════════════════

// ── Helpers ────────────────────────────────────────────────────────────────

const c_io = @cImport({
    @cInclude("stdio.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
});

// Write `text` to a freshly-created temp file via libc and return its
// NUL-terminated path.  Caller frees with `freeTmpPath()`.
//
// We bypass std.Io here because Zig 0.16's tmpDir/writeFile dance got
// thorny (writeFile now requires an Io param, realpathAlloc moved).
// libc's mkstemp/write is dead simple and we already link libc.
fn makeTmpFile(text: []const u8) ![:0]u8 {
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

fn freeTmpPath(path: [:0]u8) void {
    _ = c_io.unlink(path.ptr);
    testing.allocator.free(path);
}

// Write `text`, parse it, return cfg+sim+path.  Asserts parse succeeds.
fn parseSource(text: []const u8) !struct {
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

fn freeParse(p: anytype) void {
    freeTmpPath(p.path);
}

// Parse and expect a parse error.  Suppresses the parser's stderr
// chatter so test output stays clean.
fn parseExpectFail(text: []const u8) !void {
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

// ── Smoke: minimal program ─────────────────────────────────────────────────

test "parser: minimal program (only instructions block)" {
    const src =
        \\instructions {
        \\    ADDD F1 F2 F3
        \\}
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 1), p.sim.num_instructions);
    try testing.expectEqual(@as(c_uint, c.OP_ADDD), p.sim.instructions[0].op);
    try testing.expectEqual(@as(c_int, 1), p.sim.instructions[0].dest);
    try testing.expectEqual(@as(c_int, 2), p.sim.instructions[0].src1);
    try testing.expectEqual(@as(c_int, 3), p.sim.instructions[0].src2);
}

test "parser: empty instructions block parses" {
    const src = "instructions {}";
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 0), p.sim.num_instructions);
}

test "parser: empty file is accepted (defaults apply)" {
    const src = "";
    const p = try parseSource(src);
    defer freeParse(p);
    // Defaults from config_default() should be in effect.
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 0), p.sim.num_instructions);
}

// ── Block keyword: case + punctuation flexibility ──────────────────────────

test "parser: block keywords are case-insensitive" {
    const src =
        \\CYCLES { add.d = 3 }
        \\Units { mult.d = 2 }
        \\Registers { F1 = 1.5 }
        \\INSTRUCTIONS { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 3), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 2), p.cfg.num_rs[c.RS_MULT]);
    try testing.expectApproxEqAbs(1.5, p.sim.fp_regs[1], 0.001);
    try testing.expectEqual(@as(c_int, 1), p.sim.num_instructions);
}

test "parser: reg_init is an alias for registers" {
    const src =
        \\reg_init { F4 = 2.5 }
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectApproxEqAbs(2.5, p.sim.fp_regs[4], 0.001);
}

test "parser: mem_units is an alias for units" {
    const src =
        \\mem_units { l.d = 4, s.d = 2 }
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 4), p.cfg.num_rs[c.RS_LOAD]);
    try testing.expectEqual(@as(c_int, 2), p.cfg.num_rs[c.RS_STORE]);
}

// ── Opcode/key spelling normalisation ──────────────────────────────────────

test "parser: opcode keys accept '.', '_', or no separator" {
    const src =
        \\cycles {
        \\    add.d  = 2
        \\    SUB_D  = 3
        \\    MultD  = 5
        \\    div.d  = 7
        \\    L_D    = 11
        \\    sd     = 13
        \\}
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 3), p.cfg.latency[c.OP_SUBD]);
    try testing.expectEqual(@as(c_int, 5), p.cfg.latency[c.OP_MULTD]);
    try testing.expectEqual(@as(c_int, 7), p.cfg.latency[c.OP_DIVD]);
    try testing.expectEqual(@as(c_int, 11), p.cfg.latency[c.OP_LD]);
    try testing.expectEqual(@as(c_int, 13), p.cfg.latency[c.OP_SD]);
}

test "parser: instruction opcodes accept mixed spellings" {
    const src =
        \\instructions {
        \\    add.d  F1 F2 F3
        \\    SUB_D  F4 F2 F3
        \\    MultD  F5 F2 F3
        \\    div_d  F6 F2 F3
        \\}
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 4), p.sim.num_instructions);
    try testing.expectEqual(@as(c_uint, c.OP_ADDD), p.sim.instructions[0].op);
    try testing.expectEqual(@as(c_uint, c.OP_SUBD), p.sim.instructions[1].op);
    try testing.expectEqual(@as(c_uint, c.OP_MULTD), p.sim.instructions[2].op);
    try testing.expectEqual(@as(c_uint, c.OP_DIVD), p.sim.instructions[3].op);
}

// ── Block ordering ─────────────────────────────────────────────────────────

test "parser: block order is flexible (instructions first)" {
    const src =
        \\instructions { ADDD F1 F2 F3 }
        \\cycles { add.d = 5 }
        \\registers { F2 = 7.0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 1), p.sim.num_instructions);
    try testing.expectEqual(@as(c_int, 5), p.cfg.latency[c.OP_ADDD]);
    // Note: registers block after instructions still sets the register.
    try testing.expectApproxEqAbs(7.0, p.sim.fp_regs[2], 0.001);
}

test "parser: same block can appear twice (later wins)" {
    const src =
        \\cycles { add.d = 2 }
        \\cycles { add.d = 9 }
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 9), p.cfg.latency[c.OP_ADDD]);
}

// ── Separators (commas, semicolons, newlines) ──────────────────────────────

test "parser: items can be comma-separated on one line" {
    const src =
        \\cycles { add.d = 2, mult.d = 4, div.d = 8 }
        \\units  { add.d = 1, mult.d = 1 }
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 4), p.cfg.latency[c.OP_MULTD]);
    try testing.expectEqual(@as(c_int, 8), p.cfg.latency[c.OP_DIVD]);
}

test "parser: semicolons work as item separators" {
    const src =
        \\cycles { add.d = 2; mult.d = 4; }
        \\instructions { ADDD F0 F0 F0; }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 4), p.cfg.latency[c.OP_MULTD]);
    try testing.expectEqual(@as(c_int, 1), p.sim.num_instructions);
}

test "parser: extra commas and whitespace are tolerated" {
    const src =
        \\cycles {,,, add.d = 2,,, mult.d = 4 ,,,}
        \\instructions {  ADDD  F0  F0  F0  }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
}

// ── Comments ───────────────────────────────────────────────────────────────

test "parser: '#' comments are stripped" {
    const src =
        \\# top-level comment
        \\cycles {
        \\    add.d = 2  # trailing comment
        \\    # comment in the middle
        \\    mult.d = 4
        \\}
        \\instructions { ADDD F0 F0 F0 }  # comment after block
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 4), p.cfg.latency[c.OP_MULTD]);
}

test "parser: '//' comments are stripped" {
    const src =
        \\// like C
        \\cycles { add.d = 2 } // trailing
        \\instructions { ADDD F0 F0 F0 // comment inside block
        \\}
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 1), p.sim.num_instructions);
}

// ── Memory operand forms ───────────────────────────────────────────────────

test "parser: L.D with bare 'offset base' form" {
    const src =
        \\registers { R1 = 100 }
        \\instructions { L.D F2 8 R1 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    const inst = p.sim.instructions[0];
    try testing.expectEqual(@as(c_uint, c.OP_LD), inst.op);
    try testing.expectEqual(@as(c_int, 2), inst.dest);
    try testing.expectEqual(@as(c_int, 1), inst.src1); // R1
    try testing.expectEqual(@as(c_int, 8), inst.imm);
}

test "parser: L.D with C-like 'offset(base)' form" {
    const src =
        \\registers { R1 = 100 }
        \\instructions { L.D F2 8(R1) }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    const inst = p.sim.instructions[0];
    try testing.expectEqual(@as(c_uint, c.OP_LD), inst.op);
    try testing.expectEqual(@as(c_int, 2), inst.dest);
    try testing.expectEqual(@as(c_int, 1), inst.src1);
    try testing.expectEqual(@as(c_int, 8), inst.imm);
}

test "parser: both LD forms produce identical instruction" {
    const src1 =
        \\instructions { L.D F2 16 R1 }
    ;
    const src2 =
        \\instructions { L.D F2 16(R1) }
    ;
    const p1 = try parseSource(src1);
    defer freeParse(p1);
    const p2 = try parseSource(src2);
    defer freeParse(p2);
    try testing.expectEqual(p1.sim.instructions[0].op, p2.sim.instructions[0].op);
    try testing.expectEqual(p1.sim.instructions[0].dest, p2.sim.instructions[0].dest);
    try testing.expectEqual(p1.sim.instructions[0].src1, p2.sim.instructions[0].src1);
    try testing.expectEqual(p1.sim.instructions[0].imm, p2.sim.instructions[0].imm);
}

test "parser: S.D with offset(base) form" {
    const src =
        \\instructions { S.D F8 0(R3) }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    const inst = p.sim.instructions[0];
    try testing.expectEqual(@as(c_uint, c.OP_SD), inst.op);
    try testing.expectEqual(@as(c_int, 8), inst.dest);
    try testing.expectEqual(@as(c_int, 3), inst.src1);
    try testing.expectEqual(@as(c_int, 0), inst.imm);
}

test "parser: negative offset on memory instruction" {
    const src =
        \\instructions { L.D F2 -16(R1) }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, -16), p.sim.instructions[0].imm);
}

// ── Register init: numeric forms ───────────────────────────────────────────

test "parser: register init accepts int, float and exponent" {
    const src =
        \\registers {
        \\    F1 = 42
        \\    F2 = 3.14
        \\    F3 = -2.5
        \\    F4 = 1.5e2
        \\    F5 = -1e-3
        \\}
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectApproxEqAbs(42.0, p.sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(3.14, p.sim.fp_regs[2], 0.001);
    try testing.expectApproxEqAbs(-2.5, p.sim.fp_regs[3], 0.001);
    try testing.expectApproxEqAbs(150.0, p.sim.fp_regs[4], 0.001);
    try testing.expectApproxEqAbs(-0.001, p.sim.fp_regs[5], 1e-6);
}

test "parser: F and R registers share the same index space" {
    // R1 and F1 should refer to the same physical register.
    const src =
        \\registers { R1 = 7.0 }
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectApproxEqAbs(7.0, p.sim.fp_regs[1], 0.001);
}

// ── End-to-end: parse + run ────────────────────────────────────────────────

test "parser: full program parses and simulates correctly" {
    const src =
        \\cycles { add.d = 2, mult.d = 4 }
        \\units  { add.d = 1, mult.d = 1 }
        \\registers { F4 = 2.0, F6 = 10.0 }
        \\instructions {
        \\    ADDD  F8  F4 F6     # F8  = 12
        \\    MULTD F10 F8 F8     # F10 = 144
        \\}
    ;
    var p = try parseSource(src);
    defer freeParse(p);
    _ = runToCompletion(&p.sim);
    try testing.expect(c.sim_done(&p.sim));
    try testing.expectApproxEqAbs(12.0, p.sim.fp_regs[8], 0.001);
    try testing.expectApproxEqAbs(144.0, p.sim.fp_regs[10], 0.001);
}

// ── Error cases ────────────────────────────────────────────────────────────

test "parser: unknown opcode rejected" {
    try parseExpectFail(
        \\instructions { FROB F1 F2 F3 }
    );
}

test "parser: unknown block keyword rejected" {
    try parseExpectFail(
        \\widgets { foo = 1 }
        \\instructions { ADDD F0 F0 F0 }
    );
}

test "parser: missing closing brace rejected" {
    try parseExpectFail(
        \\cycles { add.d = 2
        \\instructions { ADDD F0 F0 F0 }
    );
}

test "parser: register out of range rejected" {
    try parseExpectFail(
        \\instructions { ADDD F99 F0 F0 }
    );
}

test "parser: arithmetic opcode with offset form rejected" {
    try parseExpectFail(
        \\instructions { ADDD F1 0(R2) }
    );
}

test "parser: memory opcode with three register form rejected" {
    try parseExpectFail(
        \\instructions { L.D F1 F2 F3 }
    );
}

test "parser: missing '=' in config item rejected" {
    try parseExpectFail(
        \\cycles { add.d 2 }
        \\instructions { ADDD F0 F0 F0 }
    );
}
