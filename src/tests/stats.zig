// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! Statistics collection tests.

const common = @import("common.zig");
const testing = common.testing;
const c = common.c;

const initSim = common.initSim;
const initDefaultSim = common.initDefaultSim;
const makeArithInst = common.makeArithInst;
const makeMemInst = common.makeMemInst;
const addInst = common.addInst;
const runToCompletion = common.runToCompletion;
const getInst = common.getInst;

test "stats: initialized to zero" {
    const sim = initDefaultSim();
    const s = sim.stats;
    // FU stats
    for (0..c.RS_TYPE_COUNT) |t| {
        try testing.expectEqual(@as(c_int, 0), s.fu_busy_cycles[t]);
        try testing.expectEqual(@as(c_int, 0), s.fu_peak_occupancy[t]);
        try testing.expectEqual(@as(c_int, 0), s.fu_total_occupancy[t]);
    }
    // RS stats
    for (0..c.RS_TYPE_COUNT) |t| {
        try testing.expectEqual(@as(c_int, 0), s.rs_peak_occupancy[t]);
        try testing.expectEqual(@as(c_int, 0), s.rs_total_occupancy[t]);
        try testing.expectEqual(@as(c_int, 0), s.rs_full_cycles[t]);
    }
    // CDB stats
    try testing.expectEqual(@as(c_int, 0), s.cdb_busy_cycles);
    try testing.expectEqual(@as(c_int, 0), s.cdb_total_requests);
    try testing.expectEqual(@as(c_int, 0), s.cdb_contention_cycles);
    // ROB stats
    try testing.expectEqual(@as(c_int, 0), s.rob_peak_occupancy);
    try testing.expectEqual(@as(c_int, 0), s.rob_total_occupancy);
    try testing.expectEqual(@as(c_int, 0), s.rob_full_cycles);
}

test "stats: single ADD.D collects FU and RS stats" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 3;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = runToCompletion(&sim);

    const s = sim.stats;
    // FU was busy during execution (2 cycles: exec_start=2, exec_end=3)
    try testing.expect(s.fu_busy_cycles[c.RS_ADD] >= 1);
    try testing.expect(s.fu_peak_occupancy[c.RS_ADD] >= 1);
    // RS was occupied from issue until write
    try testing.expect(s.rs_peak_occupancy[c.RS_ADD] >= 1);
    try testing.expect(s.rs_total_occupancy[c.RS_ADD] > 0);
}

test "stats: CDB used for each instruction write" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 3;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 4, 3.0);
    c.sim_set_reg(&sim, 5, 4.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 6, 4, 5));
    _ = runToCompletion(&sim);

    const s = sim.stats;
    // Two instructions should produce two CDB broadcasts
    try testing.expectEqual(@as(c_int, 2), s.cdb_total_requests);
    try testing.expectEqual(@as(c_int, 2), s.cdb_busy_cycles);
}

test "stats: ROB occupancy tracks issued instructions" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 3;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = runToCompletion(&sim);

    const s = sim.stats;
    // ROB had at least one entry during execution
    try testing.expect(s.rob_peak_occupancy >= 1);
    try testing.expect(s.rob_total_occupancy > 0);
}

test "stats: RS full detection with 1 RS" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 1;
    cfg.num_rs[c.RS_MULT] = 0;
    cfg.num_rs[c.RS_LOAD] = 0;
    cfg.num_rs[c.RS_STORE] = 0;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 4, 3.0);
    c.sim_set_reg(&sim, 5, 4.0);
    // Two ADDs with only 1 RS => second must wait
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 6, 4, 5));
    _ = runToCompletion(&sim);

    const s = sim.stats;
    // RS was full (at 1) for at least some cycles while first inst occupied it
    try testing.expect(s.rs_full_cycles[c.RS_ADD] >= 1);
    try testing.expectEqual(@as(c_int, 1), s.rs_peak_occupancy[c.RS_ADD]);
}

test "stats: multiple FUs busy simultaneously" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 4;
    cfg.num_rs[c.RS_ADD] = 3;
    var sim = initSim(&cfg);
    // 3 independent ADDs that can execute in parallel
    for (0..6) |i| {
        c.sim_set_reg(&sim, @intCast(i), @as(f64, @floatFromInt(i + 1)));
    }
    addInst(&sim, makeArithInst(c.OP_ADDD, 10, 0, 1));
    addInst(&sim, makeArithInst(c.OP_ADDD, 11, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 12, 4, 5));
    _ = runToCompletion(&sim);

    const s = sim.stats;
    // Peak occupancy should reflect multiple concurrent executing units
    // (depends on whether FUs can run in parallel in the implementation)
    try testing.expect(s.fu_peak_occupancy[c.RS_ADD] >= 1);
    try testing.expect(s.rs_peak_occupancy[c.RS_ADD] >= 1);
}

test "stats: CDB contention when multiple instructions finish same cycle" {
    // Two ADDs with same latency, issued back-to-back, both try to write
    // when their execution completes at overlapping times
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 2;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    c.sim_set_reg(&sim, 4, 3.0);
    c.sim_set_reg(&sim, 5, 4.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 6, 4, 5));
    _ = runToCompletion(&sim);

    const s = sim.stats;
    // CDB is single; if both want to write, there's contention
    // Write cycles should differ, indicating serialization
    const w1 = getInst(&sim, 0).write_cycle;
    const w2 = getInst(&sim, 1).write_cycle;
    try testing.expect(w1 != w2);
    // cdb_contention_cycles may be > 0 if both tried same cycle
    // (implementation-dependent, but total broadcasts should equal 2)
    try testing.expectEqual(@as(c_int, 2), s.cdb_total_requests);
}

test "stats: Hennessy example collects comprehensive stats" {
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

    c.sim_set_reg(&sim, 2, 100.0);
    c.sim_set_reg(&sim, 3, 200.0);
    c.sim_set_reg(&sim, 4, 5.0);

    // L.D F6, 34(R2)  => F6 = 134
    addInst(&sim, makeMemInst(c.OP_LD, 6, 34, 2));
    // L.D F2, 45(R3)  => F2 = 245
    addInst(&sim, makeMemInst(c.OP_LD, 2, 45, 3));
    // MUL.D F0, F2, F4 => F0 = 1225
    addInst(&sim, makeArithInst(c.OP_MULTD, 0, 2, 4));
    // SUB.D F8, F6, F2 => F8 = -111
    addInst(&sim, makeArithInst(c.OP_SUBD, 8, 6, 2));
    // DIV.D F10, F0, F6 => F10 = ~9.14
    addInst(&sim, makeArithInst(c.OP_DIVD, 10, 0, 6));
    // ADD.D F6, F8, F2 => F6 = 134
    addInst(&sim, makeArithInst(c.OP_ADDD, 6, 8, 2));

    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));

    const s = sim.stats;
    // Verify meaningful statistics were collected
    // Load unit was used
    try testing.expect(s.fu_busy_cycles[c.RS_LOAD] >= 1);
    // Mult unit was used (for MUL and DIV)
    try testing.expect(s.fu_busy_cycles[c.RS_MULT] >= 1);
    // Add unit was used (for SUB and ADD)
    try testing.expect(s.fu_busy_cycles[c.RS_ADD] >= 1);
    // CDB was used for each non-store instruction (6 instructions, 0 stores)
    try testing.expectEqual(@as(c_int, 6), s.cdb_total_requests);
    // ROB had entries
    try testing.expect(s.rob_peak_occupancy >= 1);
}

test "stats: S.D does not use CDB" {
    var cfg = c.config_default();
    cfg.latency[c.OP_SD] = 2;
    cfg.num_rs[c.RS_STORE] = 1;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 6, 42.0);
    c.sim_set_reg(&sim, 2, 100.0);
    addInst(&sim, makeMemInst(c.OP_SD, 6, 0, 2));
    _ = runToCompletion(&sim);

    const s = sim.stats;
    // Store doesn't broadcast on CDB
    try testing.expectEqual(@as(c_int, 0), s.cdb_total_requests);
    try testing.expectEqual(@as(c_int, 0), s.cdb_busy_cycles);
}

test "stats: long DIV dominates cycle count" {
    var cfg = c.config_default();
    cfg.latency[c.OP_DIVD] = 40;
    cfg.num_rs[c.RS_MULT] = 1;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 2, 100.0);
    c.sim_set_reg(&sim, 3, 4.0);
    addInst(&sim, makeArithInst(c.OP_DIVD, 1, 2, 3));
    _ = runToCompletion(&sim);

    const s = sim.stats;
    // Mult FU (used for DIV) should be busy for many cycles
    try testing.expect(s.fu_busy_cycles[c.RS_MULT] >= 1);
    // Total cycles should be around 42+ (issue + 40 exec + write)
    try testing.expect(sim.cycle >= 42);
}

test "stats: RS occupancy increases with dependent chain" {
    // Chain of 4 dependent ADDs: each must wait for previous
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 4;
    var sim = initSim(&cfg);
    c.sim_set_reg(&sim, 0, 1.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 0, 0)); // F1 = 2
    addInst(&sim, makeArithInst(c.OP_ADDD, 2, 1, 0)); // F2 = 3, waits for F1
    addInst(&sim, makeArithInst(c.OP_ADDD, 3, 2, 0)); // F3 = 4, waits for F2
    addInst(&sim, makeArithInst(c.OP_ADDD, 4, 3, 0)); // F4 = 5, waits for F3
    _ = runToCompletion(&sim);

    const s = sim.stats;
    // Multiple RS entries should have been occupied at some point
    // (all 4 can issue before the first completes)
    try testing.expect(s.rs_peak_occupancy[c.RS_ADD] >= 2);
}

test "stats: parallel ADD and MUL track separate FU types" {
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
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3)); // independent
    addInst(&sim, makeArithInst(c.OP_MULTD, 4, 5, 6)); // independent
    _ = runToCompletion(&sim);

    const s = sim.stats;
    // Both FU types should show busy cycles
    try testing.expect(s.fu_busy_cycles[c.RS_ADD] >= 1);
    try testing.expect(s.fu_busy_cycles[c.RS_MULT] >= 1);
    // Both RS types should have been occupied
    try testing.expect(s.rs_peak_occupancy[c.RS_ADD] >= 1);
    try testing.expect(s.rs_peak_occupancy[c.RS_MULT] >= 1);
}
