// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! Property-based / fuzz tests using random data.
//! These tests verify invariants that should hold regardless of input.

const common = @import("common.zig");
const std = common.std;
const testing = common.testing;
const c = common.c;

const initSim = common.initSim;
const initDefaultSim = common.initDefaultSim;
const makeArithInst = common.makeArithInst;
const makeMemInst = common.makeMemInst;
const addInst = common.addInst;
const runToCompletion = common.runToCompletion;
const getInst = common.getInst;

// ═══════════════════════════════════════════════════════════════════════════
// Random number generation helpers
// ═══════════════════════════════════════════════════════════════════════════

const RNG = std.Random.DefaultPrng;

fn makeRng(seed: u64) RNG {
    return RNG.init(seed);
}

fn randomReg(rng: *RNG) c_int {
    return @intCast(rng.random().intRangeAtMost(u5, 0, c.MAX_FP_REGISTERS - 1));
}

fn randomArithOp(rng: *RNG) c_uint {
    const ops = [_]c_uint{ c.OP_ADDD, c.OP_SUBD, c.OP_MULTD, c.OP_DIVD };
    return ops[rng.random().intRangeAtMost(usize, 0, ops.len - 1)];
}

fn randomOp(rng: *RNG) c_uint {
    const ops = [_]c_uint{ c.OP_ADDD, c.OP_SUBD, c.OP_MULTD, c.OP_DIVD, c.OP_LD, c.OP_SD };
    return ops[rng.random().intRangeAtMost(usize, 0, ops.len - 1)];
}

fn randomFloat(rng: *RNG) f64 {
    // Generate floats in a reasonable range to avoid overflow issues
    const r = rng.random();
    const sign: f64 = if (r.boolean()) 1.0 else -1.0;
    return sign * r.float(f64) * 1000.0;
}

fn randomLatency(rng: *RNG) c_int {
    return @intCast(rng.random().intRangeAtMost(u8, 1, 20));
}

fn randomRSCount(rng: *RNG) c_int {
    return @intCast(rng.random().intRangeAtMost(u8, 1, 4));
}

fn randomImm(rng: *RNG) c_int {
    return @intCast(rng.random().intRangeAtMost(i16, -500, 500));
}

// ═══════════════════════════════════════════════════════════════════════════
// Property: Simulator always terminates
// ═══════════════════════════════════════════════════════════════════════════

test "fuzz: random arithmetic programs always terminate" {
    const seeds = [_]u64{ 0xDEAD, 0xBEEF, 0xCAFE, 0xF00D, 42, 123, 999, 0x12345678 };

    for (seeds) |seed| {
        var rng = makeRng(seed);

        // Random configuration
        var cfg = c.config_default();
        cfg.latency[c.OP_ADDD] = randomLatency(&rng);
        cfg.latency[c.OP_SUBD] = randomLatency(&rng);
        cfg.latency[c.OP_MULTD] = randomLatency(&rng);
        cfg.latency[c.OP_DIVD] = randomLatency(&rng);
        cfg.num_rs[c.RS_ADD] = randomRSCount(&rng);
        cfg.num_rs[c.RS_MULT] = randomRSCount(&rng);

        var sim = initSim(&cfg);

        // Set random initial register values
        for (0..c.MAX_FP_REGISTERS) |i| {
            c.sim_set_reg(&sim, @intCast(i), randomFloat(&rng));
        }

        // Add random arithmetic instructions
        const num_insts = rng.random().intRangeAtMost(usize, 1, 20);
        for (0..num_insts) |_| {
            const op = randomArithOp(&rng);
            const dest = randomReg(&rng);
            const src1 = randomReg(&rng);
            const src2 = randomReg(&rng);
            addInst(&sim, makeArithInst(op, dest, src1, src2));
        }

        // Must terminate within reasonable cycles
        const cycles = c.sim_run(&sim, 1000);
        try testing.expect(cycles < 1000);
        try testing.expect(c.sim_done(&sim));
    }
}

test "fuzz: random programs with loads always terminate" {
    const seeds = [_]u64{ 0x1111, 0x2222, 0x3333, 0x4444, 0x5555 };

    for (seeds) |seed| {
        var rng = makeRng(seed);

        var cfg = c.config_default();
        cfg.latency[c.OP_LD] = randomLatency(&rng);
        cfg.latency[c.OP_ADDD] = randomLatency(&rng);
        cfg.num_rs[c.RS_LOAD] = randomRSCount(&rng);
        cfg.num_rs[c.RS_ADD] = randomRSCount(&rng);

        var sim = initSim(&cfg);

        // Set random base register values
        for (0..c.MAX_FP_REGISTERS) |i| {
            c.sim_set_reg(&sim, @intCast(i), @floatFromInt(rng.random().intRangeAtMost(i32, 0, 1000)));
        }

        // Mix of loads and adds
        const num_insts = rng.random().intRangeAtMost(usize, 1, 15);
        for (0..num_insts) |_| {
            if (rng.random().boolean()) {
                // Load
                addInst(&sim, makeMemInst(c.OP_LD, randomReg(&rng), randomImm(&rng), randomReg(&rng)));
            } else {
                // Add
                addInst(&sim, makeArithInst(c.OP_ADDD, randomReg(&rng), randomReg(&rng), randomReg(&rng)));
            }
        }

        const cycles = c.sim_run(&sim, 1000);
        try testing.expect(cycles < 1000);
        try testing.expect(c.sim_done(&sim));
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Property: Instruction timing invariants
// ═══════════════════════════════════════════════════════════════════════════

test "fuzz: issue_cycle <= exec_start <= exec_end <= write_cycle for all instructions" {
    const seeds = [_]u64{ 0xAAAA, 0xBBBB, 0xCCCC, 0xDDDD };

    for (seeds) |seed| {
        var rng = makeRng(seed);

        var cfg = c.config_default();
        cfg.latency[c.OP_ADDD] = randomLatency(&rng);
        cfg.latency[c.OP_SUBD] = randomLatency(&rng);
        cfg.latency[c.OP_MULTD] = randomLatency(&rng);
        cfg.latency[c.OP_DIVD] = randomLatency(&rng);
        cfg.num_rs[c.RS_ADD] = randomRSCount(&rng);
        cfg.num_rs[c.RS_MULT] = randomRSCount(&rng);

        var sim = initSim(&cfg);

        for (0..c.MAX_FP_REGISTERS) |i| {
            c.sim_set_reg(&sim, @intCast(i), randomFloat(&rng));
        }

        const num_insts = rng.random().intRangeAtMost(usize, 5, 20);
        for (0..num_insts) |_| {
            addInst(&sim, makeArithInst(randomArithOp(&rng), randomReg(&rng), randomReg(&rng), randomReg(&rng)));
        }

        _ = runToCompletion(&sim);

        // Verify timing invariants for all instructions
        for (0..@as(usize, @intCast(sim.num_instructions))) |i| {
            const inst = getInst(&sim, i);
            try testing.expect(inst.issue_cycle > 0);
            try testing.expect(inst.issue_cycle <= inst.exec_start);
            try testing.expect(inst.exec_start <= inst.exec_end);
            try testing.expect(inst.exec_end <= inst.write_cycle);
        }
    }
}

test "fuzz: instructions issue in program order" {
    const seeds = [_]u64{ 0x9999, 0x8888, 0x7777, 0x6666 };

    for (seeds) |seed| {
        var rng = makeRng(seed);

        var cfg = c.config_default();
        cfg.latency[c.OP_ADDD] = randomLatency(&rng);
        cfg.latency[c.OP_MULTD] = randomLatency(&rng);
        cfg.num_rs[c.RS_ADD] = randomRSCount(&rng);
        cfg.num_rs[c.RS_MULT] = randomRSCount(&rng);

        var sim = initSim(&cfg);

        for (0..c.MAX_FP_REGISTERS) |i| {
            c.sim_set_reg(&sim, @intCast(i), randomFloat(&rng));
        }

        const num_insts = rng.random().intRangeAtMost(usize, 3, 15);
        for (0..num_insts) |_| {
            const op: c_uint = if (rng.random().boolean()) c.OP_ADDD else c.OP_MULTD;
            addInst(&sim, makeArithInst(op, randomReg(&rng), randomReg(&rng), randomReg(&rng)));
        }

        _ = runToCompletion(&sim);

        // Verify in-order issue
        var prev_issue: c_int = 0;
        for (0..@as(usize, @intCast(sim.num_instructions))) |i| {
            const inst = getInst(&sim, i);
            try testing.expect(inst.issue_cycle >= prev_issue);
            prev_issue = inst.issue_cycle;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Property: Arithmetic correctness with random operands
// ═══════════════════════════════════════════════════════════════════════════

test "fuzz: ADD.D computes correct result for random operands" {
    const seeds = [_]u64{ 111, 222, 333, 444, 555, 666, 777, 888 };

    for (seeds) |seed| {
        var rng = makeRng(seed);
        const a = randomFloat(&rng);
        const b = randomFloat(&rng);

        var sim = initDefaultSim();
        c.sim_set_reg(&sim, 2, a);
        c.sim_set_reg(&sim, 3, b);
        addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
        _ = runToCompletion(&sim);

        const expected = a + b;
        try testing.expectApproxEqAbs(expected, sim.fp_regs[1], 0.0001);
    }
}

test "fuzz: SUB.D computes correct result for random operands" {
    const seeds = [_]u64{ 101, 202, 303, 404, 505 };

    for (seeds) |seed| {
        var rng = makeRng(seed);
        const a = randomFloat(&rng);
        const b = randomFloat(&rng);

        var sim = initDefaultSim();
        c.sim_set_reg(&sim, 2, a);
        c.sim_set_reg(&sim, 3, b);
        addInst(&sim, makeArithInst(c.OP_SUBD, 1, 2, 3));
        _ = runToCompletion(&sim);

        const expected = a - b;
        try testing.expectApproxEqAbs(expected, sim.fp_regs[1], 0.0001);
    }
}

test "fuzz: MUL.D computes correct result for random operands" {
    const seeds = [_]u64{ 11, 22, 33, 44, 55 };

    for (seeds) |seed| {
        var rng = makeRng(seed);
        // Use smaller values to avoid overflow
        const a = rng.random().float(f64) * 100.0;
        const b = rng.random().float(f64) * 100.0;

        var sim = initDefaultSim();
        c.sim_set_reg(&sim, 2, a);
        c.sim_set_reg(&sim, 3, b);
        addInst(&sim, makeArithInst(c.OP_MULTD, 1, 2, 3));
        _ = runToCompletion(&sim);

        const expected = a * b;
        try testing.expectApproxEqRel(expected, sim.fp_regs[1], 0.0001);
    }
}

test "fuzz: DIV.D computes correct result for random non-zero divisors" {
    const seeds = [_]u64{ 1, 2, 3, 4, 5 };

    for (seeds) |seed| {
        var rng = makeRng(seed);
        const a = randomFloat(&rng);
        // Ensure non-zero divisor
        var b = randomFloat(&rng);
        while (@abs(b) < 0.001) {
            b = randomFloat(&rng);
        }

        var sim = initDefaultSim();
        c.sim_set_reg(&sim, 2, a);
        c.sim_set_reg(&sim, 3, b);
        addInst(&sim, makeArithInst(c.OP_DIVD, 1, 2, 3));
        _ = runToCompletion(&sim);

        const expected = a / b;
        try testing.expectApproxEqRel(expected, sim.fp_regs[1], 0.0001);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Property: RAW dependencies preserve correctness
// ═══════════════════════════════════════════════════════════════════════════

test "fuzz: chained dependencies compute correct results" {
    const seeds = [_]u64{ 0xFACE, 0xBEAD, 0xFEED, 0xDEED };

    for (seeds) |seed| {
        var rng = makeRng(seed);

        var cfg = c.config_default();
        cfg.latency[c.OP_ADDD] = randomLatency(&rng);
        cfg.num_rs[c.RS_ADD] = randomRSCount(&rng);

        var sim = initSim(&cfg);

        // F0 is initial value
        const initial = randomFloat(&rng);
        c.sim_set_reg(&sim, 0, initial);

        // Chain: F1 = F0 + F0, F2 = F1 + F0, F3 = F2 + F0, ...
        const chain_len = rng.random().intRangeAtMost(usize, 2, 6);
        for (1..chain_len + 1) |i| {
            const dest: c_int = @intCast(i);
            const src1: c_int = @intCast(i - 1);
            addInst(&sim, makeArithInst(c.OP_ADDD, dest, src1, 0));
        }

        _ = runToCompletion(&sim);

        // Verify each register has correct value
        var expected = initial;
        for (1..chain_len + 1) |i| {
            expected = expected + initial;
            try testing.expectApproxEqRel(expected, sim.fp_regs[i], 0.0001);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Property: WAW hazards preserve last-writer-wins semantics
// ═══════════════════════════════════════════════════════════════════════════

test "fuzz: multiple writes to same register, last write wins" {
    const seeds = [_]u64{ 0x1234, 0x5678, 0x9ABC, 0xDEF0 };

    for (seeds) |seed| {
        var rng = makeRng(seed);

        var cfg = c.config_default();
        cfg.latency[c.OP_ADDD] = randomLatency(&rng);
        cfg.num_rs[c.RS_ADD] = randomRSCount(&rng);

        var sim = initSim(&cfg);

        // Set up source registers with known values
        const values = [_]f64{
            randomFloat(&rng),
            randomFloat(&rng),
            randomFloat(&rng),
            randomFloat(&rng),
        };
        c.sim_set_reg(&sim, 2, values[0]);
        c.sim_set_reg(&sim, 3, values[1]);
        c.sim_set_reg(&sim, 4, values[2]);
        c.sim_set_reg(&sim, 5, values[3]);

        // Multiple independent writes to F1
        addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3)); // F1 = values[0] + values[1]
        addInst(&sim, makeArithInst(c.OP_ADDD, 1, 4, 5)); // F1 = values[2] + values[3] (last write)

        _ = runToCompletion(&sim);

        // Last write should win
        const expected = values[2] + values[3];
        try testing.expectApproxEqRel(expected, sim.fp_regs[1], 0.0001);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Property: Cycle count is monotonically increasing
// ═══════════════════════════════════════════════════════════════════════════

test "fuzz: cycle counter monotonically increases during simulation" {
    const seeds = [_]u64{ 0xA1B2, 0xC3D4, 0xE5F6 };

    for (seeds) |seed| {
        var rng = makeRng(seed);

        var cfg = c.config_default();
        cfg.latency[c.OP_ADDD] = randomLatency(&rng);
        cfg.latency[c.OP_MULTD] = randomLatency(&rng);
        cfg.num_rs[c.RS_ADD] = randomRSCount(&rng);
        cfg.num_rs[c.RS_MULT] = randomRSCount(&rng);

        var sim = initSim(&cfg);

        for (0..c.MAX_FP_REGISTERS) |i| {
            c.sim_set_reg(&sim, @intCast(i), randomFloat(&rng));
        }

        const num_insts = rng.random().intRangeAtMost(usize, 3, 10);
        for (0..num_insts) |_| {
            addInst(&sim, makeArithInst(randomArithOp(&rng), randomReg(&rng), randomReg(&rng), randomReg(&rng)));
        }

        var prev_cycle: c_int = 0;
        while (!c.sim_done(&sim)) {
            _ = c.sim_step(&sim);
            try testing.expect(sim.cycle > prev_cycle);
            prev_cycle = sim.cycle;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Property: All instructions eventually commit
// ═══════════════════════════════════════════════════════════════════════════

test "fuzz: committed count equals num_instructions after completion" {
    const seeds = [_]u64{ 0x1A2B, 0x3C4D, 0x5E6F, 0x7081 };

    for (seeds) |seed| {
        var rng = makeRng(seed);

        var cfg = c.config_default();
        cfg.latency[c.OP_ADDD] = randomLatency(&rng);
        cfg.latency[c.OP_SUBD] = randomLatency(&rng);
        cfg.latency[c.OP_MULTD] = randomLatency(&rng);
        cfg.latency[c.OP_DIVD] = randomLatency(&rng);
        cfg.num_rs[c.RS_ADD] = randomRSCount(&rng);
        cfg.num_rs[c.RS_MULT] = randomRSCount(&rng);

        var sim = initSim(&cfg);

        for (0..c.MAX_FP_REGISTERS) |i| {
            c.sim_set_reg(&sim, @intCast(i), randomFloat(&rng));
        }

        const num_insts = rng.random().intRangeAtMost(usize, 1, 20);
        for (0..num_insts) |_| {
            addInst(&sim, makeArithInst(randomArithOp(&rng), randomReg(&rng), randomReg(&rng), randomReg(&rng)));
        }

        _ = runToCompletion(&sim);

        try testing.expectEqual(sim.num_instructions, sim.committed);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Property: L.D computes address correctly
// ═══════════════════════════════════════════════════════════════════════════

test "fuzz: L.D computes effective address correctly" {
    const seeds = [_]u64{ 0xABCD, 0xEF01, 0x2345, 0x6789 };

    for (seeds) |seed| {
        var rng = makeRng(seed);
        const base: f64 = @floatFromInt(rng.random().intRangeAtMost(i32, 0, 1000));
        const imm = rng.random().intRangeAtMost(i16, -500, 500);

        var sim = initDefaultSim();
        c.sim_set_reg(&sim, 2, base);
        addInst(&sim, makeMemInst(c.OP_LD, 1, imm, 2));
        _ = runToCompletion(&sim);

        // L.D simulates loading the effective address as the value
        const expected = base + @as(f64, @floatFromInt(imm));
        try testing.expectApproxEqAbs(expected, sim.fp_regs[1], 0.001);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Property: Configuration extremes don't break the simulator
// ═══════════════════════════════════════════════════════════════════════════

test "fuzz: minimal RS configuration still works" {
    const seeds = [_]u64{ 0x0001, 0x0002, 0x0003 };

    for (seeds) |seed| {
        var rng = makeRng(seed);

        var cfg = c.config_default();
        // Minimal: 1 RS of each type
        cfg.num_rs[c.RS_ADD] = 1;
        cfg.num_rs[c.RS_MULT] = 1;
        cfg.num_rs[c.RS_LOAD] = 1;
        cfg.num_rs[c.RS_STORE] = 1;
        cfg.latency[c.OP_ADDD] = randomLatency(&rng);
        cfg.latency[c.OP_MULTD] = randomLatency(&rng);

        var sim = initSim(&cfg);

        for (0..c.MAX_FP_REGISTERS) |i| {
            c.sim_set_reg(&sim, @intCast(i), randomFloat(&rng));
        }

        // Add several instructions that will cause structural hazards
        for (0..8) |_| {
            addInst(&sim, makeArithInst(c.OP_ADDD, randomReg(&rng), randomReg(&rng), randomReg(&rng)));
        }

        const cycles = c.sim_run(&sim, 500);
        try testing.expect(cycles < 500);
        try testing.expect(c.sim_done(&sim));
    }
}

test "fuzz: high latency configuration still terminates" {
    const seeds = [_]u64{ 0xF001, 0xF002, 0xF003 };

    for (seeds) |seed| {
        var rng = makeRng(seed);

        var cfg = c.config_default();
        // High latencies
        cfg.latency[c.OP_ADDD] = 15;
        cfg.latency[c.OP_SUBD] = 15;
        cfg.latency[c.OP_MULTD] = 20;
        cfg.latency[c.OP_DIVD] = 40;
        cfg.num_rs[c.RS_ADD] = randomRSCount(&rng);
        cfg.num_rs[c.RS_MULT] = randomRSCount(&rng);

        var sim = initSim(&cfg);

        for (0..c.MAX_FP_REGISTERS) |i| {
            c.sim_set_reg(&sim, @intCast(i), randomFloat(&rng));
        }

        const num_insts = rng.random().intRangeAtMost(usize, 3, 8);
        for (0..num_insts) |_| {
            addInst(&sim, makeArithInst(randomArithOp(&rng), randomReg(&rng), randomReg(&rng), randomReg(&rng)));
        }

        const cycles = c.sim_run(&sim, 2000);
        try testing.expect(cycles < 2000);
        try testing.expect(c.sim_done(&sim));
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Property: Empty program terminates immediately
// ═══════════════════════════════════════════════════════════════════════════

test "fuzz: empty program with random config terminates immediately" {
    const seeds = [_]u64{ 0xE001, 0xE002, 0xE003, 0xE004 };

    for (seeds) |seed| {
        var rng = makeRng(seed);

        var cfg = c.config_default();
        cfg.latency[c.OP_ADDD] = randomLatency(&rng);
        cfg.latency[c.OP_MULTD] = randomLatency(&rng);
        cfg.num_rs[c.RS_ADD] = randomRSCount(&rng);
        cfg.num_rs[c.RS_MULT] = randomRSCount(&rng);

        var sim = initSim(&cfg);

        // Random register values but no instructions
        for (0..c.MAX_FP_REGISTERS) |i| {
            c.sim_set_reg(&sim, @intCast(i), randomFloat(&rng));
        }

        try testing.expect(c.sim_done(&sim));
        const cycles = c.sim_run(&sim, 100);
        try testing.expectEqual(@as(c_int, 0), cycles);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Property: Register file integrity
// ═══════════════════════════════════════════════════════════════════════════

test "fuzz: untouched registers preserve initial values" {
    const seeds = [_]u64{ 0xD001, 0xD002, 0xD003 };

    for (seeds) |seed| {
        var rng = makeRng(seed);

        var cfg = c.config_default();
        cfg.latency[c.OP_ADDD] = randomLatency(&rng);
        cfg.num_rs[c.RS_ADD] = randomRSCount(&rng);

        var sim = initSim(&cfg);

        // Set all registers to known values
        var initial_values: [c.MAX_FP_REGISTERS]f64 = undefined;
        for (0..c.MAX_FP_REGISTERS) |i| {
            initial_values[i] = randomFloat(&rng);
            c.sim_set_reg(&sim, @intCast(i), initial_values[i]);
        }

        // Only touch registers 0-3 (destinations)
        addInst(&sim, makeArithInst(c.OP_ADDD, 0, 4, 5));
        addInst(&sim, makeArithInst(c.OP_ADDD, 1, 6, 7));
        addInst(&sim, makeArithInst(c.OP_ADDD, 2, 8, 9));
        addInst(&sim, makeArithInst(c.OP_ADDD, 3, 10, 11));

        _ = runToCompletion(&sim);

        // Registers 4-31 should be unchanged
        for (4..c.MAX_FP_REGISTERS) |i| {
            try testing.expectApproxEqRel(initial_values[i], sim.fp_regs[i], 0.0001);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Property: Associativity stress test
// ═══════════════════════════════════════════════════════════════════════════

test "fuzz: independent parallel adds compute correct sum" {
    const seeds = [_]u64{ 0xC001, 0xC002, 0xC003 };

    for (seeds) |seed| {
        var rng = makeRng(seed);

        var cfg = c.config_default();
        cfg.latency[c.OP_ADDD] = randomLatency(&rng);
        cfg.num_rs[c.RS_ADD] = 3; // Allow some parallelism

        var sim = initSim(&cfg);

        // Set up 8 values in F0-F7
        var sum: f64 = 0;
        for (0..8) |i| {
            const val = randomFloat(&rng);
            c.sim_set_reg(&sim, @intCast(i), val);
            sum += val;
        }

        // Pairwise add: F8=F0+F1, F9=F2+F3, F10=F4+F5, F11=F6+F7
        addInst(&sim, makeArithInst(c.OP_ADDD, 8, 0, 1));
        addInst(&sim, makeArithInst(c.OP_ADDD, 9, 2, 3));
        addInst(&sim, makeArithInst(c.OP_ADDD, 10, 4, 5));
        addInst(&sim, makeArithInst(c.OP_ADDD, 11, 6, 7));

        // Second level: F12=F8+F9, F13=F10+F11
        addInst(&sim, makeArithInst(c.OP_ADDD, 12, 8, 9));
        addInst(&sim, makeArithInst(c.OP_ADDD, 13, 10, 11));

        // Final: F14=F12+F13
        addInst(&sim, makeArithInst(c.OP_ADDD, 14, 12, 13));

        _ = runToCompletion(&sim);

        // F14 should contain the sum of all 8 values
        try testing.expectApproxEqRel(sum, sim.fp_regs[14], 0.0001);
    }
}
