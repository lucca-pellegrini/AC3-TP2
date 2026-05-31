// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! Tests for parse_register and file parser integration.

const common = @import("common.zig");
const std = common.std;
const testing = common.testing;
const c = common.c;
const runToCompletion = common.runToCompletion;

// ═══════════════════════════════════════════════════════════════════════════
// parse_register tests
// ═══════════════════════════════════════════════════════════════════════════

test "parser: parse_register valid F registers" {
    try testing.expectEqual(@as(c_int, 0), c.parse_register("F0"));
    try testing.expectEqual(@as(c_int, 6), c.parse_register("F6"));
    try testing.expectEqual(@as(c_int, 31), c.parse_register("F31"));
    try testing.expectEqual(@as(c_int, 10), c.parse_register("F10"));
    try testing.expectEqual(@as(c_int, 0), c.parse_register("f0")); // lowercase
}

test "parser: parse_register valid R registers" {
    try testing.expectEqual(@as(c_int, 0), c.parse_register("R0"));
    try testing.expectEqual(@as(c_int, 2), c.parse_register("R2"));
    try testing.expectEqual(@as(c_int, 31), c.parse_register("R31"));
    try testing.expectEqual(@as(c_int, 15), c.parse_register("r15")); // lowercase
}

test "parser: parse_register invalid inputs" {
    try testing.expectEqual(@as(c_int, -1), c.parse_register("X5"));
    try testing.expectEqual(@as(c_int, -1), c.parse_register(""));
    try testing.expectEqual(@as(c_int, -1), c.parse_register("F99")); // out of range
    try testing.expectEqual(@as(c_int, -1), c.parse_register("F-1")); // negative
    try testing.expectEqual(@as(c_int, -1), c.parse_register("F")); // no number
    try testing.expectEqual(@as(c_int, -1), c.parse_register("123")); // no prefix
    try testing.expectEqual(@as(c_int, -1), c.parse_register("Fabc")); // non-numeric
}

// ═══════════════════════════════════════════════════════════════════════════
// File parser integration tests
// ═══════════════════════════════════════════════════════════════════════════

test "parser: parse_input loads basic test file" {
    var cfg: c.TomasuloConfig = undefined;
    var sim: c.Simulator = undefined;
    const result = c.parse_input("simulations/basic.tom", &cfg, &sim);
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

test "parser: parse_input loads chain test file" {
    var cfg: c.TomasuloConfig = undefined;
    var sim: c.Simulator = undefined;
    const result = c.parse_input("simulations/chain.tom", &cfg, &sim);
    try testing.expectEqual(@as(c_int, 0), result);
    try testing.expectEqual(@as(c_int, 4), sim.num_instructions);
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(9.0, sim.fp_regs[4], 0.001);
    try testing.expectApproxEqAbs(13.0, sim.fp_regs[6], 0.001);
    try testing.expectApproxEqAbs(65.0, sim.fp_regs[8], 0.001);
}

test "parser: parse_input loads parallel test file" {
    var cfg: c.TomasuloConfig = undefined;
    var sim: c.Simulator = undefined;
    const result = c.parse_input("simulations/parallel.tom", &cfg, &sim);
    try testing.expectEqual(@as(c_int, 0), result);
    try testing.expectEqual(@as(c_int, 4), sim.num_instructions);
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(7.0, sim.fp_regs[4], 0.001);
    try testing.expectApproxEqAbs(21.0, sim.fp_regs[7], 0.001);
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[8], 0.001);
}

test "parser: parse_input loads Hennessy test file" {
    var cfg: c.TomasuloConfig = undefined;
    var sim: c.Simulator = undefined;
    const result = c.parse_input("simulations/hennessy.tom", &cfg, &sim);
    try testing.expectEqual(@as(c_int, 0), result);
    try testing.expectEqual(@as(c_int, 6), sim.num_instructions);
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(1225.0, sim.fp_regs[0], 0.01);
    try testing.expectApproxEqAbs(-111.0, sim.fp_regs[8], 0.01);
}

test "parser: parse_input loads structural hazard test file" {
    var cfg: c.TomasuloConfig = undefined;
    var sim: c.Simulator = undefined;
    const result = c.parse_input("simulations/structural.tom", &cfg, &sim);
    try testing.expectEqual(@as(c_int, 0), result);
    try testing.expectEqual(@as(c_int, 3), sim.num_instructions);
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[10], 0.001);
    try testing.expectApproxEqAbs(8.0, sim.fp_regs[11], 0.001);
    try testing.expectApproxEqAbs(16.0, sim.fp_regs[12], 0.001);
}

test "parser: parse_input returns error for nonexistent file" {
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
