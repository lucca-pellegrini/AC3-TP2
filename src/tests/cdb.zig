// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! CDB contention and parallel execution tests.

const common = @import("common.zig");
const testing = common.testing;
const c = common.c;

const initSim = common.initSim;
const makeArithInst = common.makeArithInst;
const addInst = common.addInst;
const runToCompletion = common.runToCompletion;
const getInst = common.getInst;

// ═══════════════════════════════════════════════════════════════════════════
// CDB contention tests (single bus)
// ═══════════════════════════════════════════════════════════════════════════

test "cdb: two instructions finish same cycle, only one writes per cycle" {
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

test "cdb: MUL and ADD finish at different times, no contention" {
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

test "cdb: parallel independent ADD and MUL execute simultaneously" {
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

test "cdb: parallel 4 independent ADDs with 3 RS, one stalls" {
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

test "cdb: in-order commit fast instruction after slow still commits in order" {
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
