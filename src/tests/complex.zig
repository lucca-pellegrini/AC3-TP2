// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! Hennessy & Patterson textbook example and complex scenario tests.

const common = @import("common.zig");
const testing = common.testing;
const c = common.c;

const initSim = common.initSim;
const initDefaultSim = common.initDefaultSim;
const makeArithInst = common.makeArithInst;
const makeMemInst = common.makeMemInst;
const addInst = common.addInst;
const runToCompletion = common.runToCompletion;

// ═══════════════════════════════════════════════════════════════════════════
// Hennessy & Patterson textbook example
// ═══════════════════════════════════════════════════════════════════════════

test "complex: Hennessy classic L.D L.D MUL.D SUB.D DIV.D ADD.D" {
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
// Complex scenario tests
// ═══════════════════════════════════════════════════════════════════════════

test "complex: register F0 can be used as source and destination" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 0, 7.0);
    c.sim_set_reg(&sim, 1, 3.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 0, 0, 1)); // F0 = F0 + F1 = 10
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(10.0, sim.fp_regs[0], 0.001);
}

test "complex: multiple writes to same register in sequence produce correct final value" {
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

test "complex: back-to-back dependent ADDs with minimal latency" {
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

test "complex: large number of independent instructions" {
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

test "complex: mixed operations ADD, SUB, MUL, DIV all in one program" {
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
