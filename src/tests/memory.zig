// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! Load/Store tests.

const common = @import("common.zig");
const testing = common.testing;
const c = common.c;

const initSim = common.initSim;
const initDefaultSim = common.initDefaultSim;
const makeArithInst = common.makeArithInst;
const makeMemInst = common.makeMemInst;
const addInst = common.addInst;
const runToCompletion = common.runToCompletion;

test "memory: LD then ADD uses loaded value" {
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

test "memory: multiple LDs in parallel with 3 load buffers" {
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

test "memory: SD after LD completes without deadlock" {
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

test "memory: LD with zero offset" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 50.0);
    addInst(&sim, makeMemInst(c.OP_LD, 1, 0, 2));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(50.0, sim.fp_regs[1], 0.001);
}

test "memory: LD feeds MUL feeds ADD chain" {
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

test "memory: SD waits for base address register (Qk hazard)" {
    // This test covers the case where SD must wait for its base address
    // register (stored in Qk) to be computed by a prior instruction.
    // ADD.D F1, F2, F3 => F1 = base address
    // S.D F4, 0(F1)    => store F4 at address F1+0 (must wait for F1)
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_SD] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 50.0); // F2 = 50
    c.sim_set_reg(&sim, 3, 50.0); // F3 = 50
    c.sim_set_reg(&sim, 4, 42.0); // F4 = value to store
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3)); // F1 = 50+50 = 100 (base addr)
    addInst(&sim, makeMemInst(c.OP_SD, 4, 0, 1)); // Store F4 at 0(F1) - must wait for F1
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    // The store should complete; F1 should have the computed base address
    try testing.expectApproxEqAbs(100.0, sim.fp_regs[1], 0.001);
}

test "memory: SD waits for both base and value (Qj and Qk hazards)" {
    // Both the value to store (Qj) and the base address (Qk) are produced
    // by prior instructions, so SD must wait for both.
    // ADD.D F1, F2, F3 => F1 = base address
    // ADD.D F4, F5, F6 => F4 = value to store
    // S.D F4, 0(F1)    => store F4 at address F1+0 (waits for both F1 and F4)
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_SD] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 50.0); // F2 = 50
    c.sim_set_reg(&sim, 3, 50.0); // F3 = 50
    c.sim_set_reg(&sim, 5, 10.0); // F5 = 10
    c.sim_set_reg(&sim, 6, 32.0); // F6 = 32
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3)); // F1 = 100 (base addr)
    addInst(&sim, makeArithInst(c.OP_ADDD, 4, 5, 6)); // F4 = 42 (value to store)
    addInst(&sim, makeMemInst(c.OP_SD, 4, 0, 1)); // Store F4 at 0(F1)
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(100.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(42.0, sim.fp_regs[4], 0.001);
}
