// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! RAW, WAW, and structural hazard tests.

const common = @import("common.zig");
const testing = common.testing;
const c = common.c;

const initSim = common.initSim;
const initDefaultSim = common.initDefaultSim;
const initSimWith = common.initSimWith;
const makeArithInst = common.makeArithInst;
const addInst = common.addInst;
const runToCompletion = common.runToCompletion;
const getInst = common.getInst;

// ═══════════════════════════════════════════════════════════════════════════
// RAW hazard tests (Read-After-Write / true dependencies)
// ═══════════════════════════════════════════════════════════════════════════

test "hazards: RAW ADD then MUL depending on ADD result" {
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

test "hazards: RAW three-instruction chain ADD->MUL->SUB" {
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

test "hazards: RAW four-instruction deep chain" {
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

test "hazards: RAW MUL waits for ADD result, does not execute early" {
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

test "hazards: RAW both operands depend on different producers" {
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

test "hazards: WAW two instructions write same register, last wins" {
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

test "hazards: WAW later slow instruction overwrites earlier fast instruction" {
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

test "hazards: WAW third instruction reads correct value from chain" {
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

test "hazards: structural 1 Add RS, 3 ADDs must serialize" {
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

test "hazards: structural 2 Add RS, 2 ADDs can overlap" {
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

test "hazards: structural ADD and MUL use different RS types, no conflict" {
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
// WAR hazard tests (Write-After-Read)
// ═══════════════════════════════════════════════════════════════════════════

test "hazards: WAR write-after-read does not cause incorrect results" {
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
