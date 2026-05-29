// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! Tests for sim_init, sim_add_instruction, sim_set_reg, sim_done, sim_step lifecycle.

const common = @import("common.zig");
const testing = common.testing;
const c = common.c;

const initSim = common.initSim;
const initDefaultSim = common.initDefaultSim;
const initSimWith = common.initSimWith;
const makeArithInst = common.makeArithInst;
const addInst = common.addInst;
const runToCompletion = common.runToCompletion;

// ═══════════════════════════════════════════════════════════════════════════
// sim_init tests
// ═══════════════════════════════════════════════════════════════════════════

test "simulator: sim_init creates correct number of RS with defaults" {
    var cfg = c.config_default();
    var sim: c.Simulator = undefined;
    c.sim_init(&sim, &cfg);
    // default: 3 Add + 2 Mult + 3 Load + 3 Store = 11
    try testing.expectEqual(@as(c_int, 11), sim.num_rs);
}

test "simulator: sim_init creates RS with custom counts" {
    const sim = initSimWith(1, 1, 0, 0);
    try testing.expectEqual(@as(c_int, 2), sim.num_rs);
    // First RS should be Add type, second should be Mult type
    try testing.expectEqual(@as(c_uint, c.RS_ADD), sim.rs[0].type);
    try testing.expectEqual(@as(c_uint, c.RS_MULT), sim.rs[1].type);
}

test "simulator: sim_init with only add RS" {
    const sim = initSimWith(5, 0, 0, 0);
    try testing.expectEqual(@as(c_int, 5), sim.num_rs);
    for (0..5) |i| {
        try testing.expectEqual(@as(c_uint, c.RS_ADD), sim.rs[i].type);
        try testing.expectEqual(@as(c_int, @intCast(i + 1)), sim.rs[i].unit_id);
    }
}

test "simulator: sim_init zeroes registers and RAT" {
    const sim = initDefaultSim();
    for (0..c.MAX_FP_REGISTERS) |i| {
        try testing.expectApproxEqAbs(0.0, sim.fp_regs[i], 0.001);
        try testing.expectEqual(@as(c_int, 0), sim.rat.Qi[i]);
    }
}

test "simulator: sim_init zeroes cycle and commit counters" {
    const sim = initDefaultSim();
    try testing.expectEqual(@as(c_int, 0), sim.cycle);
    try testing.expectEqual(@as(c_int, 0), sim.committed);
    try testing.expectEqual(@as(c_int, 0), sim.next_issue);
    try testing.expectEqual(@as(c_int, 0), sim.num_instructions);
}

// ═══════════════════════════════════════════════════════════════════════════
// sim_add_instruction and sim_set_reg tests
// ═══════════════════════════════════════════════════════════════════════════

test "simulator: sim_add_instruction increments count" {
    var sim = initDefaultSim();
    try testing.expectEqual(@as(c_int, 0), sim.num_instructions);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    try testing.expectEqual(@as(c_int, 1), sim.num_instructions);
    addInst(&sim, makeArithInst(c.OP_SUBD, 4, 5, 6));
    try testing.expectEqual(@as(c_int, 2), sim.num_instructions);
}

test "simulator: sim_add_instruction preserves fields" {
    var sim = initDefaultSim();
    addInst(&sim, makeArithInst(c.OP_MULTD, 10, 4, 6));
    const inst = common.getInst(&sim, 0);
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

test "simulator: sim_add_instruction returns false when full" {
    var sim = initDefaultSim();
    for (0..c.MAX_INSTRUCTIONS) |_| {
        try testing.expect(c.sim_add_instruction(&sim, makeArithInst(c.OP_ADDD, 0, 0, 0)));
    }
    // Now should fail
    try testing.expect(!c.sim_add_instruction(&sim, makeArithInst(c.OP_ADDD, 0, 0, 0)));
}

test "simulator: sim_set_reg sets and reads back" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 0, 1.5);
    c.sim_set_reg(&sim, 15, -3.14);
    c.sim_set_reg(&sim, 31, 999.0);
    try testing.expectApproxEqAbs(1.5, sim.fp_regs[0], 0.001);
    try testing.expectApproxEqAbs(-3.14, sim.fp_regs[15], 0.001);
    try testing.expectApproxEqAbs(999.0, sim.fp_regs[31], 0.001);
}

test "simulator: sim_set_reg ignores out-of-range indices" {
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

test "simulator: sim_done is true with no instructions" {
    var sim = initDefaultSim();
    try testing.expect(c.sim_done(&sim));
}

test "simulator: sim_done is false with pending instructions" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    try testing.expect(!c.sim_done(&sim));
}

test "simulator: sim_step returns false when already done" {
    var sim = initDefaultSim();
    try testing.expect(!c.sim_step(&sim));
}

test "simulator: sim_step advances cycle counter" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = c.sim_step(&sim);
    try testing.expectEqual(@as(c_int, 1), sim.cycle);
    _ = c.sim_step(&sim);
    try testing.expectEqual(@as(c_int, 2), sim.cycle);
}

test "simulator: sim_run returns total cycles" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    const cycles = runToCompletion(&sim);
    try testing.expect(cycles > 0);
    try testing.expect(c.sim_done(&sim));
}
