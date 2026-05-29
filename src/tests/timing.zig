// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! Pipeline timing correctness tests.

const common = @import("common.zig");
const testing = common.testing;
const c = common.c;

const initSim = common.initSim;
const makeArithInst = common.makeArithInst;
const makeMemInst = common.makeMemInst;
const addInst = common.addInst;
const runToCompletion = common.runToCompletion;
const getInst = common.getInst;

test "timing: single ADD.D issue=1, exec=2-3, write=4" {
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

test "timing: single MUL.D with latency 4: issue=1, exec=2-5, write=6" {
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

test "timing: single DIV.D with latency 40" {
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

test "timing: two independent ADDs issue on consecutive cycles" {
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

test "timing: single L.D issue=1, exec=2-3, write=4" {
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

test "timing: custom latencies: latency 1 for ADD" {
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

test "timing: sim_run respects max_cycles limit" {
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
